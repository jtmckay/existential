#!/usr/bin/env bash
# Department: research
#
# DEPT_DESCRIPTION: Investigation, fact-finding, competitive and market analysis, literature review.
# DEPT_TOOLSETS: search, web, skills, todo
# DEPT_MCP: openviking, firecrawl
#
# The only department with web access — send anything that needs looking up.
#
# Reached by hermes-router, which picks a department and writes an outbox
# message naming this routine. Can also be triggered directly by dropping a
# message with `routine: dept-research` — the router is bypassed entirely then.
#
#   ---
#   routine: dept-research
#   output_name: research-answer
#   ---
#   <the task>
#
# The work runs against the hermes 'research' profile (/p/research/v1), which owns
# this department's toolsets and MCP servers. Change what it can reach by
# editing volumes/hermes_agent_data/profiles/research/config.yaml — not here.
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
    command -v curl >/dev/null 2>&1 || precheck_fail "dept-research" "curl not found"
    command -v jq >/dev/null 2>&1 || precheck_fail "dept-research" "jq not found"
    [ -n "${HERMES_API_KEY:-}" ] || precheck_fail "dept-research" \
        "HERMES_API_KEY is empty — enable hermes so the gateway credential is passed through"
    precheck_pass "dept-research"
    exit 0
fi

DEPT_PROFILE="research"
DEPT_DESCRIPTION="Investigation, fact-finding, competitive and market analysis, literature review."

# shellcheck source=../lib/hermes-dept.sh
source "${SCRIPT_DIR}/../lib/hermes-dept.sh"
dept_run
