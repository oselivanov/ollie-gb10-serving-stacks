#!/bin/bash

LAUNCH_SCRIPT="${DIR}/run/${SELF}_launcher.sh"
MODEL_REPO="${HF_CACHE_DIR}/hub/models--${MODEL//\//--}"

SVD_REPO=https://github.com/eugr/spark-vllm-docker
SVD_REF=e5174b8c56c96e2ec2b5d63a8022075d1c60bad3
SVD_DIR="${DIR}/.deps/spark-vllm-docker"
LAUNCHER="${SVD_DIR}/launch-cluster.sh"

if [[ "${USE_LOCAL_IMAGE}" == "1" ]]; then
    IMAGE="${LOCAL_IMAGE}"
else
    IMAGE="${DOCKER_HUB_IMAGE}"
fi

PERF_SED=(
    -E
    -e 's/, Deferred: [0-9]+ reqs//'
    -e 's/^.*INFO ([0-9]{2})-([0-9]{2}) ([0-9]{2}:[0-9]{2}:[0-9]{2}).*Avg prompt throughput: ([0-9.]+) tokens\/s, Avg generation throughput: ([0-9.]+) tokens\/s, Running: ([0-9]+) reqs, Waiting: ([0-9]+) reqs, GPU KV cache usage: ([0-9.]+)%, Prefix cache hit rate: ([0-9.]+)%.*/[\1\/\2 \3] KV cache usage: \8%, Cache hit: \9%, Running \6 reqs, Waiting: \7 reqs, Avg PP: \4, Avg TG: \5/'
)


# Commands -----------------------------------------------------------------------------------------

do_heal() {
    log "-- healing --"
    ensure_launcher
    ensure_model force
    ensure_image
}

do_down() {
    log "-- stopping --"
    "${LAUNCHER}" stop --name "${CONTAINER_NAME}"
}

do_status() {
    log "-- nodes status --"
    "${LAUNCHER}" status --name "${CONTAINER_NAME}" 2>&1 || true

    print_cache_size

    log "-- v1/models --"
    curl -s -m 5 "http://localhost:${PORT}/v1/models"
}

do_tail_head() {
    log "-- full head log follow --"

    exec docker logs -f "${CONTAINER_NAME}" 2>&1
}

do_tail_worker() {
    log "-- full worker log follow --"

    local -a nodes; IFS=',' read -r -a nodes <<< "${CLUSTER_NODES}"
    local wip="${nodes[1]:-}"
    [[ -n "${wip}" ]] || die "cannot determine worker from CLUSTER_NODES"
    exec ssh -o ConnectTimeout=10 "${wip}" "docker logs -f ${CONTAINER_NAME}" 2>&1
}

do_tail_perf() {
    log "-- performance grep log follow --"

    exec docker logs -f "${CONTAINER_NAME}" | grep --line-buffered 'Avg gen' | sed "${PERF_SED[@]}"
}

# Stream the head container log, printing every line, until a line containing
# `marker` is seen (then return 0). If the stream ends first, return 1.
# Opens the live `docker logs -f` on fd 3 so a follow-up continue_perf_tail can keep
# consuming the same stream without replaying it.
do_tail_head_till() {
    local marker="$1"

    log "-- waiting for server startup (head log until '${marker}', then perf tail), safe to Ctrl+C --"

    exec 3< <(docker logs -f "${CONTAINER_NAME}" 2>&1)
    while IFS= read -r line <&3; do
        printf '%s\n' "${line}"
        [[ "${line}" == *"${marker}"* ]] && return 0
    done
    return 1
}

# Continue consuming fd 3 (opened by do_tail_head_till), printing only the
# compact perf summary lines (the same sed as do_tail_perf).
continue_perf_tail() {
    log "-- performance grep log follow, safe to Ctrl+C--"

    while IFS= read -r line <&3; do
        [[ "${line}" == *"Avg gen"* ]] && printf '%s\n' "${line}" | sed "${PERF_SED[@]}"
    done
}

do_build_image() {
    docker build -f "${DIR}/Dockerfile" -t "${LOCAL_IMAGE}" "${DIR}"

    log "-- NOTE: Image built, don't forget to set USE_LOCAL_IMAGE to 1 --"
}


# Orchestration ------------------------------------------------------------------------------------

