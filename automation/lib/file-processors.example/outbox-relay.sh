#!/usr/bin/env bash
# shellcheck disable=SC2034  # PATTERN/CRITERIA/IS_PRE_SIGNED are read out of this
# file's source by s3-router and file-processor, not by sourcing it.
# Outbox relay — turn a workspace/outbox/ file into a real decree message.
#
# This is the ONLY door from workspace/ into decree's inbox. Hermes
# (or anything else confined to workspace/) has no mount into automation/ and
# must never be given one — shared_routines/ is read-only from inside the main
# daemon on purpose (see .claude/reference/services.md). Drop a message here
# instead, and the object-store webhook (via workspace-sync) does the rest:
#
# A relayed message deletes itself from workspace/outbox/ on success — both
# the local copy (directly, here) and the remote one — a real outbox empties
# once its mail is sent. Local is removed before remote, not left to
# workspace-pull's own reaction to the resulting webhook event: workspace-sync
# bisyncs on its own 10-min cron on automation-backup, a different daemon with
# no idea how deep automation's queue is, and "remote gone, local still
# there, waiting its turn behind other messages" reads to bisync as an
# ordinary new local file — it would re-upload it, undoing the delete.
#
# Nothing here controls how many times the object store fires for one object regardless
# (a webhook redelivery, for instance), so the delete is tidiness either way,
# not the guarantee against running the target routine twice: this (path,
# content) pair, once relayed, is recorded in /data/outbox-relay/seen (same
# pattern as rss-poll.sh's SEEN_FILE) and a later event for that same pair is
# skipped outright, whether or not the deletes above ever landed or the file
# came back. No id field is required in the message for this — the key is the
# object's own path plus a hash of its bytes, not anything the author has to
# set.
#
#   ---
#   routine: agent-task
#   prompt: Summarize this week's notes.
#   correlation_id: D0002-1939-triage-0
#   ---
#
# correlation_id is optional and is NOT decree's own chain — decree's
# collect_outbox always stamps a relayed message with the chain of whoever is
# currently draining the outbox (here, s3-router's own webhook-fan-out
# chain), discarding any chain/seq the dropped file names, so there is no way
# for this relay to make decree treat the result as a continuation of an
# earlier chain. correlation_id is instead a plain custom field: it survives
# untouched (decree only reserves id/chain/seq/routine/migration/trigger), so
# every routine downstream can read it back with
# correlation_id="${correlation_id:-$chain}" (see agent-task.sh) to keep
# tracing this flow across hops that each get their own fresh decree chain.
#
# Copy to lib/file-processors/ to activate — no restart needed; s3-router
# reads the directory per event.
PATTERN="nextcloud:S3/workspace/outbox/.*\.md$"
CRITERIA=""
IS_PRE_SIGNED=false

set -euo pipefail

if [ "$FILE_ACTION" = "removed" ]; then
    echo "Delete event for $FILE_KEY — nothing to relay."
    exit 0
fi

OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
# decree reads the outbox but never creates it — an absent dir is silently
# treated as "no messages", so a relay would vanish without an error.
mkdir -p "$OUTBOX_DIR"

# The actual guarantee against a double-run: workspace/outbox/ is a one-shot
# mailbox, not a stable resource, so this exact (path, content) pair is never
# relayed twice within SEEN_TTL_SECONDS — regardless of why the same object-store
# event happened twice. /data survives container restarts (it's decree_data,
# not the runs/ dir clean-runs prunes), so this holds across a daemon restart.
#
# Keyed on content as well as path, not path alone: this reads no id field
# from the message (nothing requires the author to invent one), but path
# alone would mean a SECOND, genuinely different message written to a REUSED
# filename gets silently dropped as "already relayed" forever — worse than a
# duplicate, since a duplicate is just wasteful and a silent drop loses real
# work. Hashing in the content means only a true repeat (same object, same
# bytes) is ever treated as one.
#
# Entries expire after SEEN_TTL_SECONDS (default 1 day) rather than blocking a
# repeat forever: every redelivery/bisync-conflict anomaly actually seen here
# played out within an hour, so a day is a comfortable margin, and a genuinely
# deliberate resend of identical content a day later is a new request, not a
# glitch — it should run again, not vanish silently with no way to force it.
SEEN_DIR="${SEEN_DIR:-/data/outbox-relay}"
mkdir -p "$SEEN_DIR"
SEEN_FILE="${SEEN_DIR}/seen"
SEEN_TTL_SECONDS="${SEEN_TTL_SECONDS:-86400}"
touch "$SEEN_FILE"
_dedup_key="${FILE_KEY}#$(sha256sum "$FILE_PATH" | awk '{print $1}')"
_now="$(date +%s)"

# Prune expired entries before checking — keeps the file bounded and lets an
# entry past its TTL be relayed again. Format per line: "<epoch>\t<key>".
_cutoff=$((_now - SEEN_TTL_SECONDS))
awk -F'\t' -v cutoff="$_cutoff" '$1 >= cutoff' "$SEEN_FILE" > "${SEEN_FILE}.tmp"
mv "${SEEN_FILE}.tmp" "$SEEN_FILE"

