#!/usr/bin/env bash
# lint-shell.sh — shellcheck every tracked shell script.
#
# Runs on the HOST in a throwaway container: shellcheck ships in neither the
# adhoc image nor (usually) the host, and installing it into the decree image
# would force an image rebuild on everyone for a developer-only tool. The
# repo already documents this pattern for `go test` — see testing.md.
#
# Gate is -S warning. The findings that shellcheck cannot resolve are real
# limitations, not latent bugs: decree injects variables ($DECREE_DATA_*,
# $DECREE_MESSAGE, …) that the script never assigns, and several scripts source a
# path computed at runtime. Each such site carries a targeted inline
# `# shellcheck disable=` naming the reason, so the gate stays at warning
# rather than being loosened globally — a blanket exclusion would also hide
# the same code smell somewhere it IS a bug.
#
# Read-only: mounts the repo and reads it; writes nothing.
set -euo pipefail

# Pinned by tag *and* digest, like the image bases in webhook/Dockerfile: the
# tag documents the version, the digest is what Docker actually resolves, so a
# re-pushed tag cannot silently change what this gate enforces.
SHELLCHECK_IMAGE="koalaman/shellcheck-alpine:stable@sha256:c82fe42504fbc9fc68f15d36638e5ee2324ebb8b94e96a3c4e395bf361c49183"
SEVERITY="${SHELLCHECK_SEVERITY:-warning}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "${ROOT}/.." && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "  PASS  lint-shell (not a git repo — skipped)"
    exit 0
fi

# A worker may have neither docker nor podman; CI's lint job always has docker.
# shellcheck source=../utils/adhoc.sh
. src/utils/adhoc.sh
if ! adhoc_find_runtime; then
    echo "  PASS  lint-shell (no docker or podman: skipped; CI's lint job runs it)"
    exit 0
fi

# Tracked shell scripts only. graveyard/ is archived and explicitly out of scope
# (CLAUDE.md principle 9); .githooks/* are shell without a .sh suffix.
mapfile -t FILES < <(git ls-files '*.sh' .githooks/ | grep -v '^graveyard/' || true)

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "  FAIL  lint-shell: no shell scripts found — the file selection is broken" >&2
    exit 1
fi

# Self-check: a forced canary must be reported, otherwise a linter that silently
# no-ops (wrong entrypoint, bad flag, image change) reads as a clean pass. The
# wording avoids opening a line with the tool's own name — that parses as a
# malformed directive, and this file lints itself.
# This is the same "every mechanism has an opposite" rule the suites follow.
_canary="$(mktemp -d)/canary.sh"
printf '#!/usr/bin/env bash\nif [ $undefined_var == "a" ]; then echo hi; fi\n' > "$_canary"
trap 'rm -rf "$(dirname "$_canary")"' EXIT
# Captured, not piped: shellcheck exits non-zero when it finds something, and
# `set -o pipefail` would let that failure win over a successful grep — the
# check would then report "not running" precisely when it IS working.
_canary_out="$($DOCKER_CMD run --rm -v "$(dirname "$_canary")":/c -w /c \
    --entrypoint shellcheck "$SHELLCHECK_IMAGE" -S warning canary.sh 2>/dev/null || true)"
if ! printf '%s' "$_canary_out" | grep -q SC2154; then
    echo "  FAIL  lint-shell: shellcheck did not flag the canary — the linter is not running" >&2
    exit 1
fi

echo "  linting ${#FILES[@]} shell scripts at -S ${SEVERITY}"

_rc=0
$DOCKER_CMD run --rm -v "$ROOT":/repo -w /repo \
    --entrypoint shellcheck "$SHELLCHECK_IMAGE" \
    -x -S "$SEVERITY" -f gcc "${FILES[@]}" || _rc=1

