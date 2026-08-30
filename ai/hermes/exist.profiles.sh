#!/usr/bin/env bash
# hermes — provision the router and department profiles.
#
# Run after 'docker compose up -d':
#   ./existential.sh run hermes profiles
#
# A hermes profile is its own HERMES_HOME: its own config.yaml, .env, SOUL.md
# and skills/. With GATEWAY_MULTIPLEX_PROFILES set (see docker-compose.exist.yml)
# each one is served off the same listener at /p/<name>/v1, so a caller picks a
# profile — and therefore a toolset and an MCP server list — by URL alone.
#
# Why that matters: tool schemas are the expensive axis of a hermes prompt
# (~2.4 KB each against ~76 B for a skill's index entry). The default profile
# carries every tool, ~40,000 prompt tokens per call. The router profile carries
# none and costs ~630. Splitting departments out is what makes routing cheap
# enough to run on every message.
#
# Nothing here is invented configuration: the departments are discovered from
# automations/shared_routines/dept-*.sh, which is the same list hermes-router
# routes to. Each declares what it needs in its header:
#
#   # DEPT_DESCRIPTION: <when work should come here>
#   # DEPT_TOOLSETS: search, web, skills, todo
#   # DEPT_MCP: openviking, firecrawl
#
# So adding a department stays adding a file — the routine, the router's catalog
# entry and the profile all come from that one header.
#
# Idempotent, and never destructive: an existing profile keeps its config.yaml.
# Delete volumes/hermes_agent_data/profiles/<name> and re-run to rebuild one.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROUTINES="${REPO}/automations/shared_routines"
PROFILES_DIR="/opt/data/profiles"

if ! docker inspect hermes-agent --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "hermes-agent is not running. Start it first:"
    echo ""
    echo "  docker compose up -d"
    echo ""
    exit 1
fi

PUID="${EXIST_PUID:-1000}"
PGID="${EXIST_PGID:-1000}"

# The gateway credential. Secondary profiles do NOT borrow the default profile's
# key — the API server reads API_SERVER_KEY from the profile being addressed, so
# a profile without one 401s on every request.
API_KEY=$(grep -m1 '^HERMES_API_KEY=' "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d= -f2- || true)
if [[ -z "$API_KEY" ]]; then
    echo "[hermes] HERMES_API_KEY not found in ai/hermes/.env — run ./existential.sh first." >&2
    exit 1
fi

# openviking authenticates its MCP endpoint; firecrawl-mcp holds its own key and
# is reached unauthenticated over the exist network. Same split as the default
# profile's wiring in exist.initial.sh.
OV_KEY=$(grep -m1 '^OPENVIKING_API_KEY=' "${REPO}/ai/openviking/.env" 2>/dev/null | cut -d= -f2- || true)

# Rebuild a model: block from the default profile's config.yaml. Departments
# inherit the model rather than naming one, so the stack's single model choice
# stays a single choice — change it with `hermes model` and re-run this.
#
# The four keys are pulled out rather than the block copied verbatim: hermes'
# shipped config.yaml carries ~200 lines of commented provider documentation
# inside model:, and reproducing that in every generated profile would bury the
# three lines that actually differ.
_model_block() {
    local raw key val out=""
    raw="$(docker exec hermes-agent sh -c \
        'awk "/^model:/ { f = 1; next } f && /^[^[:space:]#]/ { exit } f { print }" /opt/data/config.yaml')"
    for key in default provider base_url context_length; do
        val="$(printf '%s\n' "$raw" | grep -m1 -E "^[[:space:]]+${key}:" \
            | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//; s/[[:space:]]*(#.*)?\$//; s/^\"//; s/\"\$//")"
        [[ -z "$val" ]] && continue
        case "$key" in
            context_length) out+="  ${key}: ${val}"$'\n' ;;
            *)              out+="  ${key}: \"${val}\""$'\n' ;;
        esac
    done
    [[ -n "$out" ]] && printf 'model:\n%s' "$out"
}

MODEL_BLOCK="$(_model_block)"
if [[ -z "$MODEL_BLOCK" ]]; then
    echo "[hermes] No model: block in /opt/data/config.yaml — run ./existential.sh run hermes setup first." >&2
    exit 1
fi

# Header field of a dept-*.sh, e.g. _dept_field dept-sales.sh DEPT_MCP
_dept_field() {
    grep -m1 "^# ${2}:" "$1" 2>/dev/null | sed "s/^# ${2}:[[:space:]]*//"
}

