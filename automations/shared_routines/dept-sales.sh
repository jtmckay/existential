#!/usr/bin/env bash
# Department: sales
#
# DEPT_DESCRIPTION: Outbound, discovery calls, deal strategy, pricing, and customer-facing writing.
# DEPT_TOOLSETS: skills, todo
# DEPT_MCP: openviking
#
# Anything aimed at winning or keeping a customer.
#
# Reached by hermes-router, which picks a department and writes an outbox
# message naming this routine. Can also be triggered directly by dropping a
# message with `routine: dept-sales` — the router is bypassed entirely then.
#
#   ---
#   routine: dept-sales
#   output_name: sales-answer
#   ---
#   <the task>
#
# The work runs against the hermes 'sales' profile (/p/sales/v1), which owns
# this department's toolsets and MCP servers. Change what it can reach by
# editing volumes/hermes_agent_data/profiles/sales/config.yaml — not here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "dept-sales" "curl not found"
    command -v jq >/dev/null 2>&1 || precheck_fail "dept-sales" "jq not found"
    [ -n "${HERMES_API_KEY:-}" ] || precheck_fail "dept-sales" \
        "HERMES_API_KEY is empty — enable hermes so the gateway credential is passed through"
    precheck_pass "dept-sales"
    exit 0
fi

# shellcheck disable=SC2034  # consumed by hermes-dept.sh (${DEPT_PROFILE:?})
# after the source below; shellcheck does not follow into it. The
# description is NOT repeated here — hermes-router and exist.profiles.sh
# both read the `# DEPT_DESCRIPTION:` header comment out of this file, so a
# second copy as a shell variable is read by nothing and only drifts.
DEPT_PROFILE="sales"

# shellcheck source=../lib/hermes-dept.sh
source "${SCRIPT_DIR}/../lib/hermes-dept.sh"
dept_run
