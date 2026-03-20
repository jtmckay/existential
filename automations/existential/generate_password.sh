#!/bin/bash

# Generate a random 24-character password
# Uses a mix of uppercase, lowercase, numbers, and safe special characters
# Compatible with Windows (Git Bash/WSL), Mac, and Linux

generate_24_char_password() {
    local length=24
    # Shell-safe character set - only alphanumeric plus hyphen and underscore
    # These characters are safe unquoted in shell assignments, YAML, JSON, URLs, and sed/awk
    # Avoids: ! @ # % * = + and any shell metacharacters (> < | & ; $ ` etc.)
    # 24 chars from a 64-char alphabet = ~143 bits of entropy, which is more than sufficient
    local charset="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    local charset_len=${#charset}

    local password=""

    for i in $(seq 1 "$length"); do
        local rand_seed
        if [ -r /dev/urandom ]; then
            rand_seed=$(od -An -N4 -tu4 < /dev/urandom | tr -d ' ')
        else
            rand_seed=$(($(date +%s%N 2>/dev/null || date +%s) + RANDOM + $$))
        fi

        local char_index=$((rand_seed % charset_len))
        password="${password}${charset:$char_index:1}"
    done

    # Validate the password contains only safe characters
    if echo "$password" | grep -q '[^A-Za-z0-9_-]'; then
        echo "Error: Generated password contains unsafe characters" >&2
        return 1
    fi

    echo "$password"
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    password=$(generate_24_char_password)
    echo "$password"
    # Verify length for user
    echo "Generated ${#password} character password" >&2
fi
