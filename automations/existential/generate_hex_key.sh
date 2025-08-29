#!/bin/bash

# Generate a random hexadecimal key of specified length
# Uses only characters 0-9 and a-f (lowercase hex)
# Compatible with Windows (Git Bash/WSL), Mac, and Linux

generate_hex_key() {
    local length="${1:-32}"  # Default to 32 if no length specified
    local hex_charset="0123456789abcdef"
    local charset_len=${#hex_charset}
    
    # Validate input is a positive integer
    if ! [[ "$length" =~ ^[0-9]+$ ]] || [ "$length" -lt 1 ]; then
        echo "Error: Length must be a positive integer" >&2
        return 1
    fi
    
    # Use the safe generation method consistently
    local hex_key=""
    
    for i in $(seq 1 "$length"); do
        # Generate random index using multiple entropy sources
        local rand_seed
        if [ -r /dev/urandom ]; then
            # Use /dev/urandom for better randomness
            rand_seed=$(od -An -N4 -tu4 < /dev/urandom | tr -d ' ')
        elif command -v openssl >/dev/null 2>&1; then
            # Use openssl for entropy
            rand_seed=$(openssl rand -hex 4 | od -An -tx4 | tr -d ' ' | head -c 8)
            rand_seed=$((0x$rand_seed))
        else
            # Fallback to time-based randomness
            rand_seed=$(($(date +%s%N 2>/dev/null || date +%s) + RANDOM + i + $$))
        fi
        
        local char_index=$((rand_seed % charset_len))
        hex_key="${hex_key}${hex_charset:$char_index:1}"
    done
    
    # Validate the hex key contains only safe characters
    if ! echo "$hex_key" | grep -q '^[0-9a-f]*$'; then
        echo "Error: Generated hex key contains invalid characters" >&2
        return 1
    fi
    
    echo "$hex_key"
}

# Convenience functions for common lengths
generate_32_char_hex() {
    generate_hex_key 32
}

generate_64_char_hex() {
    generate_hex_key 64
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Get length from command line argument, default to 32
    length="${1:-32}"
    
    # Validate argument
    if ! [[ "$length" =~ ^[0-9]+$ ]] || [ "$length" -lt 1 ]; then
        echo "Usage: $0 [LENGTH]"
        echo "Generate a hexadecimal key of specified length"
        echo "Examples:"
        echo "  $0 32    # Generate 32-character hex key"
        echo "  $0 64    # Generate 64-character hex key"
        echo "  $0       # Generate 32-character hex key (default)"
        exit 1
    fi
    
    hex_key=$(generate_hex_key "$length")
    echo "$hex_key"
    # Verify length for user
    echo "Generated ${#hex_key} character hex key" >&2
fi
