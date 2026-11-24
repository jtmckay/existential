#!/usr/bin/env bash
# decree-check.sh — `decree check` each decree project with every plugin tagged
# for it installed, every message template queued, and each plugin on its own.
#
# No project is checkable as it sits: its plugins are written from
# automation/plugins/, and inbox/ and cron/ are the user's. So each (automation,
# backup, host) is assembled in a temp dir from every plugin whose x-exist-project
# names it, with their order files and every flow's examples in the inbox: that is
# what makes decree check validate the templates' machine and params against the
# machines' data, which is the mistake a rename or a new param makes. Then each
# plugin is checked again alone with the plugins its needs: names, so a needs: that
# misses one fails here, not on the install that turns it on.
#
# Runs in adhoc (decree and yq on PATH): ./existential.sh test decree. Read-only.
set -euo pipefail

REPO="${REPO_DIR:-/repo}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
rc=0

check() {  # <name> <project root>; graphs are drawn by the install, so their warnings are noise here
    local out
    echo "=== decree check: $1 ==="
    out="$(cd "$2" && decree check --no-color 2>&1)" || rc=1
    grep -v '^warning: .*\(graph\.md\|system\.md\|state_files\)' <<<"$out" || true
}

# shellcheck source=../../automation/lib/automations/plugin.sh
. "${REPO}/automation/lib/automations/plugin.sh"
DIR="${REPO}/automation/plugins"
unpack() {  # <project root> <name>...: each plugin installed there, as the stack installs it
    local root="$1"; shift
    plugin_unpack "$@" "$root" >/dev/null || { echo "FAIL  $* does not install" >&2; rc=1; }
}
PLUGINS="$(cd "$DIR" && ls -- *.md flows/*.md | sed 's#^flows/##; s/\.md$//')"

# messages <dir> <name>...: each plugin's order files and examples (messages for
# reading, never installed) into <dir>/inbox, where decree check reads them.
messages() {
    local dir="$1" n src k; shift
    mkdir -p "${dir}/inbox"
    for n in "$@"; do
        src="$(plugin_src "$DIR" "$n")" || continue
        for k in $(yq --front-matter=extract -r '((.order // {}) | keys | .[]), ((.["x-exist-examples"] // {}) | keys | .[] | "x:" + .)' "$src"); do
            if [[ "$k" == x:* ]]; then k="${k#x:}"; printf '%s\n' "$(k="$k" yq --front-matter=extract -r '.["x-exist-examples"][strenv(k)]' "$src")" > "${dir}/inbox/${n}-${k}.md"
            else printf '%s\n' "$(k="$k" yq --front-matter=extract -r '.order[strenv(k)]' "$src")" > "${dir}/inbox/${n}-${k}"; fi
        done
    done
}

# Two plugins shipping one lib path would have one overwrite the other.
dups="$(cd "$DIR" && for f in *.md flows/*.md; do yq --front-matter=extract -r '.["x-exist-lib"] // {} | keys | .[]' "$f"; done | sort | uniq -d)"
[[ -z "$dups" ]] || { echo "FAIL  two plugins ship the same lib file: $(paste -sd' ' <<<"$dups")" >&2; rc=1; }

tagged() {  # <project>: every plugin whose x-exist-project names it
    local n
    for n in $PLUGINS; do plugin_tags "$(plugin_src "$DIR" "$n")" | grep -qxF "$1" && echo "$n"; done
}

# Each project, with every plugin tagged for it.
for project in automation backup host; do
    p="${TMP}/${project}"; mkdir -p "${p}/.decree"
    [[ "$project" != automation ]] || cp "${REPO}/automation/decree-go-rest.exist.yml" "${p}/.decree/decree-go-rest.yml"
    # shellcheck disable=SC2046
    unpack "$p" $(tagged "$project")
    # shellcheck disable=SC2046
    messages "${p}/.decree" $(tagged "$project")
    check "$project" "$p"
done

# Each plugin alone, with only what its needs: reach and the plugin system:
# what an install that turns just that one on gets.
for n in $PLUGINS; do
    q="${TMP}/alone-${n}"; mkdir -p "${q}/.decree"
    cp "${REPO}/automation/decree-go-rest.exist.yml" "${q}/.decree/decree-go-rest.yml"
    # shellcheck disable=SC2086
    unpack "$q" $PLUGIN_KERNEL "$n"
    messages "${q}/.decree" "$n"
    if (cd "$q" && decree check --no-color >/dev/null 2>&1); then
        echo "PASS  ${n} passes decree check with only what it needs"
    else
        echo "FAIL  ${n} fails decree check with only what it needs:" >&2
        (cd "$q" && decree check --no-color 2>&1 | grep -v '^warning' | head -5) >&2; rc=1
    fi
done

exit "$rc"
