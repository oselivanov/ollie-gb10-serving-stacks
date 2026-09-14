#!/bin/bash
# INVESTIGATION-ONLY instrumentation. NOT a shipped fix — do not enable in
# production. This adds [kvfix] log lines to the prefix-cache coordinator and
# the SWA cache manager to pin down where sparse-retention replay-boundary
# blocks are lost at runtime:
#
#   - group geometry + scheduler/hash block size       (HybridKVCacheCoordinator init)
#   - per-group num_tokens_to_cache / commit range      (HybridKVCacheCoordinator.cache_blocks)
#   - base manager commit range (num_cached/full, mask) (SingleTypeKVCacheManager.cache_blocks)
#   - SWA mask keep-set                                  (SlidingWindowManager.reachable_block_mask)
#   - SWA hit result                                     (SlidingWindowManager.find_longest_cache_hit)
#
# Gate it behind FIX_KVFIX_INSTRUMENT=1 in vision-exp-stack.
set -euo pipefail

VLLM_DIR="$(python3 -c 'import vllm, os; print(os.path.dirname(vllm.__file__))')"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/kvfix-instrument.patch"

# paths inside the patch are relative to vllm/; patch from parent of vllm/
cd "$(dirname "$VLLM_DIR")"

if patch -p1 --dry-run -N -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-kvfix-instrument] applying instrumentation to $VLLM_DIR"
    patch -p1 -N -s < "$PATCH_FILE"
elif patch -p1 --dry-run -R -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-kvfix-instrument] already applied - skipping"
else
    echo "[fix-kvfix-instrument] ERROR: cannot apply and not already applied" >&2
    exit 1
fi

python3 -m py_compile "$VLLM_DIR/v1/core/kv_cache_coordinator.py"
python3 -m py_compile "$VLLM_DIR/v1/core/single_type_kv_cache_manager.py"

echo "[fix-kvfix-instrument] done"
