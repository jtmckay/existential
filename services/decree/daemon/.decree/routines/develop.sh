#!/usr/bin/env bash
# Develop
#
# Default routine that delegates work to an AI assistant.
# Reads the task message, prompts the AI to implement all
# requirements, then verifies acceptance criteria are met.
set -euo pipefail

# --- Standard Environment Variables ---
# message_file  - Path to message.md in the run directory
# message_id    - Full message ID (e.g., D0001-1432-01-add-auth-0)
# message_dir   - Run directory path (contains logs from prior attempts)
# chain         - Chain ID (D<NNNN>-HHmm-<name>)
# seq           - Sequence number in chain
message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

# Pre-check: verify AI tool is available
if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v opencode >/dev/null 2>&1 || precheck_fail "develop" "opencode not found"
    precheck_pass "develop"
    exit 0
fi

# Implementation
opencode run "Read ${message_file} and implement all requirements.
Previous attempt logs (if any) are in ${message_dir} for context.
Follow best practices: clean code, proper error handling, and tests
where appropriate."

# Verification
opencode run "Read ${message_file}. Verify that all requirements and
acceptance criteria are met. Run any tests. Report what passes and what
fails. Exit 0 if everything passes, exit 1 if anything fails."
