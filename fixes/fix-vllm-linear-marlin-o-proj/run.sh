#!/bin/bash
# Fix: make `--linear-backend marlin` work on CUDA / GB10 (DeepSeek-V4 block FP8).
#
# Root cause:
#   DeepSeek-V4 (Flash / Vision-Exp) stores its block-FP8 weight scales as E8M0
#   (exponent-only; config: quantization_config.scale_fmt="ue8m0",
#   weight_block_size=[128,128], expert_dtype="fp4", is_scale_e8m0=True).
#
#   With `--linear-backend marlin`, MarlinFP8ScaledMMLinearKernel is selected
#   for the FP8 block-scaled linear layers. Its process_weights_after_loading
#   unconditionally repacks EVERY block-quant layer weight into Marlin int32
#   layout (prepare_fp8_layer_for_marlin).
#
#   DeepSeek-V4's attention output projection (wo_a) is marked is_bmm=True and
#   is consumed DIRECTLY by deep_gemm_fp8_o_proj -> fp8_einsum, which reads
#   wo_a.weight / wo_a.weight_scale_inv and requires the raw FP8 block layout.
#   With Marlin, the weight is repacked to int32 and the scale permuted, so the
#   einsum chokes on the shape/dtype:
#       RuntimeError: Assertion error (einsum.hpp:164): m == m_ and n == n_ and k == k_
#   This happens during model init (weight loading), before any request ->
#   "Engine core initialization failed".
#
#   (The b12x kernel works because B12xFp8BlockScaledMMKernel keeps the raw
#   FP8 weight and only upcasts the E8M0 scale to fp32 at load time.)
#
# Fix:
#   In MarlinFP8ScaledMMLinearKernel.process_weights_after_loading, when
#   layer.is_bmm is set (the wo_a o_proj), keep the raw FP8 weight and upcast
#   the E8M0/uint8 weight block scales to fp32 -- exactly mirroring the B12x
#   kernel -- so fp8_einsum gets fp32 scales and the flat checkpoint layout.
#   All other (non-is_bmm) layers are still repacked to Marlin as before.
#   Python-only, no recompile.
#
# Idempotent: safe to apply to an already-patched tree (patch reversed with -R,
# errors tolerated).
set -euo pipefail

VLLM_DIR="$(python3 -c 'import vllm, os; print(os.path.dirname(vllm.__file__))')"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/marlin-o-proj.patch"

TARGET="${VLLM_DIR}/model_executor/kernels/linear/scaled_mm/marlin.py"

# paths inside the patch are relative to vllm/; patch from parent of vllm/
cd "$(dirname "$VLLM_DIR")"

if patch -p1 --dry-run -N -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-vllm-linear-marlin-o-proj] applying patch to $VLLM_DIR"
    patch -p1 -N -s < "$PATCH_FILE"
elif patch -p1 --dry-run -R -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-vllm-linear-marlin-o-proj] already applied - skipping"
else
    echo "[fix-vllm-linear-marlin-o-proj] ERROR: cannot apply and not already applied" >&2
    exit 1
fi

# Verify the result compiles.
python3 -m py_compile "$TARGET"

echo "[fix-vllm-linear-marlin-o-proj] done"
