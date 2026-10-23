#!/usr/bin/env bash
# test-value-proposition.sh — the homepage, README and intro make one pitch.
#
# The tagline and hero lede are exact copy, shown in the hero and repeated as the opening
# of README.md and site/docs/intro.md, which also name the Diagram. Retired pitches
# and claims the repo does not back must not creep back into any of them.
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

# JSX wraps lines, so compare the source with whitespace collapsed.
_flat() { tr -s ' \n' '  ' < "${REPO_DIR}/$1"; }
LEDE="Some mornings you wake up able to see the whole board. Most mornings you don't. Existential is where the sharp you leaves orders for every other you, and makes sure they're carried out."
for f in site/src/pages/index.tsx README.md site/docs/intro.md; do
    if _flat "$f" | grep -qF "$LEDE"; then _ok "hero lede in $f"; else _fail "hero lede in $f"; fi
done

WHY=site/src/components/HomepageWhy/index.tsx
first=$(grep -A2 "<HomepageHeader />" "${REPO_DIR}/site/src/pages/index.tsx" | grep -o "<Homepage[A-Za-z]* />" | sed -n 2p)
if [[ "$first" == "<HomepageWhy />" ]]; then _ok "Diagram follows the hero"; else _fail "Diagram follows the hero" "got $first"; fi
for heading in "Write your Diagram." "Nobody else decides what you look at."; do
    if grep -qF "$heading" "${REPO_DIR}/$WHY"; then _ok "heading: $heading"; else _fail "heading: $heading" "missing from $WHY"; fi
done

# README and intro name the Diagram in their opening, before the first section.
for f in README.md site/docs/intro.md; do
    opening=$(sed '/^## /q' "${REPO_DIR}/$f")
    if grep -q Taravangian <<<"$opening" && grep -q Diagram <<<"$opening"; then
        _ok "$f opening names Taravangian and the Diagram"
    else
        _fail "$f opening names Taravangian and the Diagram"
    fi
done

# Retired pitches, unbacked claims ("nothing leaves the house": Claude Code and a remote
# Nextcloud are default), generic lines and self-help phrasing.
if hit=$(cd "$REPO_DIR" && grep -rniE 'second brain|software already exists|nothing leaves the house|unplug the internet|take ownership of your digital life|less screen time|full potential|supercharge|unlock' \
        site/src site/docusaurus.config.ts README.md site/docs/intro.md); then
    _fail "no retired or unbacked pitch" "$hit"
else
    _ok "no retired or unbacked pitch"
fi

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
