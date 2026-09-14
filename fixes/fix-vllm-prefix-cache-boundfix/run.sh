#!/bin/bash
# NOTE: NOT READY / DO NOT APPLY.
#
# Sparse-retention replay-boundary tail fix (boundfix Defect B) — under
# investigation. Two candidate ports were attempted and REVERTED because they
# did not address this model's geometry:
#
#   1. Manager-level final tail-commit pass in
#      `single_type_kv_cache_manager.cache_blocks`. Caused an AssertionError at
#      `block_pool.cache_full_blocks` (a "new full block already has a hash"
#      partial->full promotion assert) via a double-commit of the replay-boundary
#      block. Reverted.
#
#   2. Coordinator-level unrounded-token pass in
#      `hybrid_kv_cache_coordinator.cache_blocks`, passing the unrounded
#      `num_computed_tokens` to sliding-window / Mamba managers. Static analysis
#      showed it is a NO-OP for this alignment (`scheduler_block_size=256`,
#      SWA compressor blocks of 4/8, prompts that are not 256-aligned): the SWA
#      mask's replay-tail already falls within `[num_cached, num_full)` so no
#      block is dropped. Reverted.
#
# The true root cause of the ~9.97% retention (2/25 contexts) under sparse
# retention (the fork's default `prefix_cache_retention_interval=0`) is still
# to be determined. It is likely in the SWA mask's shared-prefix / replay-
# boundary retention or the fixed-point hit, not in commit-range truncation.
#
# Keep `FIX_PREFIX_CACHE_BOUNDFIX=0` (disabled) until a verified fix exists.
# NO-OP placeholder.
echo "[fix-vllm-prefix-cache-boundfix] NOT READY (under investigation) - no-op"
