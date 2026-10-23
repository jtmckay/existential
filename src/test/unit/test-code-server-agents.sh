#!/usr/bin/env bash
# test-code-server-agents.sh — the AI CLIs code-server's terminal ships.
#
#   opencode  entrypoint.sh's _opencode_config must aim opencode at the chat
#             role's /v1 URL and tag, so a user sets nothing beyond the endpoint.
#   tmx       services/automation/decree/tmx.sh (the image's /etc/profile.d copy)
#             must never start a second session under a name already running —
#             `tmx -d claude claude remote-control` is safe to re-run.
#
# entrypoint.sh cannot be sourced (its top level installs and execs code-server),
# so the helper is extracted by name, as test-hermes-model.sh does. The tmx half
# needs tmux, which the decree image ships; it skips where tmux is absent. Its
# tmux server runs on a private socket, removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
ENTRY="${REPO_DIR}/services/code-server/entrypoint.sh"
TMX="${REPO_DIR}/services/automation/decree/tmx.sh"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq() { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }

TMP="$(mktemp -d)"
SOCK="${TMP}/tmux.sock"
trap 'tmux -S "$SOCK" kill-server 2>/dev/null; rm -rf "$TMP"' EXIT

# ── opencode ──────────────────────────────────────────────────────────────────
awk '/^_opencode_config\(\)/{f=1} f{print} f&&/^}$/{f=0}' "$ENTRY" > "${TMP}/fns.sh"
# shellcheck disable=SC1091  # generated above
. "${TMP}/fns.sh"
if ! declare -F _opencode_config >/dev/null; then
    _fail "extracted _opencode_config" "renamed? update the awk pattern above"
else
    cfg="$(_opencode_config "http://chatbox:11434/v1" "gemma4:e2b-it-qat")"
    assert_eq "opencode model is the chat tag" "existential/gemma4:e2b-it-qat" \
        "$(jq -r .model <<<"$cfg")"
    assert_eq "opencode provider speaks openai-compatible" "@ai-sdk/openai-compatible" \
        "$(jq -r .provider.existential.npm <<<"$cfg")"
    assert_eq "opencode baseURL is the chat role's URL" "http://chatbox:11434/v1" \
        "$(jq -r .provider.existential.options.baseURL <<<"$cfg")"
    assert_eq "opencode declares the chat model" "gemma4:e2b-it-qat" \
        "$(jq -r '.provider.existential.models["gemma4:e2b-it-qat"].name' <<<"$cfg")"
fi

# ── tmx ───────────────────────────────────────────────────────────────────────
if ! command -v tmux >/dev/null; then
    echo "  skipped tmx — tmux not installed here (the decree image ships it)"
else
    # tmx calls bare `tmux`; route it to the private socket.
    tmux() { command tmux -S "$SOCK" "$@"; }
    # shellcheck disable=SC1090
    . "$TMX"
    tmx -d claude sleep 300
    tmx -d claude sleep 300
    tmx -d claude-2 sleep 300
    assert_eq "tmx -d twice leaves one claude session" "1" \
        "$(tmux ls -F '#S' | grep -cx claude)"
    assert_eq "an exact name: claude-2 is its own session" "1" \
        "$(tmux ls -F '#S' | grep -cx claude-2)"
fi

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→non-zero-exit path is itself testable (src/test/run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[[ $FAIL -eq 0 ]] || { printf '  - %s\n' "${FAIL_NAMES[@]}"; exit 1; }
