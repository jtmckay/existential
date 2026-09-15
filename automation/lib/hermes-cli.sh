#!/usr/bin/env bash
# hermes-cli.sh — one prompt to the hermes gateway, answer on stdout.
#
# Run by path (hence 755), never sourced: decree's `commands.ai_router` /
# `ai_interactive` invoke it, and code-server symlinks it onto PATH as `hermes`
# so the integrated terminal reaches the same gateway a routine does. The
# request shape lives in lib/hermes.sh — this is only the CLI around it, so
# there is still exactly one place that knows how to talk to hermes.
#
#   hermes "what is in workspace/notes/plan.md?"
#   echo "summarise this" | hermes
#   hermes --profile research "..."   # a named profile's own toolset
#
# One prompt, one answer, no session. The upstream hermes CLI — the interactive
# TUI with sessions, skills and slash commands — is a local agent that reads its
# own HERMES_HOME, so it only runs where that lives: inside hermes-agent. `-h`
# prints how to reach it.
#
# Hermes runs its own tool loop against its own MCP servers (openviking,
# firecrawl, playwright), so the prompt says what it wants and hermes decides
# what to reach for. It has no terminal and no mount into this container: to
# get work done here, ask it to write a message to workspace/outbox/ (see
# workspace/outbox/README.md) and outbox-relay.sh turns that into a decree
# message.
#
# Env: HERMES_API_KEY (the gateway rejects an unauthenticated call),
# HERMES_GATEWAY_URL, HERMES_MODEL, HERMES_TIMEOUT, HERMES_MAX_TOKENS,
# HERMES_SYSTEM.
set -euo pipefail

# readlink -f so the code-server PATH symlink still finds hermes.sh next door.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=./hermes.sh
source "${SCRIPT_DIR}/hermes.sh"

usage() {
    cat >&2 <<'USAGE'
usage: hermes [--profile <name>] <prompt>   (or pipe the prompt in)

One prompt, one answer — there is no session and no history: this is a curl
wrapper around the gateway, not the upstream hermes CLI. For the interactive
TUI (sessions, skills, slash commands) run the real CLI where its HERMES_HOME
and MCP servers are, from a shell on the host:

  docker exec -it hermes-agent /opt/hermes/.venv/bin/hermes chat
  docker exec -it -e HERMES_HOME=/opt/data/profiles/<name> hermes-agent \
      /opt/hermes/.venv/bin/hermes chat
USAGE
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

profile=""
if [ "${1:-}" = "--profile" ]; then
    profile="${2:-}"
    shift 2
    [ -n "$profile" ] || { echo "hermes: --profile needs a name" >&2; exit 2; }
fi

if [ "$#" -gt 0 ]; then
    prompt="$*"
elif [ -t 0 ]; then
    # No prompt and nobody piping one in: `cat` here would look like a hang.
    usage
    exit 2
else
    prompt="$(cat)"
fi

if [ -z "${prompt//[[:space:]]/}" ]; then
    usage
    exit 2
fi

if [ -z "${HERMES_API_KEY:-}" ]; then
    echo "hermes: HERMES_API_KEY is empty — enable hermes so the gateway credential is passed through" >&2
    exit 1
fi

HERMES_API_URL="$(hermes_profile_url "$profile")"
export HERMES_API_URL

answer="$(hermes_chat "${HERMES_SYSTEM:-You are a helpful assistant. Answer directly.}" \
    "$prompt" "${HERMES_MAX_TOKENS:-2000}")"

if [ -z "$answer" ]; then
    echo "hermes: no answer from the gateway (check: docker logs hermes-agent)" >&2
    exit 1
fi

printf '%s\n' "$answer"
