#!/usr/bin/env bash
# generate_hex_key.sh — sourced only (see CLAUDE.md Layout). Never run by path.
#
# Lowercase hex, 0-9a-f. Shares _random_from_charset with generate_password.sh,
# which is where the sampling and the entropy-source notes live.

# shellcheck source=src/utils/generate_password.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/generate_password.sh"

# generate_hex_key [length]  — default 32 characters (128 bits).
generate_hex_key() {
    local length="${1:-32}" hex_key

    if ! [[ "$length" =~ ^[0-9]+$ ]] || [ "$length" -lt 1 ]; then
        echo "Error: Length must be a positive integer" >&2
        return 1
    fi

    hex_key="$(_random_from_charset '0-9a-f' "$length")" || return 1

    if [ "${#hex_key}" -ne "$length" ] || ! printf '%s' "$hex_key" | grep -q '^[0-9a-f]*$'; then
        echo "Error: generated hex key failed validation" >&2
        return 1
    fi

    printf '%s\n' "$hex_key"
}
