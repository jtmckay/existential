#!/usr/bin/env bash
# exist.test.sh — validate that code-server is fully operational.
#
# See .claude/reference/testing.md for the convention.
# Run via: ./existential.sh run code-server test  (or: ./existential.sh test)

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "code-server" EXIST_IS_SERVICES_CODE_SERVER
skip_if_disabled

# /healthz is unauthenticated and answers 200 as soon as the HTTP server is up
# (verified against v4.135.0: a plain curl with no cookie gets 200 from
# /healthz, vs. a 302-to-/login from / and a 401 from an authenticated route
# like /vscode-remote-resource) — the real "is the process alive" signal, and
# what the container's own healthcheck now uses too (docker-compose.exist.yml).
probe_service "code-server /healthz" code-server 8080 /healthz 200

# CODE_SERVER_PASSWORD is what entrypoint.sh's `--auth password` actually
# checks against ($PASSWORD env). A bare shell in this container can read/write
# the whole workspace, reach the models and run whatever is installed in it, so an empty password is a
# real exposure, not just a broken login. Verify root really is gated behind
# it (302 to /login, not a 200 straight into the IDE) rather than trusting the
# flag was honored.
env_var_set "code-server password" CODE_SERVER_PASSWORD
probe_service "code-server auth gate" code-server 8080 / 302

# model.sh and pi.sh (sourced to configure opencode and pi) and the capture hook
# and plugin are read from the workspace's decree lib, where the model, pi and
# capture plugins install them. A missing one only makes the entrypoint warn, so
# check them on disk.
for _src in model.sh pi.sh capture/capture.sh capture/opencode.ts; do
    if [ -f "/repo/volumes/workspace_data/.decree/lib/${_src}" ]; then
        ok "code-server lib/${_src} installed"
    else
        fail "code-server lib/${_src} installed" "workspace/.decree/lib/${_src} is missing" \
             "./existential.sh flow on code-server-agents"
    fi
done

# pi in the terminal answers from the chat role: pi_configure wrote that provider.
_pi_models=/repo/volumes/code_server_data/home/.pi/agent/models.json
if [ -n "$(jq -r '.providers.existential.baseUrl // empty' "$_pi_models" 2>/dev/null)" ]; then
    ok "code-server pi has the chat model"
else
    fail "code-server pi has the chat model" "${_pi_models} has no existential provider" \
         "docker logs code-server | grep pi; then docker compose up -d --force-recreate code-server"
fi

# Search (ai/qmd): with the add-on on, entrypoint.sh registers qmd with Claude
# Code, allows its tools and copies the recall skill. Read the files it wrote
# rather than reaching into the container.
if [ "${EXIST_IS_AI_QMD:-false}" = "true" ]; then
    _home=/repo/volumes/code_server_data/home/.claude
    _fix="Recreate code-server so its entrypoint wires search: docker compose up -d --force-recreate code-server; then docker logs code-server | grep qmd"
    if [ "$(jq -r '.mcpServers.qmd.url // empty' "${_home}/.claude.json" 2>/dev/null)" = "http://qmd:8181/mcp" ]; then
        ok "code-server Claude Code has the qmd MCP"
    else
        fail "code-server Claude Code has the qmd MCP" "${_home}/.claude.json has no qmd server at http://qmd:8181/mcp" "$_fix"
    fi
    if jq -e '.permissions.allow | index("mcp__qmd")' "${_home}/settings.json" >/dev/null 2>&1; then
        ok "code-server allows mcp__qmd"
    else
        fail "code-server allows mcp__qmd" "${_home}/settings.json does not allow mcp__qmd" "$_fix"
    fi
    if [ -f /repo/volumes/workspace_data/.claude/skills/recall/SKILL.md ]; then
        ok "code-server recall skill"
    else
        fail "code-server recall skill" "workspace/.claude/skills/recall/SKILL.md is missing" "$_fix"
    fi
fi

finish