# A plugin's scripts and lib live in its file (automation/plugins/<name>.md, as
# lib/automations/plugin.sh writes it: `scripts:` and `lib:` at the margin, each
# entry a block two spaces in, its text four). Each is written out where the
# stack installs it, scripts/<plugin>/<script>.sh and lib/<path>, beside the
# shared lib, so `# shellcheck source=` lines resolve. awk, not yq: this is the host.
_pd="$(dirname "$_canary")/plugins"; mkdir -p "${_pd}/scripts" "${_pd}/lib"
cp -R automation/lib/. "${_pd}/lib/"
for _p in automation/plugins/*.md automation/plugins/flows/*.md; do
    _n="$(basename "$_p" .md)"; mkdir -p "${_pd}/scripts/${_n}"
    awk -v sdir="${_pd}/scripts/${_n}" -v ldir="${_pd}/lib" '
        /^[A-Za-z_]+:/ { s = ($0 ~ /^scripts:/); l = ($0 ~ /^lib:/); f = ""; next }
        /^---$/ { s = 0; l = 0; f = ""; next }
        s && /^  [a-z][a-z0-9_]*: [|][-+]?$/ { k = $1; sub(/:$/, "", k); f = sdir "/" k ".sh"; printf "" > f; next }
        l && /^  [A-Za-z0-9_][A-Za-z0-9_.\/-]*\.sh: [|][-+]?$/ {
            k = $1; sub(/:$/, "", k); f = ldir "/" k
            d = f; sub(/\/[^\/]*$/, "", d); system("mkdir -p \"" d "\""); printf "" > f; next }
        (s || l) && /^  [^ ]/ { f = ""; next }
        f != "" { print (length($0) >= 4 ? substr($0, 5) : "") > f }' "$_p"
done
mapfile -t PLUGIN_SCRIPTS < <(cd "$_pd" && find scripts -name '*.sh' | sort)
mapfile -t PLUGIN_LIB < <(cd automation/plugins && awk '/^lib:/{l=1; next} /^[A-Za-z_-]/{l=0} l && /^  [A-Za-z0-9_][A-Za-z0-9_.\/-]*\.sh: [|][-+]?$/ {k=$1; sub(/:$/, "", k); print "lib/" k}' *.md flows/*.md | sort)
_expected="$(cat automation/plugins/*.md automation/plugins/flows/*.md | awk '/^scripts:/{s=1; next} /^[A-Za-z_-]/{s=0} s && /^  [a-z][a-z0-9_]*: [|][-+]?$/' | wc -l)"
if [ "${#PLUGIN_SCRIPTS[@]}" -ne "$_expected" ]; then
    echo "  FAIL  lint-shell: wrote ${#PLUGIN_SCRIPTS[@]} plugin scripts, the plugins have ${_expected}" >&2; _rc=1
fi
for _f in ${PLUGIN_LIB[@]+"${PLUGIN_LIB[@]}"}; do
    [ -s "${_pd}/${_f}" ] || { echo "  FAIL  lint-shell: plugin ${_f} was not written out" >&2; _rc=1; }
done
echo "  linting ${#PLUGIN_SCRIPTS[@]} plugin scripts and ${#PLUGIN_LIB[@]} plugin lib files (automation/plugins/)"
$DOCKER_CMD run --rm -v "$_pd":/plugins -w /plugins \
    --entrypoint shellcheck "$SHELLCHECK_IMAGE" \
    -x -S "$SEVERITY" -f gcc "${PLUGIN_SCRIPTS[@]}" ${PLUGIN_LIB[@]+"${PLUGIN_LIB[@]}"} \
    | sed 's#^scripts/\([^/]*\)/#automation/plugins/\1.md: scripts.#' || _rc=1

if [ "$_rc" -eq 0 ]; then
    echo "  PASS  lint-shell (${#FILES[@]} scripts, ${#PLUGIN_SCRIPTS[@]} plugin scripts and ${#PLUGIN_LIB[@]} plugin lib files, -S ${SEVERITY})"
else
    echo "  FAIL  lint-shell — fix the findings above, or add a targeted" >&2
    echo "        '# shellcheck disable=SCxxxx  # <why>' at the site." >&2
    exit 1
fi
