#!/bin/bash
# Fix: allow arbitrary DSpark k (num_speculative_tokens) that is not divisible
# by the draft model's n_predict (MTP layer count).
#
# Root cause:
#   SpeculativeConfig._verify_and_get_draft_parallel_config (in
#   vllm/config/speculative.py) raises:
#       num_speculative_tokens must be divisible by n_predict
#   This check exists for MTP-style proposers where draft tokens are produced
#   in n_predict-sized chunks. DSpark does NOT use MTP chunking: it drafts a
#   single block of k tokens in one parallel pass (see
#   vllm/v1/worker/gpu/spec_decode/dspark/speculator.py). So for DSpark the
#   divisibility requirement is bogus and, e.g., k=5 fails against n_predict=3.
#
# Fix: skip the divisibility check when method == "dspark".
#
# Python-only, no recompile. Idempotent: safe to apply to an already-patched
# tree (patch reversed with -R, errors tolerated).
set -euo pipefail

VLLM_DIR="$(python3 -c 'import vllm, os; print(os.path.dirname(vllm.__file__))')"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/dspark-mtp-divisibility.patch"

# paths inside the patch are relative to vllm/; patch from parent of vllm/
cd "$(dirname "$VLLM_DIR")"

if patch -p1 --dry-run -N -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-dspark-mtp-divisibility] applying patch to $VLLM_DIR"
    patch -p1 -N -s < "$PATCH_FILE"
elif patch -p1 --dry-run -R -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-dspark-mtp-divisibility] already applied - skipping"
else
    echo "[fix-dspark-mtp-divisibility] ERROR: cannot apply and not already applied" >&2
    exit 1
fi

echo "[fix-dspark-mtp-divisibility] done"
