#!/bin/bash
# Fix: parse DeepSeek-V4 DSML tool calls even when the model omits the
# <tool_calls> wrapper (upstream commit d98c8c030b64, PR #55954, issue #48931).
#
# Root cause:
#   At long context the model sometimes drops the <tool_calls> ... </tool_calls>
#   wrapper and opens <invoke name="..."> directly from CONTENT. The V4 parser
#   only recognised an invoke after a TOOL_PREAMBLE (i.e. after TOOL_START), so
#   a bare invoke was emitted as content, leaking DSML into the output.
#
# Fix (state-machine changes in deepseek_v4_config):
#   1. Add a CONTENT -> INVOKE_PREFIX transition to TOOL_NAME, so an invoke
#      with no wrapper anchors tool-call detection itself.
#   2. TOOL_ARGS -> TOOL_END now goes to TOOL_BETWEEN (not CONTENT), and a
#      further TOOL_END while in TOOL_BETWEEN stays there, so any text after a
#      tool block is dropped (matches official DSV4 behaviour).
#   3. A TOOL_START while in TOOL_BETWEEN moves to TOOL_PREAMBLE, so a wrapped
#      call can follow an orphan invoke.
#
# Python-only, no recompile. Idempotent (reverses with -R, errors tolerated).
set -euo pipefail

VLLM_DIR="$(python3 -c 'import vllm, os; print(os.path.dirname(vllm.__file__))')"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/deepseek_v4.patch"

# paths inside the patch are relative to vllm/; patch from parent of vllm/
cd "$(dirname "$VLLM_DIR")"

if patch -p1 --dry-run -N -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-dsv4-toolcall-orphan-invoke] applying patch to $VLLM_DIR"
    patch -p1 -N -s < "$PATCH_FILE"
elif patch -p1 --dry-run -R -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-dsv4-toolcall-orphan-invoke] already applied - skipping"
else
    echo "[fix-dsv4-toolcall-orphan-invoke] ERROR: cannot apply and not already applied" >&2
    exit 1
fi

echo "[fix-dsv4-toolcall-orphan-invoke] done"