ensure_launcher() {
    [[ -x "${LAUNCHER}" ]] && return 0

    log "-- installing spark-vllm-docker dependency --"

    command -v git >/dev/null 2>&1 || die "git required to fetch launcher"
    log "fetching ${SVD_REPO} @ ${SVD_REF}"
    git clone "${SVD_REPO}" "${SVD_DIR}" 2>/dev/null || true
    git -C "${SVD_DIR}" fetch --all --quiet 2>/dev/null || true
    git -C "${SVD_DIR}" checkout -f "${SVD_REF}" 2>/dev/null || die "launcher checkout ${SVD_REF} failed"
    [[ -x "${LAUNCHER}" ]] || die "launcher missing after fetch"
}

is_model_cached() {
    local rev; rev="$(resolve_model_revision)"
    [[ "${rev}" =~ ^[0-9a-f]{40}$ ]] || return 1
    [[ -d "${MODEL_REPO}/snapshots/${rev}" ]]
}

resolve_model_revision() {
    [[ "${MODEL_REVISION}" != "main" ]] && { printf '%s\n' "${MODEL_REVISION}"; return; }
    [[ -f "${MODEL_REPO}/refs/main" ]] && { cat "${MODEL_REPO}/refs/main"; return; }
    printf 'main\n'
}

ensure_hf() {
    command -v hf >/dev/null 2>&1 && return 0
    log "the 'hf' CLI is required but not found"
    cat >&2 <<'EOF'

Install it with:

    pip install -U "huggingface_hub[cli]"
    # or
    curl -LsSf https://astral.sh/uv/install.sh | sh
    uv tool install huggingface_hub

Then make sure 'hf' is on your PATH (e.g. .venv/bin on your PATH).
EOF
    die "hf CLI not found"
}

ensure_model() {
    ensure_hf
    log "downloading ${MODEL} @ ${MODEL_REVISION}"
    hf download "${MODEL}" --revision "${MODEL_REVISION}" || die "model download failed"

    [[ -z "${1:-}" ]] && is_model_cached || distribute_model
}

distribute_model() {
    local wip
    for wip in $(worker_hosts); do
        log "rsync model -> ${wip}"
        rsync -a "${MODEL_REPO}/" "${wip}:${MODEL_REPO}/"
    done
}

ensure_image() {
    if [[ "${USE_LOCAL_IMAGE}" != "1" ]]; then
        log "pulling ${IMAGE}"
        docker pull "${IMAGE}" || die "image pull failed"
    fi
    local workers; workers="$(worker_hosts)"
    [[ -n "${workers}" ]] || return 0
    log "distributing ${IMAGE} -> workers"
    "${SVD_DIR}/build-and-copy.sh" --no-build -c "${workers}" -t "${IMAGE}"
}


# Helpers ------------------------------------------------------------------------------------------

add_mod_arg_if_1() {
    local enable="$1" dir="$2"
    if [[ "$enable" == "1" && -d "${DIR}/fixes/${dir}" ]]; then
        mod_args+=(--apply-mod "${DIR}/fixes/${dir}")
    fi
    return 0
}

launch_cluster() {
    log "starting containers on ${CLUSTER_NODES} (container name: ${CONTAINER_NAME})"

    local content="${1:?launch_cluster: command content required}"
    shift
    local -a mod_args_launcher_args=("$@")

    export HF_HOME="${HF_CACHE_DIR}"
    mkdir -p "$(dirname "${LAUNCH_SCRIPT}")"
    printf '%s\n' "${content}" > "${LAUNCH_SCRIPT}"
    "${LAUNCHER}" -t "${IMAGE}" -n "${CLUSTER_NODES}" \
        --name "${CONTAINER_NAME}" \
        --launch-script "${LAUNCH_SCRIPT}" -d "${mod_args_launcher_args[@]}"
}

worker_hosts() {
    local -a nodes; IFS=',' read -r -a nodes <<< "${CLUSTER_NODES}"
    local wip out=()
    for wip in "${nodes[@]:1}"; do
        wip="$(echo "${wip}" | xargs)"
        [[ -n "${wip}" ]] && out+=("${wip}")
    done
    printf '%s\n' "${out[*]}"
}

print_cache_size() {
    log "-- cache size --"
    docker logs "${CONTAINER_NAME}" 2>&1 | grep -i "GPU KV cache size" | tail -5 || true
}

log() { printf '\n === %s\n\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
