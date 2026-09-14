#!/bin/bash
# Fix: commit-time same-content dedupe in the prefix-cache block pool.
#
# Ported from https://github.com/co-l/ds4-prefix-cache-fixes patches/03-dedupe.py
# to this fork (0rand/vllm_spark_dsv4-0.29-b12x, vLLM 0.28.1rc1.dev475+).
#
# Root cause:
#   Every request re-computes ~20 already-cached positions (hit-path drop /
#   spec-decode boundary). Each re-commit inserts a SECOND block with the same
#   content hash into the map, and hits always return the first copy, so the
#   older copies are never touched again — pure dead weight that grows with
#   request count.
#
# Fix:
#   In block_pool.cache_full_blocks, before inserting a block's content hash,
#   check whether the map already holds that (hash, group) position for a
#   different block; if so, evict the old copy's hash mappings
#   (_maybe_evict_cached_block: consistent map/events/metrics/trace cleanup).
#   Both blocks hold byte-identical content (same hash chain), so no hit
#   capability is lost — the map simply keeps one block per position.
#
# Python-only, no recompile. Idempotent: safe to apply to an already-patched
# tree (patch reversed with -R, errors tolerated).
set -euo pipefail

VLLM_DIR="$(python3 -c 'import vllm, os; print(os.path.dirname(vllm.__file__))')"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/prefix-cache-dedupe.patch"

# paths inside the patch are relative to vllm/; patch from parent of vllm/
cd "$(dirname "$VLLM_DIR")"

if patch -p1 --dry-run -N -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-vllm-prefix-cache-dedupe] applying patch to $VLLM_DIR"
    patch -p1 -N -s < "$PATCH_FILE"
elif patch -p1 --dry-run -R -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-vllm-prefix-cache-dedupe] already applied - skipping"
else
    echo "[fix-vllm-prefix-cache-dedupe] ERROR: cannot apply and not already applied" >&2
    exit 1
fi

# Verify the result compiles.
python3 -m py_compile "$VLLM_DIR/v1/core/block_pool.py"

echo "[fix-vllm-prefix-cache-dedupe] done"
