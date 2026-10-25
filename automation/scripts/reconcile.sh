#!/usr/bin/env bash
# reconcile — notes/automations/<name>.md is the desired state of one automation.
#
# The spec is a decree migration for `develop` (automation_propose wrote it; you
# accepted it by moving it here, and may edit it). This keeps .decree/ in step:
#   accepted  copied to .decree/migrations/A<stamp>-<name>.md, which the daemon
#             runs: develop builds the machine and its trigger
#   edited    the migration is updated, and once it has run, run again whenever
#             it differs from what develop last built (.decree/applied/)
#   deleted   the machine, its script and its trigger are removed, and its
#             migration with them
# A name that is already a machine decree ships or you wrote is refused.
set -euo pipefail
# shellcheck source=../lib/automations/registry.sh
source "${DECREE_LIB}/automations/registry.sh"

WS="${AUTOMATIONS_WORKSPACE:-/workspace}"
rel="${DECREE_DATA_PATH:?run by the notes/automations file handler, with a path}"
change="${DECREE_DATA_CHANGE:-modified}"
name="$(basename "$rel" .md)"
say() {  # <title> <body>
    echo "reconcile: $2"
    printf '%s\n' "$2" | decree emit --machine notify --param ntfy_title="$1" --param ntfy_tags=robot >/dev/null
}

[[ "$name" =~ ^[a-z][a-z0-9_]{2,40}$ ]] || { say "Automation not built" "${rel}: '${name}' is not a machine name (lowercase, digits and _)."; exit 1; }
migration="$(cd .decree/migrations 2>/dev/null && ls -- A*-"${name}".md 2>/dev/null | head -1 || true)"

if [[ "$change" == deleted ]]; then
    automation_remove "$name"
    [[ -n "$migration" ]] && rm -f ".decree/migrations/${migration}" ".decree/applied/${migration}"
    say "Automation removed" "${name} is removed: ${rel} was deleted."
    exit 0
fi

if [[ -e ".decree/machines/${name}.yml" ]] && ! automation_installed "$name"; then
    say "Automation not built" "${name} is already a machine this stack ships or you wrote. Rename ${rel} to build it under another name."
    exit 1
fi
spec="${WS}/${rel}"
fm() { sed -n "2,/^---\$/s/^$1: *//p" "$spec" | head -1; }
[[ "$(fm machine)" == develop && "$(fm automation)" == "$name" ]] ||
    { say "Automation not built" "${rel} needs 'machine: develop' and 'automation: ${name}' in its frontmatter."; exit 1; }

mkdir -p .decree/migrations
[[ -n "$migration" ]] || migration="A$(date -u +%Y%m%d%H%M%S)-${name}.md"
cp "$spec" ".decree/migrations/${migration}"
if ! grep -qxF "$migration" .decree/processed.md 2>/dev/null; then
    say "Building an automation" "${name}: develop builds it from ${rel} now."     # pending: the daemon runs it
elif ! cmp -s ".decree/migrations/${migration}" ".decree/applied/${migration}"; then
    decree emit < ".decree/migrations/${migration}" >/dev/null
    say "Rebuilding an automation" "${name}: ${rel} changed, so develop builds it again."
else
    echo "reconcile: ${name} already matches ${rel}"
fi
