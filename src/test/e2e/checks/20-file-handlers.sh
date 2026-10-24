#!/usr/bin/env bash
# e2e_file_handlers — the workspace → file-handlers → decree chain.
#
# Staged into the clone's scripts/ by e2e.sh, with 20-file-handlers.yml as its
# machine. Two jobs, told apart by the `path` param:
#   no path   the check: register a handler, write files, assert what got queued
#   a path    the probe: the run that handler queued; assert its params
# Runs inside the `automation` daemon, which watches /workspace. Every write
# lands in the disposable e2e clone.
set -euo pipefail

WS="${E2E_WORKSPACE:-/workspace}"
INBOX="${E2E_INBOX:-/work/.decree/inbox}"
DIR="e2e-handlers"

say()  { printf '  %s\n' "$*"; }
# stdout, not stderr: the run's log keeps stdout, so the reason is in the evidence.
fail() { printf '  FAIL  %s\n' "$*"; exit 1; }

# ── The probe: the run a handler queued ──────────────────────────────────────
if [ -n "${DECREE_DATA_PATH:-}" ]; then
    [[ "$DECREE_DATA_PATH" == "$DIR"/probe-*.md ]] || fail "unexpected path: ${DECREE_DATA_PATH}"
    [ "${DECREE_DATA_CHANGE:-}" = created ] || fail "change is '${DECREE_DATA_CHANGE:-}', want created"
    [ -s "$WS/$DECREE_DATA_PATH" ] || fail "${DECREE_DATA_PATH} is not in the workspace"
    say "ok    handler run got path=${DECREE_DATA_PATH} change=${DECREE_DATA_CHANGE}"
    exit 0
fi

# ── The check ────────────────────────────────────────────────────────────────
TOKEN="$(date +%s%N)"
PROBE="$DIR/probe-${TOKEN}.md"
SKIPPED="$DIR/ignored/probe-${TOKEN}.md"

# Messages queued for one path. Match the path the handler passes, which also
# appears nowhere in this check's own message.
# None found is an answer, not an error: grep's exit 1 must not end the check.
queued() { { grep -l "$1" "$INBOX"/*.md 2>/dev/null || true; } | xargs -r grep -l '^machine: e2e_file_handlers' | wc -l; }

mkdir -p "$WS/$DIR/ignored"
printf 'ignored/\n' > "$WS/$DIR/.gitignore"
# Quiet for 2 s instead of 30, so the check waits seconds, not minutes.
cat >> "$WS/.decree/handlers.yml" <<YML
- match: "$DIR/**/*.md"
  machine: e2e_file_handlers
  changes: [created]
  quiet: 2
YML
sleep 1
say "handler registered for $DIR/**/*.md"

# Five saves half a second apart, as an editor's autosave would make: one run.
for i in 1 2 3 4 5; do
    printf '# Probe %s\n\nsave %s\n' "$TOKEN" "$i" > "$WS/$PROBE"
    printf '# Ignored %s\n\nsave %s\n' "$TOKEN" "$i" > "$WS/$SKIPPED"
    sleep 0.5
done
say "wrote $PROBE and $SKIPPED five times each"

deadline=$(( SECONDS + 60 ))
until [ "$(queued "$PROBE")" -ge 1 ]; do
    [ "$SECONDS" -lt "$deadline" ] || fail "no run queued for $PROBE within 60s — is the file-handlers watcher running? (docker logs automation | grep file-handlers)"
    sleep 1
done
say "ok    a run was queued for $PROBE"

# Past several more quiet periods, to catch a second run or a late ignored one.
sleep 10
n=$(queued "$PROBE"); [ "$n" -eq 1 ] || fail "$n runs queued for $PROBE, want exactly 1"
say "ok    exactly one run for five saves"
n=$(queued "$SKIPPED"); [ "$n" -eq 0 ] || fail "$n run(s) queued for the gitignored $SKIPPED"
say "ok    the gitignored file queued nothing"
