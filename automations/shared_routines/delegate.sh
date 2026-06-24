#!/usr/bin/env bash
# Delegate
#
# Hands a message off to the SECRET-FREE opencode sidecar (decree-delegate) for any
# routine that needs to call an LLM. This is the safe way to run an AI step over
# untrusted input: the sidecar mounts NO /secrets, so prompt-injection in the
# content can't exfiltrate credentials (SEC-10). Tool support (openviking, firecrawl,
# playwright, honcho memory) comes through hermes — the sidecar's opencode model —
# so the sidecar needs none of those service keys either.
#
# How it works:
#   - You send a normal message but set `routine: delegate` and add a `delegate:`
#     field naming the routine you actually want to run.
#   - This routine (running in the MAIN, secret-holding daemon) rewrites the message
#     so `routine:` becomes the delegate target and the `delegate:` line is dropped,
#     then drops it into the sidecar's inbox (mounted at $DELEGATE_INBOX).
#   - The sidecar runs the target routine secret-free. Any follow-up it emits via
#     $OUTBOX_DIR is routed (by the sidecar's env) back to THIS daemon's inbox, so a
#     step that needs a secret (e.g. notify → ntfy token) runs here, not there — and
#     if that follow-up is itself `routine: delegate`, it side-passes again.
#
# Example inbox message (.decree/inbox/summarize-it.md):
#
#   ---
#   routine: delegate
#   delegate: develop      # the routine to actually run, secret-free, in the sidecar
#   ---
#   Summarize the attached notes and propose three next actions.
set -euo pipefail

# --- Standard Environment Variables ---
message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

# Inbox of the decree-delegate sidecar (its /work/.decree/inbox, bind-mounted here).
DELEGATE_INBOX="${DELEGATE_INBOX:-/delegate-inbox}"

# Pre-check: the sidecar inbox must be mounted and writable (it is the only thing
# this routine needs — no AI tool runs here, the sidecar does the LLM work).
if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    [ -d "$DELEGATE_INBOX" ] || precheck_fail "delegate" "sidecar inbox not mounted at ${DELEGATE_INBOX} — add the decree-delegate service (services/decree/docker-compose.exist.yml)"
    [ -w "$DELEGATE_INBOX" ] || precheck_fail "delegate" "sidecar inbox ${DELEGATE_INBOX} is not writable"
    precheck_pass "delegate"
    exit 0
fi

# `delegate:` frontmatter field → $delegate env var: the routine to actually run.
target="${delegate:-}"

if [ -z "$target" ]; then
    echo "delegate: a 'delegate:' frontmatter field is required (the routine to run in the sidecar)." >&2
    exit 1
fi
# Constrain to a routine slug — no path traversal, no injection into the rewritten
# frontmatter. (Routine names may nest with '/', e.g. notes/compile-notes.)
if ! [[ "$target" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "delegate: invalid target routine '$target' (allowed: letters, digits, . _ - /)." >&2
    exit 1
fi
# '/' is allowed for nested routine names (e.g. notes/compile-notes), but that means
# the slug regex alone would also pass '../evil' or '/etc/x' — block traversal/absolute.
if [[ "$target" == *..* || "$target" == /* ]]; then
    echo "delegate: invalid target routine '$target' (no '..' path traversal or leading '/')." >&2
    exit 1
fi
if [ "$target" = "delegate" ]; then
    echo "delegate: refusing to delegate to 'delegate' (would loop)." >&2
    exit 1
fi
if [ -z "$message_file" ] || [ ! -f "$message_file" ]; then
    echo "delegate: message_file not found ('${message_file}')." >&2
    exit 1
fi

# Rewrite the message: within the FIRST frontmatter block, replace the `routine:`
# value with the target and drop the `delegate:` line. Everything else (other
# frontmatter fields and the entire body) passes through unchanged. If the
# frontmatter somehow has no routine line, inject one right after the opening '---'.
_rewritten="$(awk -v target="$target" '
    BEGIN { fm = 0; done_open = 0; replaced = 0 }
    NR == 1 && $0 == "---" { fm = 1; done_open = 1; print; next }
    fm == 1 && $0 == "---" {
        if (!replaced) { print "routine: " target; replaced = 1 }
        fm = 0; print; next
    }
    fm == 1 && /^[[:space:]]*routine[[:space:]]*:/ { print "routine: " target; replaced = 1; next }
    fm == 1 && /^[[:space:]]*delegate[[:space:]]*:/ { next }   # drop the delegate field
    { print }
' "$message_file")"

# Atomic drop into the sidecar inbox: write a temp file in the same dir, then rename
# so the sidecar daemon never reads a half-written message.
_name="delegate-${message_id:-$(date +%s%N)}.md"
_tmp="$(mktemp "${DELEGATE_INBOX}/.${_name}.XXXXXX")"
printf '%s\n' "$_rewritten" > "$_tmp"
mv -f "$_tmp" "${DELEGATE_INBOX}/${_name}"

echo "Delegated to '${target}' → ${DELEGATE_INBOX}/${_name} (runs secret-free in decree-delegate)."
