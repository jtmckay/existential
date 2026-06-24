#!/usr/bin/env bash
# Shared input validators for routines.
#
# Source inside a routine (same pattern as precheck.sh):
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/validate.sh"
#
# Then use in a condition:
#   has_control_chars "$untrusted" && { echo "rejected" >&2; exit 1; }

# True (exit 0) if $1 contains ANY control character (newline, NUL-ish, etc.).
#
# SEC-12: attacker-influenceable fields (S3 object keys, rclone paths) are
# interpolated into decree outbox frontmatter, and decree turns frontmatter keys
# into routine env vars — so a newline could inject extra frontmatter (override
# `processor:`, smuggle env vars). Legitimate values never contain control bytes.
#
# Counts control bytes with tr|wc, NOT grep: grep treats a newline as a line
# separator and would miss the single most dangerous character here.
has_control_chars() {
    [ "$(printf '%s' "${1-}" | LC_ALL=C tr -cd '[:cntrl:]' | wc -c)" -gt 0 ]
}
