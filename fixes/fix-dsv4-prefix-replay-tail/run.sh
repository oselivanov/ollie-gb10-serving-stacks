#!/bin/bash
# Fix the DSV4 prefix-cache "dead zone" under sparse retention + EAGLE-style drafting.
#
# Symptom (measured on vLLM 0.28.1rc1 with DSpark speculative decoding): a request
# whose prompt ends 1..64 tokens past a 256-token boundary leaves nothing
# reusable. Its exact replay and its follow-up turn get 0 cached tokens (full
# cold prefill), about 1 in 4 prompt lengths. The follow-up falls back to the
# last turn that did cache, and consecutive dead-zone turns compound.
#
# Root cause: prefix_cache_retention_interval defaults to 0 (keep only the
# replay-boundary tail). With DSpark the 64-token SWA group is an EAGLE group,
# whose hit run needs a FULL 64-token peek block starting on the aligned
# boundary. For prompts ending 1..64 tokens past it that block is never full,
# so the only tail retained is unreachable; the hybrid hit (min over groups)
# collapses to 0. Same defect class as co-l/ds4-prefix-cache-fixes 04-boundfix
# (written for vLLM 0.26), reimplemented for the 0.28.1 cache manager.
#
# Fix: every sliding/Mamba manager additionally retains the tail at the last
# reachable boundary (num_prompt - 1 - slack, slack = EAGLE SWA block size).
# Only adds retained blocks, never removes any. No-op without EAGLE groups.
# Python-only, no recompile.
#
# Verified offline with the image's own cache manager against all 256 prompt
# end offsets at 8K/65K/262K, MNBT 4096 and 2048: zero-hit cases 192/768 -> 0.
#
# Idempotent: safe to apply to an already-patched tree.
set -euo pipefail

VLLM_DIR="$(python3 -c 'import vllm, os; print(os.path.dirname(vllm.__file__))' 2>/dev/null | tail -1)"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/dsv4-prefix-replay-tail.patch"

# paths inside the patch are relative to vllm/'s parent
cd "$(dirname "$VLLM_DIR")"

if patch -p1 --dry-run -N -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-dsv4-prefix-replay-tail] applying patch to $VLLM_DIR"
    patch -p1 -N -s < "$PATCH_FILE"
elif patch -p1 --dry-run -R -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-dsv4-prefix-replay-tail] already applied - skipping"
else
    echo "[fix-dsv4-prefix-replay-tail] ERROR: cannot apply and not already applied" >&2
    exit 1
fi

python3 -m py_compile "$VLLM_DIR/v1/core/single_type_kv_cache_manager.py" "$VLLM_DIR/v1/core/kv_cache_coordinator.py"
echo "[fix-dsv4-prefix-replay-tail] done"
