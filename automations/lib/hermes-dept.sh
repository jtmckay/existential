#!/usr/bin/env bash
# hermes-dept.sh — shared dispatch for department routines.
#
# Sourced, never run. A dept-<name>.sh routine declares what it is and calls
# dept_run; everything else lives here so a new department is a 20-line file.
#
#   # DEPT_DESCRIPTION: Outbound, discovery, deal strategy.
#   DEPT_PROFILE="sales"
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/hermes-dept.sh"
#   dept_run
#
# DEPT_DESCRIPTION is a header COMMENT, not a variable, and it is not decoration:
# hermes-router and ai/hermes/exist.profiles.sh both grep `^# DEPT_DESCRIPTION:`
# out of the file to build the list the router chooses from. Write it as the
# answer to "when should work come here?"
#
# Each department maps to a hermes profile reached at /p/<profile>/v1, which
# carries its own toolsets and MCP servers. The routine name is what shows up in
# decree's run log and the Grafana dashboard, which is why departments are
# separate routines rather than one dispatcher with a parameter.
#
# The profile is called directly over its OpenAI-compatible endpoint. Hermes is
# itself an agent running its own tool loop against its own MCP servers, so
# routing this through opencode would wrap an agent in an agent — and opencode's
# streaming parser rejects hermes' custom `event: hermes.tool.progress` SSE
# frames, which fails every profile that owns tools. Coding work that genuinely
# wants a repo-editing agent still goes to `develop`/`agent-task`.
#
# Env vars:
#   AGENT_OUTPUT_DIR  where answers are filed        (default /workspace/ai)
#   AGENT_TIMEOUT     seconds for the gateway call   (default 900)
#   AGENT_MAX_TOKENS  cap on the answer              (default 4000)
#   AGENT_NOTIFY      send an ntfy message when done (default true)

dept_run() {
    local profile="${DEPT_PROFILE:?DEPT_PROFILE must be set by the department routine}"
    local out_dir="${AGENT_OUTPUT_DIR:-/workspace/ai}"
    local timeout_s="${agent_timeout:-${AGENT_TIMEOUT:-900}}"
    local outbox="${OUTBOX_DIR:-/work/.decree/outbox}"
    mkdir -p "$outbox"   # decree reads the outbox but never creates it

    # The task text is the message body, with the frontmatter stripped.
    local body
    # shellcheck disable=SC2154  # decree sets message_file in the environment of
    # the dept-*.sh routine that sources this file; nothing assigns it here.
    body="$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
        "${message_file}" | sed '/./,$!d')"

    if [ -z "$body" ] && [ -z "${prompt:-}" ]; then
        echo "Nothing to do: message body and prompt are both empty." >&2
        return 1
    fi
    [ -n "${prompt:-}" ] && body="${prompt}

${body}"

    local system="You are the ${profile} department. Use the tools and knowledgebase
available to you where they would change the answer, and say plainly where you
could not find something rather than inventing it.

Write markdown. Be concrete and brief — no preamble, no encouragement."

    local name="${output_name:-${message_id:-${profile}-$(date +%s)}}"
    name="$(basename "$name")"; name="${name%.md}"
    local out="${out_dir}/${name}.md"

    mkdir -p "$out_dir"

    echo "Department : ${profile}"
    echo "Routed via : ${routed_by:-direct}"
    [ -n "${route_reason:-}" ] && echo "Because    : ${route_reason}"

    local raw; raw="$(mktemp "${message_dir:-/tmp}/dept.XXXXXX")"
    # shellcheck disable=SC2064  # expand raw now, not at trap time
    trap "rm -f '$raw'" RETURN

    # shellcheck source=./hermes.sh
    source "$(dirname "${BASH_SOURCE[0]}")/hermes.sh"
    HERMES_API_URL="$(hermes_profile_url "$profile")"
    HERMES_TIMEOUT="$timeout_s"
    export HERMES_API_URL HERMES_TIMEOUT

    hermes_chat "$system" "$body" "${AGENT_MAX_TOKENS:-4000}" > "$raw" || true

    if [ ! -s "$raw" ]; then
        # An empty body is the one failure the gateway does not report as an
        # HTTP error: a tool loop that was cut short still returns 200. Fail so
        # decree retries under max_attempts rather than filing an empty answer.
        echo "The ${profile} profile returned nothing." >&2
        echo "Check: docker logs hermes-agent — a run cut short logs" >&2
        echo "'Interrupted during API call'." >&2
        return 1
    fi

    {
        printf -- '---\n'
        printf 'generated_by: %s\n' "$(jq -rn --arg v "dept-${profile}" '$v|@json')"
        printf 'profile: %s\n' "$(jq -rn --arg v "$profile" '$v|@json')"
        printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        [ -n "${source_file:-}" ] && printf 'source_file: %s\n' "$(jq -rn --arg v "$source_file" '$v|@json')"
        [ -n "${route_reason:-}" ] && printf 'routed_because: %s\n' "$(jq -rn --arg v "$route_reason" '$v|@json')"
        printf -- '---\n\n'
        cat "$raw"
    } > "$out"

    echo "Wrote ${out}"

    if [ "${AGENT_NOTIFY:-true}" = "true" ]; then
        cat > "${outbox}/dept-${profile}-$(date +%s%N).md" << NOTIFY
---
routine: notify
ntfy_title: ${profile} — ${name}
ntfy_priority: default
ntfy_tags: robot
---
${route_reason:-Handled by the ${profile} department.}

Written to workspace/ai/${name}.md
NOTIFY
    fi
}
