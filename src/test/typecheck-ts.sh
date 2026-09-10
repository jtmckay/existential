#!/usr/bin/env bash
# typecheck-ts.sh — run `tsc --noEmit` over the repo's TypeScript.
#
# Everything here executes through tsx, which STRIPS types without checking
# them, so `"strict": true` in tsconfig.json was decorative: ~2,700 lines across
# 15 files had never been type-checked by anything. Shell has had a rigorous
# gate (lint-shell.sh) all along; this is the missing half.
#
# Runs in the adhoc container, which already carries typescript, @types/node,
# @types/js-yaml and the runtime deps the sources import.
#
# WHY THE SYMLINK: the deps live at /opt/decree/node_modules, which is not on
# the resolution path for a file at /repo/automation/lib/x.ts — node walks up
# from the importing file, checking /repo/**/node_modules and then /node_modules.
# The container runs unprivileged (adhoc.sh passes --user), so it cannot write /
# ; the link goes at /repo/node_modules instead, which IS on that path. It is
# gitignored, and removed again on exit including on failure.
#
# WHY ERRORS INSIDE node_modules ARE IGNORED: @actual-app/api ships .ts SOURCE,
# not just declarations, and that source does not compile under strict — 19
# errors in @actual-app/core/src/mocks/budget.ts alone. skipLibCheck does not
# cover it (that is .d.ts only) and it is not our code to fix. The gate reports
# every error whose path is outside node_modules, which is exactly our own.
# The canary below is what keeps that from becoming a way to hide real findings.
#
# Read-only: mounts the repo and reads it; writes nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../utils/adhoc.sh
. "${ROOT}/utils/adhoc.sh"

REPO="$(cd "${ROOT}/.." && pwd)"
_LINK="${REPO}/node_modules"

_tsc_in_container() {
    # $1 = extra shell run before tsc (used to plant the canary)
    run_adhoc bash -c "
        set -euo pipefail
        ln -sfn /opt/decree/node_modules /repo/node_modules
        cd /repo
        ${1:-true}
        /opt/decree/node_modules/.bin/tsc --noEmit -p tsconfig.json 2>&1 || true
    "
}

# Self-check: prove the compiler is actually running and actually rejects a bad
# type in OUR tree, before trusting a clean run. A typecheck that silently
# no-ops — wrong path, missing tsc, an include glob that matches nothing —
# otherwise reads as a pass. Same rule the unit suites follow.
# NOT a dotfile: tsconfig's include glob `src/**/*.ts` does not match a leading
# dot, so a canary named .typecheck-canary.ts is never compiled and the
# self-check reports "tsc is not running" on a perfectly working checker.
_canary_src='src/typecheck-canary.ts'
# Refuse to clobber a real node_modules: if one exists and is a directory, this
# is a developer machine that ran npm install and resolution already works.
_made_link=false
if [ ! -e "$_LINK" ]; then _made_link=true; fi
_cleanup() {
    rm -f "${REPO}/${_canary_src}"
    if [ "$_made_link" = true ] && [ -L "$_LINK" ]; then rm -f "$_LINK"; fi
}
trap _cleanup EXIT

_canary_out="$(_tsc_in_container "printf 'export const n: number = \"not a number\";\\n' > ${_canary_src}")" || true
rm -f "${REPO}/${_canary_src}"

if ! printf '%s' "$_canary_out" | grep -q "typecheck-canary"; then
    echo "  FAIL  typecheck-ts: the canary type error was not reported — tsc is not running" >&2
    printf '%s\n' "$_canary_out" | head -5 >&2
    exit 1
fi

OUT="$(_tsc_in_container)"
# Keep only errors under our own include roots. Filtering on a `node_modules/`
# prefix is not enough: pnpm's store means a dependency's source is reported as
# ../opt/decree/node_modules/.pnpm/... — a path that starts with neither. An
# allowlist of the three roots tsconfig actually includes cannot drift from it.
OURS="$(printf '%s\n' "$OUT" \
    | grep -E '^(src|automation|services/automation/src)/[^ ]*\.tsx?\([0-9]+,[0-9]+\): error TS' \
    || true)"

# `git ls-files 'src/**/*.ts'` misses src/generate-compose.ts — a pathspec ** in
# git needs a directory to descend into. Match the roots and filter instead.
_count="$(git -C "$REPO" ls-files '*.ts' 2>/dev/null \
    | grep -E '^(src|automation|services/automation/src)/' | wc -l)"

if [ -z "$OURS" ]; then
    echo "  PASS  typecheck-ts (${_count} files, tsc --noEmit, strict)"
else
    echo "  FAIL  typecheck-ts" >&2
    printf '%s\n' "$OURS" >&2
    exit 1
fi
