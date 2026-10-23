#!/usr/bin/env bash
# test-value-proposition.sh — the homepage, README and intro make one pitch.
#
# V1-V9 (migration 008) are exact copy: V1 is the site tagline, V2-V3 the hero lede, V4-V7
# the first section after the hero and V8-V9 the second. Retired pitches, claims the repo does
# not back, and any name for where "Diagram" comes from must not creep back in.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -d "${REPO_DIR}/site/docs" ]] || REPO_DIR="/repo"

# shellcheck disable=SC2034  # V2-V9 are read by name, through ${!v}
{
V1='Your best brain day now carries your worst.'
V2="On a clear day you can see exactly what to do. Then the fog rolls in, and the idea sits in a note you won't open for three weeks."
V3="Existential keeps the clear day running. What you decide when you're sharp becomes an automation that comes to you on its own, on the days you'd never think to look."
V4="Every system you've tried needed you to remember to use it. That's the one thing a bad day takes."
V5="Your good days stop going to catching up. Each one starts where the last one left off."
V6="Everything else on your phone surfaces what someone else decided needs your attention. This surfaces what you decided."
V7="What you're building is your Diagram: the plan your best day wrote, followed on every other one."
V8="When you outgrow how you set it up, and you will, rebuild it your way. Nothing you built is lost: it's all plain files, and it's where the next version starts."
V9="Existential makes no money from you: no ads, no attention to sell, nothing collected. Which AI you talk to is your choice, as private or as easy as you want. Your data improves you."
}

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
# JSX and markdown wrap lines, so compare sources with whitespace collapsed.
_flat() { tr -s ' \n' '  ' < "${REPO_DIR}/$1"; }
# _has <name> <file> <text> — passes when <file> contains <text> verbatim.
_has() {
    if _flat "$2" | grep -qF "$3"; then _ok "$1"; else _fail "$1" "missing from $2: $3"; fi
}

_has "V1 is the site tagline"          site/docusaurus.config.ts "tagline: '$V1'"
_has "README opens with V1"            README.md          "$V1"
_has "intro opens with V1"             site/docs/intro.md "$V1"
_has "meta description leads with V1"  site/src/pages/index.tsx "description=\"$V1"

if grep -q 'siteConfig.tagline' "${REPO_DIR}/site/src/pages/index.tsx"; then
    _ok "hero shows the site tagline"
else
    _fail "hero shows the site tagline"
fi

for v in V2 V3; do
    for f in site/src/pages/index.tsx README.md site/docs/intro.md; do
        _has "$v in $f" "$f" "${!v}"
    done
done

WHY=site/src/components/HomepageWhy/index.tsx
first=$(grep -A2 "<HomepageHeader />" "${REPO_DIR}/site/src/pages/index.tsx" | grep -o "<Homepage[A-Za-z]* />" | sed -n 2p)
if [[ "$first" == "<HomepageWhy />" ]]; then _ok "V4-V9 follow the hero"; else _fail "V4-V9 follow the hero" "got $first"; fi
for v in V4 V5 V6 V7 V8 V9; do _has "$v on the homepage" "$WHY" "${!v}"; done
# V4-V7 are the first section, V8-V9 the second.
sections=$(_flat "$WHY" | sed 's/<section/\n<section/g' | grep -c '^<section')
order=$(_flat "$WHY" | sed 's/<section/\n<section/g' | grep '^<section' |
    while read -r s; do for v in V4 V5 V6 V7 V8 V9; do grep -qF "${!v}" <<<"$s" && printf '%s ' "$v"; done; echo '|'; done | tr -d '\n')
if [[ "$sections" == 2 && "$order" == "V4 V5 V6 V7 |V8 V9 |" ]]; then
    _ok "V4-V7 then V8-V9, in two sections"
else
    _fail "V4-V7 then V8-V9, in two sections" "got $sections sections: $order"
fi

# Retired pitches, unbacked claims ("nothing leaves the house": Claude Code and a remote
# Nextcloud are default), generic lines and self-help phrasing.
if hit=$(cd "$REPO_DIR" && grep -rniE 'second brain|software already exists|nothing leaves the house|unplug the internet|take ownership of your digital life|less screen time|full potential|supercharge|unlock' \
        site/src site/docusaurus.config.ts README.md site/docs/intro.md); then
    _fail "no retired or unbacked pitch" "$hit"
else
    _ok "no retired or unbacked pitch"
fi

# "Diagram" is the only nod: no author, book or character is named.
if hit=$(cd "$REPO_DIR" && grep -rniE 'taravangian|sanderson|stormlight' \
        --exclude-dir=node_modules --exclude-dir=build --exclude-dir=.docusaurus site README.md .claude); then
    _fail "the Diagram's source goes unnamed" "$hit"
else
    _ok "the Diagram's source goes unnamed"
fi

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
