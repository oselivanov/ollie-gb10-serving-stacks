#!/bin/bash
# Fix: make `--linear-backend triton` work on CUDA / GB10 (DeepSeek-V4 block FP8).
#
# Root cause:
#   DeepSeek-V4 (Flash / Vision-Exp) stores its block-FP8 weight scales as E8M0
#   (exponent-only; config: quantization_config.scale_fmt="ue8m0",
#   weight_block_size=[128,128], expert_dtype="fp4", is_scale_e8m0=True).
#
#   With `--linear-backend b12x`, B12xFp8BlockScaledMMKernel.process_weights_after_loading
#   upcasts the E8M0 weight scales to fp32, so every consumer (the linear kernels
#   AND the attention o_proj path, which reads wo_a.weight_scale directly and
#   feeds it into DeepGEMM fp8_einsum) sees fp32 scales.
#
#   With `--linear-backend triton`, TritonFp8BlockScaledMMKernel does NOT
#   override process_weights_after_loading; it inherits the base
#   Fp8BlockScaledMMLinearKernel implementation, which leaves the scales in
#   E8M0. Two things then break:
#     1. The Triton W8A8 block-FP8 kernel cannot bind float8_e8m0fnu (there is
#        no torch->Triton dtype map entry), so launching it raises
#        KeyError('float8_e8m0fnu').
#     2. The attention o_proj path (deep_gemm_fp8_o_proj -> fp8_einsum) passes
#        the E8M0 wo_a.weight_scale straight into DeepGEMM, which asserts
#        `sf_dtype == torch::kFloat or torch::kInt` and rejects E8M0:
#            RuntimeError: Assertion error (layout.hpp:93): sf_dtype ==
#            torch::kFloat or torch::kInt
#        This is what triton.log shows (in profile_run/_dummy_run, before any
#        request) -> "Engine core initialization failed".
#
# Fix:
#   Override process_weights_after_loading in TritonFp8BlockScaledMMKernel to
#   upcast E8M0/uint8 weight scales to fp32 on load, exactly mirroring the B12x
#   kernel. This fixes both the DeepGEMM o_proj assertion and the Triton
#   KeyError. Python-only, no recompile.
#
# Idempotent: safe to apply to an already-patched tree (patch reversed with -R,
# errors tolerated).
set -euo pipefail

VLLM_DIR="$(python3 -c 'import vllm, os; print(os.path.dirname(vllm.__file__))')"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/linear-triton-e8m0.patch"

TARGET="${VLLM_DIR}/model_executor/kernels/linear/scaled_mm/triton.py"

# paths inside the patch are relative to vllm/; patch from parent of vllm/
cd "$(dirname "$VLLM_DIR")"

if patch -p1 --dry-run -N -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-vllm-linear-triton-e8m0] applying patch to $VLLM_DIR"
    patch -p1 -N -s < "$PATCH_FILE"
elif patch -p1 --dry-run -R -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-vllm-linear-triton-e8m0] already applied - skipping"
else
    echo "[fix-vllm-linear-triton-e8m0] ERROR: cannot apply and not already applied" >&2
    exit 1
fi

# Verify the result compiles.
python3 -m py_compile "$TARGET"

echo "[fix-vllm-linear-triton-e8m0] done"
