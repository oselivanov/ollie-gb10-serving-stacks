#!/bin/bash
# Fix: make `--linear-backend cutlass` work on CUDA / GB10 (DeepSeek-V4 block FP8).
#
# Root cause:
#   DeepSeek-V4 (Flash / Vision-Exp) stores its block-FP8 weight scales as E8M0
#   (exponent-only; config: quantization_config.scale_fmt="ue8m0",
#   weight_block_size=[128,128], expert_dtype="fp4", is_scale_e8m0=True).
#
#   `--linear-backend cutlass` selects CutlassFp8BlockScaledMMKernel. That kernel
#   inherits Fp8BlockScaledMMLinearKernel.process_weights_after_loading (the base
#   impl), which leaves the weight scales in E8M0. The CUTLASS block-scaled MM
#   load cannot bind float8_e8m0fnu (exponent-only) scale tensors, so invoking
#   ops.cutlass_scaled_mm with an E8M0 scale_b raises:
#       RuntimeError: dispatch_scaled_mm, .../w8a8/cutlass/c3x/scaled_mm_helper.hpp:17
#   On GB10 the b12x kernel works because B12xFp8BlockScaledMMKernel overrides
#   process_weights_after_loading and upcasts E8M0 -> fp32 at load time.
#
#   Verified by minimal repro on the live GPU (SM121):
#       As.dtype=torch.float32, Bs.dtype=torch.float8_e8m0fnu
#       ops.cutlass_scaled_mm(...)  ->  RuntimeError: dispatch_scaled_mm ...:17
#       after _upcast_e8m0_to_fp32(Bs).contiguous()  ->  launches OK
#
# Fix:
#   Override process_weights_after_loading in CutlassFp8BlockScaledMMKernel to
#   upcast E8M0/uint8 weight block scales to fp32 on load, exactly mirroring the
#   B12x kernel. This also covers the attention o_proj path
#   (deep_gemm_fp8_o_proj -> fp8_einsum, which requires fp32 scales).
#   Python-only, no recompile.
#
# Idempotent: safe to apply to an already-patched tree (patch reversed with -R,
# errors tolerated).
set -euo pipefail

VLLM_DIR="$(python3 -c 'import vllm, os; print(os.path.dirname(vllm.__file__))')"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/cutlass-e8m0.patch"

TARGET="${VLLM_DIR}/model_executor/kernels/linear/scaled_mm/cutlass.py"

# paths inside the patch are relative to vllm/; patch from parent of vllm/
cd "$(dirname "$VLLM_DIR")"

if patch -p1 --dry-run -N -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-vllm-linear-cutlass-e8m0] applying patch to $VLLM_DIR"
    patch -p1 -N -s < "$PATCH_FILE"
elif patch -p1 --dry-run -R -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-vllm-linear-cutlass-e8m0] already applied - skipping"
else
    echo "[fix-vllm-linear-cutlass-e8m0] ERROR: cannot apply and not already applied" >&2
    exit 1
fi

# Verify the result compiles.
python3 -m py_compile "$TARGET"

echo "[fix-vllm-linear-cutlass-e8m0] done"