if awk -F'\t' -v key="$_dedup_key" '$2 == key { found=1 } END { exit !found }' "$SEEN_FILE"; then
    echo "${FILE_KEY} (same content, within ${SEEN_TTL_SECONDS}s) was already relayed — skipping (idempotent)."
    exit 0
fi

# A real message's frontmatter starts on line 1 — require that before treating
# anything between two `---` lines as frontmatter. Without this check, a plain
# markdown file that merely shows an example message (README.md, this
# processor's own doc comment above) has its example block misread as a live
# one. Not a message: skip quietly, this isn't an error.
if [ "$(head -1 "$FILE_PATH")" != "---" ]; then
    echo "${FILE_KEY} has no frontmatter at line 1 — not a message, skipping."
    exit 0
fi

# Split the dropped file into its YAML frontmatter and body — the same shape
# every decree message uses.
frontmatter="$(awk 'BEGIN{fm=0} /^---$/{fm++; if (fm==2) exit; next} fm==1' "$FILE_PATH")"
body="$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$FILE_PATH" | sed '/\S/,$!d')"

routine="$(printf '%s\n' "$frontmatter" | yq eval '.routine // ""' -)"
# Routine names are slugs (see .claude/skills/decree/reference/routines.md) —
# constraining to that shape means a value safe to print straight into the
# frontmatter we build below, no YAML-escaping needed.
if ! [[ "$routine" =~ ^[a-z0-9-]+$ ]]; then
    echo "Missing or invalid 'routine' field in ${FILE_KEY} — refusing to relay." >&2
    exit 1
fi

correlation_id="$(printf '%s\n' "$frontmatter" | yq eval '.correlation_id // ""' -)"
# Loosely-shaped decree chain ids are the normal value, but this is opaque,
# attacker-influenceable (workspace/) data as far as this script is concerned
# — constrain it before it goes anywhere near a constructed YAML value.
if ! [[ "$correlation_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
    correlation_id=""
fi

# Everything else in the frontmatter is a parameter for the target routine —
# forward it verbatim, re-serialized by yq (not string-built), so whatever it
# contains can't break out of its own field. routine/correlation_id are
# already handled above; chain/seq/id are decree's own reserved fields — decree
# overwrites them on collection regardless (see header comment), so a stray
# one here is inert either way, but there's no reason to forward it.
extra="$(printf '%s\n' "$frontmatter" | yq eval 'del(.routine, .correlation_id, .chain, .seq, .id)' -)"

{
    printf -- '---\n'
    printf 'routine: %s\n' "$routine"
    [ -n "$correlation_id" ] && printf 'correlation_id: %s\n' "$correlation_id"
    [ "$extra" != "{}" ] && printf '%s\n' "$extra"
    printf -- '---\n\n'
    printf '%s\n' "$body"
} > "${OUTBOX_DIR}/outbox-relay-$(date +%s%N).md"

echo "Relayed ${FILE_KEY} -> routine=${routine}${correlation_id:+ correlation_id=${correlation_id}}"

# Record it BEFORE attempting cleanup: the message is already durably queued
# in decree's own outbox, so this is the point of no return — everything after
# this is tidying up, and must not be able to cause a second relay if it fails
# or if the file comes back some other way.
printf '%s\t%s\n' "$_now" "$_dedup_key" >> "$SEEN_FILE"

# Delete LOCAL first, then remote — not "delete remote and let workspace-pull's
# reaction to the resulting webhook event clean up the local copy". That would
# leave a window, between this delete and that separately-queued message
# actually running, where remote is gone but local still exists. workspace-sync
# bisyncs on its own 10-min cron on a DIFFERENT daemon (automation-backup),
# with no idea how deep automation's queue is — if that cron lands inside the
# window, "local present, remote missing" is indistinguishable from an
# ordinary new local file, and bisync dutifully re-uploads it, undoing the
# delete. Removing local ourselves, synchronously, and only then remote,
# closes the window: a bisync tick can now only ever see either both sides
# gone, or local-already-gone-remote-still-there — which correctly reads as
# "propagate the deletion", not "upload this".
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
# Mirrors workspace-pull.sh's own default — keep them in step if you change either.
WORKSPACE_S3_PREFIX="${WORKSPACE_S3_PREFIX:-workspace}"
_local_target="${WORKSPACE_DIR}/${FILE_KEY#S3/${WORKSPACE_S3_PREFIX}/}"
rm -f -- "$_local_target"
echo "Removed locally: ${_local_target}"

# Best-effort and non-fatal: failing this script now (decree would retry the
# whole relay) can't cause a duplicate — the seen-check above already would —
# so there's nothing to protect by treating a failed delete as an error here.
if ! rclone deletefile "$FILE_SOURCE" --config /secrets/rclone/rclone.conf 2>&1; then
    echo "Warning: could not delete ${FILE_SOURCE} after relaying it." >&2
fi