# One MCP server entry, by name. Unknown names are skipped with a warning rather
# than written out — an MCP entry pointing at nothing makes hermes retry a dead
# endpoint on every task.
_mcp_entry() {
    case "$1" in
        openviking)
            if [[ -z "$OV_KEY" ]]; then
                echo "[hermes] openviking requested but OPENVIKING_API_KEY not found — skipping." >&2
                return 0
            fi
            printf '  openviking:\n    url: "http://openviking:1933/mcp"\n    headers:\n      Authorization: "Bearer %s"\n' "$OV_KEY"
            ;;
        firecrawl)
            printf '  firecrawl:\n    url: "http://firecrawl-mcp:3003/mcp"\n'
            ;;
        *)
            echo "[hermes] Unknown MCP server '${1}' — skipping." >&2
            ;;
    esac
}

# _provision <name> <description> <toolsets csv> <mcp csv>
_provision() {
    local name="$1" desc="$2" toolsets="$3" mcp="$4"
    local dir="${PROFILES_DIR}/${name}"

    if docker exec hermes-agent test -d "$dir"; then
        echo "  ✓ ${name}: already exists — leaving it alone."
    else
        echo "  + ${name}: creating..."
        # --no-skills: a department's skills are the agents you install into it.
        # Inheriting the default profile's bundled set would put every tool
        # description back in the prompt, which is the cost this splits out.
        docker exec hermes-agent /opt/hermes/.venv/bin/hermes profile create "$name" \
            --no-skills --no-alias --description "$desc" >/dev/null
    fi

    # config.yaml is written only when absent, so an edited profile is kept.
    if docker exec hermes-agent test -f "${dir}/config.yaml"; then
        echo "    config.yaml present — not overwriting."
    else
        local toolset_yaml="[]"
        [[ -n "$toolsets" ]] && toolset_yaml="[${toolsets}]"

        local mcp_yaml=""
        if [[ -n "$mcp" ]]; then
            local one
            for one in ${mcp//,/ }; do
                mcp_yaml+="$(_mcp_entry "$one")"
            done
        fi

        {
            printf '# %s profile — generated by ./existential.sh run hermes profiles.\n' "$name"
            printf '#\n# %s\n#\n' "$desc"
            printf '# Empty of agents on purpose: install the ones you want into\n'
            printf '# profiles/%s/skills/. Skills cost ~76 B each in the always-on index;\n' "$name"
            printf '# tool schemas cost ~2.4 KB, which is why the toolset list is short.\n'
            printf '%s\n' "$MODEL_BLOCK"
            printf '\nplatform_toolsets:\n  api_server: %s\n' "$toolset_yaml"
            [[ -n "$mcp_yaml" ]] && printf '\nmcp_servers:\n%s' "$mcp_yaml"
        } | docker exec -i hermes-agent sh -c "cat > '${dir}/config.yaml'"
        echo "    config.yaml written (toolsets: ${toolsets:-none}, mcp: ${mcp:-none})."
    fi

    # The credential, appended only when absent.
    if docker exec hermes-agent sh -c "grep -q '^API_SERVER_KEY=' '${dir}/.env' 2>/dev/null"; then
        echo "    API_SERVER_KEY present."
    else
        docker exec hermes-agent sh -c "printf 'API_SERVER_KEY=%s\n' '${API_KEY}' >> '${dir}/.env'"
        echo "    API_SERVER_KEY written."
    fi
}

echo "Provisioning hermes profiles..."

# The router is not a department: it names one and stops. No toolsets, no MCP —
# choosing between two words needs neither, and every tool it carried would be
# paid for on every routed message.
_provision router \
    "Routing only: reads a task and names the department that should handle it." \
    "" ""

_found=0
for _f in "${ROUTINES}"/dept-*.sh; do
    [[ -f "$_f" ]] || continue
    _found=1
    _name="$(basename "$_f" .sh)"; _name="${_name#dept-}"
    _provision "$_name" \
        "$(_dept_field "$_f" DEPT_DESCRIPTION)" \
        "$(_dept_field "$_f" DEPT_TOOLSETS)" \
        "$(_dept_field "$_f" DEPT_MCP)"
done

if [[ "$_found" -eq 0 ]]; then
    echo "  (no dept-*.sh routines found in automations/shared_routines/)"
fi

# hermes runs as PUID; docker exec runs as root, so anything it created is
# root-owned and the gateway cannot write its logs there. Do this last: the
# profile's own log files are recreated during creation.
docker exec hermes-agent chown -R "${PUID}:${PGID}" "$PROFILES_DIR"

echo ""
echo "Done. Profiles are served at http://hermes-agent:8642/p/<name>/v1"
echo "Check what each one costs:  docker exec -e HERMES_HOME=${PROFILES_DIR}/<name> hermes-agent /opt/hermes/.venv/bin/hermes prompt-size"
