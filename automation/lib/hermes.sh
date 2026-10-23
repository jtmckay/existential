#!/usr/bin/env bash
# hermes.sh — shared helpers for talking to the hermes gateway.
#
# Sourced, never run. Hermes is optional: it is for work that needs an agent with
# tools. A plain completion goes straight to the model through model.sh, which
# this builds on, so the request shape lives in one place.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/hermes.sh"
#
#   hermes_chat <system> <user> <max_tokens>   → assistant text on stdout
#   hermes_profile_url <profile>               → base URL for a named profile
#   hermes_followup_notice → system-prompt paragraph on stdout
#
# Env vars:
#   HERMES_GATEWAY_URL  default http://hermes-agent:8642 (used by hermes_profile_url)
#   HERMES_API_URL   default http://hermes-agent:8642/v1
#   HERMES_API_KEY   bearer token; omitted from the request when empty
#   HERMES_MODEL     optional; the gateway's own default is used when unset
#   HERMES_TIMEOUT   seconds, default 120

# shellcheck source=model.sh
source "$(dirname "${BASH_SOURCE[0]}")/model.sh"

# Base URL for one hermes profile, for callers that set HERMES_API_URL per call.
#
# Profile multiplexing (GATEWAY_MULTIPLEX_PROFILES) serves every named profile
# off the one listener under /p/<profile>/v1; the default profile keeps the bare
# /v1. An unknown profile 404s rather than falling back, so a typo here fails
# loudly instead of quietly running against the wrong toolset.
hermes_profile_url() {
    local profile="${1:-}"
    local base="${HERMES_GATEWAY_URL:-http://hermes-agent:8642}"
    base="${base%/}"
    case "$profile" in
        ""|default) printf '%s/v1\n' "$base" ;;
        *)          printf '%s/p/%s/v1\n' "$base" "$profile" ;;
    esac
}

# System-prompt paragraph telling hermes how to trigger follow-up automation.
# Hermes is a remote gateway, so nothing exported here reaches it — this text
# is the only channel. Its endpoints are the /hermes/* ones in
# automation/decree-go-rest.yml, on a secret hermes holds as
# AUTOMATION_WEBHOOK_AUTH; the traceparent header joins its follow-up to this
# run's trace, so Grafana shows the whole flow.
hermes_followup_notice() {
    cat <<EOF
If this task calls for follow-up automation, ask decree for it over HTTP — you
have no access to automation/, and never need it:

  curl -fsS -X POST http://automation-webhook:8801/hermes/task/<profile> \\
    -H "Authorization: Bearer \$AUTOMATION_WEBHOOK_AUTH" \\
    -H "traceparent: ${TRACEPARENT:-}" --data-binary 'what to do'

hands a task to a hermes profile (default, research, …), and
/hermes/notify/<title> sends the body as a push notification. URL-encode the
path parameter.
EOF
}

# hermes_chat <system> <user> <max_tokens> — model_chat aimed at the gateway.
# HERMES_MODEL empty sends no model, so the gateway's own default answers.
hermes_chat() {
    MODEL_URL="${HERMES_API_URL:-http://hermes-agent:8642/v1}" \
    MODEL_NAME="${HERMES_MODEL:-}" \
    MODEL_API_KEY="${HERMES_API_KEY:-}" \
    MODEL_TIMEOUT="${HERMES_TIMEOUT:-120}" \
        model_chat "$@"
}
