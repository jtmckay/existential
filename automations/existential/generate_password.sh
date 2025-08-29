#!/bin/bash

# Generate a random 24-character password
# Uses a mix of uppercase, lowercase, numbers, and safe special characters
# Compatible with Windows (Git Bash/WSL), Mac, and Linux

generate_24_char_password() {
    local length=24
    # Ultra-safe character set - only alphanumeric and a few safe symbols
    # Completely avoids any characters that could cause shell injection or parsing issues
    local charset="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#%*-_=+"
    local charset_len=${#charset}
    
    # Always use the fallback method for maximum safety and control
    local password=""
    
    for i in $(seq 1 "$length"); do
        # Generate random index using multiple entropy sources
        local rand_seed
        if [ -r /dev/urandom ]; then
            # Use /dev/urandom for better randomness
            rand_seed=$(od -An -N4 -tu4 < /dev/urandom | tr -d ' ')
        else
            # Fallback to time-based randomness
            rand_seed=$(($(date +%s%N 2>/dev/null || date +%s) + RANDOM + $$))
        fi
        
        local char_index=$((rand_seed % charset_len))
        password="${password}${charset:$char_index:1}"
    done
    
    # Validate the password contains only safe characters
    if echo "$password" | grep -q '[^A-Za-z0-9!@#%*_=+-]'; then
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
