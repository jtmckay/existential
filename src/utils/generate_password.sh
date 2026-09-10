#!/usr/bin/env bash
# generate_password.sh — sourced only (see CLAUDE.md Layout). Never run by path.
#
# Draws from a 64-character shell-safe alphabet: alphanumerics plus hyphen and
# underscore. No shell metacharacters, so a value is safe unquoted in shell
# assignments, YAML, JSON, URLs, and in the `sed` replacement that env_set uses.
# 24 characters from 64 symbols is 144 bits.

# _random_from_charset <charset> <length>
#
# Rejection sampling: read a block of raw bytes, keep only the ones that are
# already a character in the charset, repeat until there are enough. Keeping a
# byte only when it is in the set is what makes the result uniform — there is no
# modulo, so there is no modulo bias.
#
# Reads a whole block and filters it in one go rather than piping into
# `head -c <n>`. Callers run under `set -o pipefail` (src/templates.sh:10), and
# `head` closing the pipe early would SIGPIPE `tr` and fail the whole render.
_random_from_charset() {
    local charset="$1" length="$2" out="" raw
    local attempts=0
    while [ "${#out}" -lt "$length" ]; do
        if [ "$attempts" -ge 20 ]; then
            echo "Error: entropy source produced too few usable bytes" >&2
            return 1
        fi
        attempts=$((attempts + 1))

        if [ -r /dev/urandom ]; then
            raw=$(head -c 1024 /dev/urandom | LC_ALL=C tr -dc "$charset") || true
        elif command -v openssl >/dev/null 2>&1; then
            # `openssl rand <n>` emits raw bytes. The old fallback used
            # `openssl rand -hex 4`, which emits ASCII TEXT, then hexdumped that
            # text — so the seed came from the character codes of hex digits, not
            # from the random bytes. It silently collapsed this alphabet to 16
            # symbols and the hex alphabet to the digits 0-9 with no a-f at all.
            raw=$(openssl rand 1024 | LC_ALL=C tr -dc "$charset") || true
        else
            echo "Error: No cryptographic entropy source available (/dev/urandom and openssl both absent)" >&2
            return 1
        fi
        out="${out}${raw}"
    done
    printf '%s' "${out:0:$length}"
}

generate_24_char_password() {
    local password
    password="$(_random_from_charset 'A-Za-z0-9_-' 24)" || return 1

    # Cheap assertion that the pipeline above did what it claims. A generator
    # that silently degrades is the failure this guards against.
    if [ "${#password}" -ne 24 ] || printf '%s' "$password" | grep -q '[^A-Za-z0-9_-]'; then
        echo "Error: generated password failed validation" >&2
        return 1
    fi

    printf '%s\n' "$password"
}
