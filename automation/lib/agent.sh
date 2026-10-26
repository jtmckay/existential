#!/usr/bin/env bash
# agent.sh — Claude Code for a step of a machine: `agent "<prompt>"` prints its answer.
#
# Sourced, never run. Built on lib/ai.sh, decree's own helper (it is the file
# `decree init` writes; `test decree` fails when the two differ): every call
# waits out a usage limit and adds a line to .decree/ai-use.md. model.sh is the
# other way to reach a model, one answer from the stack's own /v1 endpoint; this
# is the one with tools.
#
#   source "${DECREE_LIB}/agent.sh"
#
#   agent_ready        0 when claude is installed and signed in here
#   agent <prompt>     its answer on stdout; fails, saying how to sign in, when not
#
# Signing in is once per install: `docker exec -it automation claude`, then
# /login, and the login lives in the container's home (the decree_data volume).
# Or set AUTOMATION_ANTHROPIC_API_KEY or AUTOMATION_CLAUDE_CODE_OAUTH_TOKEN in
# services/automation/.env, which compose passes in under the names Claude reads.
#
# It runs in the workspace, in decree's own `auto` permission mode
# (AUTOMATION_CLAUDE_PERMISSION_MODE changes it): Claude acts without asking. Your
# notes it cannot change: the automation container mounts them read-only.
# shellcheck source=ai.sh
source "${DECREE_LIB}/ai.sh"

agent_ready() {
    command -v claude >/dev/null 2>&1 || return 1
    [[ -n "${ANTHROPIC_API_KEY:-}${CLAUDE_CODE_OAUTH_TOKEN:-}" || -s "${HOME}/.claude/.credentials.json" ]]
}

agent() {
    if ! agent_ready; then
        echo "agent: Claude is not signed in here. Once: docker exec -it automation claude, then /login" >&2
        return 1
    fi
    ( cd "${AUTOMATIONS_WORKSPACE:-/workspace}" && AI_CLI=claude ai "$1" )
}
