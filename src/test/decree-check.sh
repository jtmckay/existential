#!/usr/bin/env bash
# decree-check.sh — `decree check` both decree projects as a fresh install has
# them, with every shipped message template queued, plus graph drift.
#
# The projects in the repo are not checkable as they sit: cron/, migrations/
# and inbox/ are the user's gitignored active sets, and automation-backup's
# scripts and lib come from automation/. So each is assembled in a temp dir from
# tracked content, with EVERY template a quest could copy dropped into place —
# that is what makes M1-M3 validate the templates' machine and params against
# the machines' data, which is the mistake a rename or a new param makes.
#
# The committed graph/ must be what `decree graph` writes: routines_snapshot
# hands graph/system.md to hermes as the list of what decree can run.
#
# Runs in adhoc (decree on PATH): ./existential.sh test decree. Read-only,
# except with WRITE_GRAPH=1 (./existential.sh run decree-graph), which copies the
# freshly written graphs back over the committed ones.
set -euo pipefail

REPO="${REPO_DIR:-/repo}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
rc=0

# assemble <name> <machines> <graph> <cron templates> [migration templates] [inbox templates]
assemble() {
    local name="$1" machines="$2" graph="$3" cron="$4" migrations="${5:-}" inbox="${6:-}"
    local d="${TMP}/${name}/.decree"
    mkdir -p "$d"/{cron,migrations,inbox}
    cp -r "$machines" "${d}/machines"
    cp "$(dirname "$machines")/.gitignore" "$d/"
    [[ -d "$graph" ]] && cp -r "$graph" "${d}/graph"
    cp -r "${REPO}/automation/scripts" "${REPO}/automation/lib" "$d/"
    cp "$cron"/*.md "${d}/cron/"
    [[ -n "$migrations" ]] && cp "$migrations"/*.md "${d}/migrations/"
    [[ -n "$inbox" ]] && cp "$inbox"/*.md "${d}/inbox/"
    echo "${TMP}/${name}"
}

# check <name> <project root> <committed graph dir>
check() {
    echo "=== decree check: $1 ==="
    if ! (cd "$2" && decree check --no-color); then
        rc=1
    fi
    (cd "$2" && decree graph --no-color >/dev/null)
    if [[ "${WRITE_GRAPH:-}" == 1 ]]; then
        rm -rf "$3" && cp -r "$2/.decree/graph" "$3" && echo "wrote $3"
    elif ! diff -r "$3" "$2/.decree/graph" >/dev/null 2>&1; then
        echo "FAIL  $3 is stale — regenerate it: ./existential.sh run decree-graph" >&2
        rc=1
    fi
}

p=$(assemble automation "${REPO}/automation/machines" "${REPO}/automation/graph" "${REPO}/automation-examples/cron" \
        "${REPO}/automation-examples/migrations" "${REPO}/automation-examples/inbox")
check automation "$p" "${REPO}/automation/graph"

p=$(assemble backup "${REPO}/services/automation/backup/machines" \
        "${REPO}/services/automation/backup/graph" "${REPO}/services/automation/backup/cron.example")
# A machine both projects run (notify, clean_runs) is one definition, copied:
# the copies must not drift.
for m in "${REPO}"/services/automation/backup/machines/*.yml; do
    a="${REPO}/automation/machines/${m##*/}"
    if [[ -f "$a" ]] && ! cmp -s "$a" "$m"; then
        echo "FAIL  ${m#"${REPO}/"} differs from ${a#"${REPO}/"} — copy it over" >&2
        rc=1
    fi
done
check automation-backup "$p" "${REPO}/services/automation/backup/graph"

exit "$rc"
