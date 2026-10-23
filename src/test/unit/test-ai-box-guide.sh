#!/usr/bin/env bash
# test-ai-box-guide.sh — the separate-AI-box guide stays generic.
#
# The guide is drawn from one real machine, so the easy regression is pasting
# that machine's details into it. It speaks only in <ai-box> and ~/ placeholders:
# no IP address, no user@host, no path under a home directory. It must also stay
# reachable from the hosting and model-endpoint docs it is meant to be found from.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -d "${REPO_DIR}/site/docs" ]] || REPO_DIR="/repo"

DOCS="${REPO_DIR}/site/docs"
GUIDE="${DOCS}/hosting/ai-box.md"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
# _absent <name> <ERE> — passes when the guide has no line matching it.
_absent() {
    local hit
    if hit=$(grep -nE "$2" "$GUIDE"); then _fail "$1" "$hit"; else _ok "$1"; fi
}
# _links <name> <file> — passes when <file> links to the guide.
_links() {
    if grep -qE '\]\((\./|\./hosting/)ai-box\)' "$2"; then _ok "$1"; else _fail "$1" "no link in ${2#"$DOCS/"}"; fi
}

[[ -f "$GUIDE" ]] && _ok "the guide exists" || _fail "the guide exists" "$GUIDE"

_absent "no IPv4 address"              '(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)'
_absent "no path under a home dir"     '/home/|/Users/|/root/'
_absent "no user@host"                 '[A-Za-z0-9._-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*:'
_absent "no username in a home path"   '~[A-Za-z0-9_-]+/'

_links "linked from the hosting docs"          "${DOCS}/hosting/index.md"
_links "linked from the model-endpoints docs"  "${DOCS}/configuration.md"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
