#!/usr/bin/env bash
# decree-check.sh — `decree check` both decree projects with everything the repo
# ships in place, every message template queued, and each plugin on its own.
#
# The projects in the repo are not checkable as they sit: cron/, migrations/
# and inbox/ are the user's gitignored active sets, and automation-backup's
# scripts and lib come from automation/. So each is assembled in a temp dir from
# tracked content, with EVERY file a flow could switch on dropped into place, and
# every flow's examples/ in the inbox —
# that is what makes M1-M3 validate the templates' machine and params against
# the machines' data, which is the mistake a rename or a new param makes. The
# automation project is the plugin system plus every plugin in automation/plugins/;
# then each plugin is checked again alone with the plugins its needs: names, so a
# needs: that misses one fails here, not on the install that turns it on.
#
# Runs in adhoc (decree and yq on PATH): ./existential.sh test decree. Read-only.
set -euo pipefail

REPO="${REPO_DIR:-/repo}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
rc=0

# assemble <name> <machines> <cron templates> [migration templates] [inbox templates]
assemble() {
    local name="$1" machines="$2" cron="$3" migrations="${4:-}" inbox="${5:-}"
    local d="${TMP}/${name}/.decree"
    mkdir -p "$d"/{cron,migrations,inbox}
    cp -r "$machines" "${d}/machines"
    cp "${REPO}/automation/.gitignore" "$d/"
    cp -r "${REPO}/automation/scripts" "${REPO}/automation/lib" "$d/"
    cp "$cron"/*.md "${d}/cron/" 2>/dev/null || true
    [[ -n "$migrations" ]] && cp "$migrations"/*.md "${d}/migrations/"
    [[ -n "$inbox" ]] && cp "$inbox"/*.md "${d}/inbox/"
    echo "${TMP}/${name}"
}

check() {  # <name> <project root>; the daemon draws graph/, so its warnings are noise here
    local out
    echo "=== decree check: $1 ==="
    out="$(cd "$2" && decree check --no-color 2>&1)" || rc=1
    grep -v '^warning: graph/' <<<"$out" || true
}

# shellcheck source=../../automation/lib/automations/registry.sh
. "${REPO}/automation/lib/automations/registry.sh"
# shellcheck source=../../automation/lib/automations/plugin.sh
. "${REPO}/automation/lib/automations/plugin.sh"
unpack() {  # <project root> <name>...: each plugin installed there, as the stack installs it
    local root="$1" n; shift
    for n in "$@"; do plugin_unpack "$n" "$root" >/dev/null || { echo "FAIL  automation/plugins/${n}.md does not install" >&2; rc=1; }; done
}
PLUGINS="$(cd "${REPO}/automation/plugins" && ls -- *.md flows/*.md | sed 's#^flows/##; s/\.md$//')"

# messages <dir> <name>...: each plugin's migrations into <dir>/migrations, and
# its examples (messages for reading, never installed) into <dir>/inbox.
messages() {
    local dir="$1" n src k; shift
    mkdir -p "${dir}/migrations" "${dir}/inbox"
    for n in "$@"; do
        src="$(plugin_src "${REPO}/automation/plugins" "$n")"
        for k in $(yq --front-matter=extract -r '.migrations // {} | keys | .[]' "$src"); do
            printf '%s\n' "$(k="$k" yq --front-matter=extract -r '.migrations[strenv(k)]' "$src")" > "${dir}/migrations/${k}.md"
        done
        for k in $(yq --front-matter=extract -r '.examples // {} | keys | .[]' "$src"); do
            printf '%s\n' "$(k="$k" yq --front-matter=extract -r '.examples[strenv(k)]' "$src")" > "${dir}/inbox/${k}.md"
        done
    done
}

# Two plugins shipping one cron or migration name would have one overwrite the
# other on a real install, so that fails here.
dups="$(cd "${REPO}/automation/plugins" && for f in *.md flows/*.md; do
          yq --front-matter=extract -r '((.cron // {}) | keys | .[] | "cron/" + .), ((.migrations // {}) | keys | .[] | "migrations/" + .)' "$f"
        done | sort | uniq -d)"
[[ -z "$dups" ]] || { echo "FAIL  two plugins ship the same: $(paste -sd' ' <<<"$dups")" >&2; rc=1; }

mkdir -p "${TMP}/none"
# shellcheck disable=SC2086
messages "${TMP}/all" $PLUGINS
p=$(assemble automation "${REPO}/automation/machines" "${TMP}/none" "${TMP}/all/migrations" "${TMP}/all/inbox")
cp "${REPO}/automation/decree-go-rest.exist.yml" "${p}/.decree/decree-go-rest.yml"
# shellcheck disable=SC2086
unpack "$p" $PLUGINS
check automation "$p"

# Each plugin alone, with only what its needs: reach: what an install that turns
# just that one on gets.
for n in $PLUGINS; do
    q="${TMP}/alone-${n}"; mkdir -p "${q}/.decree"
    cp -r "${REPO}/automation/machines" "${REPO}/automation/scripts" "${REPO}/automation/lib" "${q}/.decree/"
    cp "${REPO}/automation/decree-go-rest.exist.yml" "${q}/.decree/decree-go-rest.yml"
    # shellcheck disable=SC2046
    unpack "$q" $(cd "$q" && plugin_wanted "${REPO}/automation/plugins" none "$n")
    # shellcheck disable=SC2046
    messages "${q}/.decree" $(cd "$q" && plugin_wanted "${REPO}/automation/plugins" none "$n")
    if (cd "$q" && decree check --no-color >/dev/null 2>&1); then
        echo "PASS  ${n} passes decree check with only what it needs"
    else
        echo "FAIL  ${n} fails decree check with only what it needs:" >&2
        (cd "$q" && decree check --no-color 2>&1 | grep -v '^warning' | head -5) >&2; rc=1
    fi
done

# automation-backup: notify, then the plugins its plugins.exist.yml turns on,
# with every cron.example queued.
mkdir -p "${TMP}/notify"; cp "${REPO}/automation/machines/notify.yml" "${TMP}/notify/"
p=$(assemble backup "${TMP}/notify" "${REPO}/services/automation-backup/cron.example")
cp "${REPO}/services/automation-backup/plugins.exist.yml" "${p}/.decree/plugins.yml"
# shellcheck disable=SC2046
unpack "$p" $(cd "$p" && plugin_wanted "${REPO}/automation/plugins" backup)
check automation-backup "$p"

# The agent plugin's lib/ai.sh is decree's own `ai` helper, never edited: it must
# be what this image's decree writes, apart from the shellcheck line on top.
mkdir -p "${TMP}/init" && (cd "${TMP}/init" && decree init --ai claude >/dev/null 2>&1) || true
unpack "${TMP}/agent" agent
if [[ ! -f "${TMP}/init/.decree/lib/ai.sh" ]]; then
    echo "FAIL  decree init wrote no lib/ai.sh to compare the agent plugin's with" >&2; rc=1
elif ! diff <(grep -vx '# shellcheck shell=bash' "${TMP}/agent/.decree/lib/ai.sh") "${TMP}/init/.decree/lib/ai.sh" >/dev/null; then
    echo "FAIL  the agent plugin's lib/ai.sh differs from decree's own — copy .decree/lib/ai.sh from a fresh decree init into automation/plugins/agent.md" >&2; rc=1
else
    echo "PASS  the agent plugin's lib/ai.sh is decree's own ai helper"
fi

exit "$rc"
