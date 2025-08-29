#!/bin/bash

# Generate a random 24-character password
# Uses a mix of uppercase, lowercase, numbers, and safe special characters
# Compatible with Windows (Git Bash/WSL), Mac, and Linux

generate_24_char_password() {
    local length=24
    local charset="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+[]{}|;:,.<>?"
    
    # Method 1: Use /dev/urandom if available (most systems)
    if [ -r /dev/urandom ]; then
        # Generate random bytes and filter to charset
        tr -dc "$charset" < /dev/urandom | head -c "$length"
    else
        # Fallback method using date and RANDOM (less secure but portable)
        local password=""
        local charset_len=${#charset}
        
        for i in $(seq 1 "$length"); do
            # Use current time and RANDOM for entropy
            local rand_seed=$(($(date +%s%N 2>/dev/null || date +%s) + RANDOM))
            local char_index=$((rand_seed % charset_len))
            password="${password}${charset:$char_index:1}"
        done
        
        echo "$password"
    fi
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    password=$(generate_24_char_password)
    echo "$password"
    # Verify length for user
    echo "Generated ${#password} character password" >&2
fi
