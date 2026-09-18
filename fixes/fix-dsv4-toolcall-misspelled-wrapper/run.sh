#!/bin/bash
# Fix: tolerate misspelled DeepSeek-V4 DSML tool_calls wrappers
# (upstream commit 9e2570656013, PR #56141).
#
# Root cause:
#   In production the model sometimes corrupts the opener spelling, emitting
#   <toolcalls> or <tool> instead of <tool_calls>. The V4 parser only matched
#   the canonical DSML_TOOL_START literal, so a misspelled opener was not
#   recognised and the wrapped tool block leaked as content / lost its tool calls.
#
# Fix:
#   1. deepseek_v4.py: declare DSML_TOOL_START_VARIANTS and make TOOL_START a
#      tuple of spellings (canonical first).
#   2. ParserEngineConfig.terminals now accepts a tuple of spellings per
#      terminal; add terminal_literal() (canonical spelling) and
#      terminal_literals (all spellings) helpers.
#   3. incremental_lexer.terminals_from_literals expands tuple spellings.
#   4. parser_engine.py / streaming_parser_engine.py use the new helpers
#      instead of reading terminals directly.
#
# Also fix-dsv4-toolcall-orphan-invoke (d98c8c0) is independent and can be
# applied before/after this one; both live in the same upstream ref family.
# Python-only, no recompile. Idempotent.
set -euo pipefail

VLLM_DIR="$(python3 -c 'import vllm, os; print(os.path.dirname(vllm.__file__))')"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/toolcall-misspelled-wrapper.patch"

# paths inside the patch are relative to vllm/; patch from parent of vllm/
cd "$(dirname "$VLLM_DIR")"

if patch -p1 --dry-run -N -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-dsv4-toolcall-misspelled-wrapper] applying patch to $VLLM_DIR"
    patch -p1 -N -s < "$PATCH_FILE"
elif patch -p1 --dry-run -R -s < "$PATCH_FILE" 2>/dev/null; then
    echo "[fix-dsv4-toolcall-misspelled-wrapper] already applied - skipping"
else
    echo "[fix-dsv4-toolcall-misspelled-wrapper] ERROR: cannot apply and not already applied" >&2
    exit 1
fi

echo "[fix-dsv4-toolcall-misspelled-wrapper] done"
