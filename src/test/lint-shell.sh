#!/usr/bin/env bash
# lint-shell.sh — shellcheck every tracked shell script.
#
# Runs on the HOST in a throwaway container: shellcheck ships in neither the
# adhoc image nor (usually) the host, and installing it into the decree image
# would force an image rebuild on everyone for a developer-only tool. The
# repo already documents this pattern for `go test` — see testing.md.
#
# Gate is -S warning. The findings that shellcheck cannot resolve are real
# limitations, not latent bugs: decree injects variables ($message_file,
# $PATTERN, …) that the script never assigns, and several routines source a
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

DOCKER_CMD="${DOCKER_CMD:-docker}"
if ! command -v "${DOCKER_CMD%% *}" >/dev/null 2>&1; then
    echo "  FAIL  lint-shell: ${DOCKER_CMD%% *} not found — shellcheck runs in a container" >&2
    exit 1
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

if $DOCKER_CMD run --rm -v "$ROOT":/repo -w /repo \
        --entrypoint shellcheck "$SHELLCHECK_IMAGE" \
        -x -S "$SEVERITY" -f gcc "${FILES[@]}"; then
    echo "  PASS  lint-shell (${#FILES[@]} scripts, -S ${SEVERITY})"
else
    echo "  FAIL  lint-shell — fix the findings above, or add a targeted" >&2
    echo "        '# shellcheck disable=SCxxxx  # <why>' at the site." >&2
    exit 1
fi
