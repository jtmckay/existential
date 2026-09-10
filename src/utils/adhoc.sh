#!/usr/bin/env bash
# adhoc.sh — sourced only (see CLAUDE.md Layout). Never run by path.
#
# The single correct way to run a one-shot inside the existential-adhoc
# container. Nine scripts used to hand-roll this `docker compose run` and every
# one of them got it wrong in at least one of two ways:
#
#   1. No --user, so the container ran as root and every file it wrote into a
#      bind mount landed root-owned on the host. That is how .env.shared,
#      automation/secrets/gmail/*, and automation/cron/*.md ended up unwritable
#      by the daemons that then had to read them — and `run fix-permissions`
#      exists as the recovery hatch for exactly this.
#   2. Hardcoded -it, which fails with "the input device is not a TTY" whenever
#      stdin is a pipe — a git pre-push hook being the case that bites.
#
# Neither is a flag you can simply add: --user is CONDITIONAL (see below), so a
# copy that adds it unconditionally trades a Docker bug for a Podman one. There
# is one right answer and this is it.
#
# Usage:
#   . "${REPO_DIR}/src/utils/adhoc.sh"
#   run_adhoc bash /src/some-script.sh
#
# Sets DOCKER_CMD and ROOTLESS_PODMAN if the caller has not already.

# ── Container runtime ─────────────────────────────────────────────────────────
#
# LAZY, and that matters: these scripts self-elevate, so the re-exec'd copy
# sources this file again from INSIDE the container, where there is no docker and
# no podman. Detecting at source time made that second source abort with
# "neither docker nor podman found" — the helper would kill the very script it
# had just launched. Nothing here runs until something actually needs a runtime,
# and `adhoc_self_elevate` returns before that when it is already inside.
#
# Idempotent and cheap to call repeatedly: it no-ops once DOCKER_CMD is set.
adhoc_detect_runtime() {
    [[ -n "${DOCKER_CMD:-}" ]] && return 0
    ROOTLESS_PODMAN=false
    if podman --version &>/dev/null 2>&1; then
        DOCKER_CMD=podman
        podman info 2>/dev/null | grep -q 'rootless: true' && ROOTLESS_PODMAN=true
    elif distrobox-host-exec podman --version &>/dev/null 2>&1; then
        podman() { distrobox-host-exec podman "$@"; }
        DOCKER_CMD=podman
        podman info 2>/dev/null | grep -q 'rootless: true' && ROOTLESS_PODMAN=true
    elif docker --version &>/dev/null 2>&1; then
        DOCKER_CMD=docker
    else
        echo "Error: neither docker nor podman found." >&2
        echo "Install Docker: https://docs.docker.com/engine/install/" >&2
        exit 1
    fi
}

# Repo root, derived from this file's own location so a caller in any service
# directory gets the right compose file without computing it.
_ADHOC_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Build the adhoc image if not present; all interactive setup runs inside it.
ensure_adhoc_built() {
    adhoc_detect_runtime
    if ! $DOCKER_CMD image inspect existential/decree:local &>/dev/null 2>&1; then
        echo "Building existential-adhoc (first run)..."
        $DOCKER_CMD compose -f "${_ADHOC_REPO}/existential-compose.yml" build existential-adhoc
    fi
}

# Run a command inside the adhoc container (TTY-aware, ownership-correct).
run_adhoc() {
    adhoc_detect_runtime
    # `docker compose run` allocates a pseudo-TTY by default (keyed off stdout),
    # which fails with "the input device is not a TTY" when stdin isn't one — e.g.
    # a git-push pre-push hook: stdout is the terminal, stdin is git's pipe. Default
    # to -T (no TTY) and only opt into -it when BOTH ends are real TTYs.
    local tty_flags=(-T)
    [[ -t 0 && -t 1 ]] && tty_flags=(-it)
    # Rootless Podman user-namespace fix: --user uid:gid maps the process to a
    # sub-uid range, not the host user, so bind-mount writes fail. In rootless
    # Podman, container root (UID 0) already maps to the host user, so omitting
    # --user lets writes succeed. Docker Engine has no namespace remapping and
    # needs --user to produce host-owned files.
    local user_flags=(--user "$(id -u):$(id -g)")
    ${ROOTLESS_PODMAN:-false} && user_flags=()
    $DOCKER_CMD compose -f "${_ADHOC_REPO}/existential-compose.yml" run --rm "${tty_flags[@]}" \
        "${user_flags[@]}" \
        --entrypoint "" existential-adhoc "$@"
}

# adhoc_self_elevate <caller's BASH_SOURCE[0]> [script args...]
#
# Re-exec the CALLING script inside adhoc, at its /repo path. No-op when already
# inside (existential-compose.yml sets IN_CONTAINER=1 on the service, so the
# re-exec'd copy sees it and falls through).
#
# Extra `docker compose run` flags — gmail-sync needs `-p 8803:8803` published
# for its OAuth redirect — go in the ADHOC_EXTRA_FLAGS array before the call.
#
# Nine scripts open-coded this. The interesting part is not the duplication, it
# is that eight of the nine dropped the conditional --user and five hardcoded
# -it: the copies did not merely repeat the original, they degraded it.
adhoc_self_elevate() {
    [ -n "${IN_CONTAINER:-}" ] && return 0
    adhoc_detect_runtime
    local caller="$1"; shift
    local script repo in_repo
    script="$(cd "$(dirname "$caller")" && pwd)/$(basename "$caller")"
    repo="$(cd "$(dirname "$script")/../.." && pwd)"
    in_repo="/repo${script#"$repo"}"

    ensure_adhoc_built
    local tty_flags=(-T)
    [[ -t 0 && -t 1 ]] && tty_flags=(-it)
    local user_flags=(--user "$(id -u):$(id -g)")
    ${ROOTLESS_PODMAN:-false} && user_flags=()

    exec $DOCKER_CMD compose -f "${_ADHOC_REPO}/existential-compose.yml" run --rm \
        "${tty_flags[@]}" "${user_flags[@]}" \
        ${ADHOC_EXTRA_FLAGS[@]+"${ADHOC_EXTRA_FLAGS[@]}"} \
        --entrypoint "" existential-adhoc bash "$in_repo" "$@"
}
