#!/usr/bin/env bash
# test-value-proposition.sh — the homepage, README and intro make one pitch.
#
# The tagline is an exact sentence, shown in the hero and repeated as the opening
# of README.md and site/docs/intro.md. The retired pitches ("second brain",
# "software already exists") must not creep back into any of them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -d "${REPO_DIR}/site/docs" ]] || REPO_DIR="/repo"

TAGLINE='Taking your best brain day, and preserving it for your worst.'

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
# _has <name> <file> — passes when <file> contains the tagline verbatim.
_has() {
    if grep -qF "$TAGLINE" "${REPO_DIR}/$2"; then _ok "$1"; else _fail "$1" "tagline missing from $2"; fi
}

_has "tagline is the site tagline"   site/docusaurus.config.ts
_has "README opens with the tagline" README.md
_has "intro opens with the tagline"  site/docs/intro.md
_has "meta description leads with it" site/src/pages/index.tsx

if grep -q 'siteConfig.tagline' "${REPO_DIR}/site/src/pages/index.tsx"; then
    _ok "hero shows the site tagline"
else
    _fail "hero shows the site tagline"
fi

if hit=$(cd "$REPO_DIR" && grep -rniE 'second brain|software already exists' \
        site/src site/docusaurus.config.ts README.md site/docs/intro.md); then
    _fail "no retired pitch" "$hit"
else
    _ok "no retired pitch"
fi

# The section right after the hero makes the two beats, each with what does it.
WHY=site/src/components/HomepageWhy/index.tsx
first=$(grep -A2 "<HomepageHeader />" "${REPO_DIR}/site/src/pages/index.tsx" | grep -o "<Homepage[A-Za-z]* />" | sed -n 2p)
if [[ "$first" == "<HomepageWhy />" ]]; then _ok "beats follow the hero"; else _fail "beats follow the hero" "got $first"; fi
for beat in "ratchet" "best day sets the floor" "next good day climbs" "Your attention is yours" "No algorithm" "decree machine" "you were here" "ntfy" "capture"; do
    if grep -qiF "$beat" "${REPO_DIR}/$WHY"; then _ok "beat: $beat"; else _fail "beat: $beat" "missing from $WHY"; fi
done

if hit=$(cd "$REPO_DIR" && grep -rniE "full potential" site/src README.md site/docs/intro.md); then
    _fail "no self-help phrasing" "$hit"
else
    _ok "no self-help phrasing"
fi

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
