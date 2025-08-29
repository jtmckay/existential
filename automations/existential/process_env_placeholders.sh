#!/bin/bash

# Process .env files and replace placeholder variables with actual values
# Replaces EXIST_* placeholders with generated values or environment variables
# Compatible with Windows (Git Bash/WSL), Mac, and Linux

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required generator scripts
if [ -f "$SCRIPT_DIR/generate_password.sh" ]; then
    source "$SCRIPT_DIR/generate_password.sh"
else
    echo "Error: generate_password.sh not found in $SCRIPT_DIR"
    exit 1
fi

if [ -f "$SCRIPT_DIR/generate_hex_key.sh" ]; then
    source "$SCRIPT_DIR/generate_hex_key.sh"
else
    echo "Error: generate_hex_key.sh not found in $SCRIPT_DIR"
    exit 1
fi

if [ -f "$SCRIPT_DIR/find_env_examples.sh" ]; then
    source "$SCRIPT_DIR/find_env_examples.sh"
else
    echo "Error: find_env_examples.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Function to process a single .env file
process_env_generated_file() {
    local file="$1"
    local temp_file="${file}.tmp"
    local changes_made=0
    
    echo "Processing: $file"
    
    # Check if file exists and is readable
    if [ ! -r "$file" ]; then
        echo "  ❌ Error: Cannot read $file"
        return 1
    fi
    
    # Create a temporary file to store the processed content
    if ! cp "$file" "$temp_file"; then
        echo "  ❌ Error: Cannot create temporary file"
        return 1
    fi
    
    # Replace EXIST_24_CHAR_PASSWORD with generated password
    if grep -q "EXIST_24_CHAR_PASSWORD" "$temp_file"; then
        local password=$(generate_24_char_password)
        if [ -n "$password" ]; then
            # Escape special characters for sed
            local escaped_password=$(printf '%s\n' "$password" | sed 's/[[\.*^$()+?{|]/\\&/g')
            sed -i "s/EXIST_24_CHAR_PASSWORD/$escaped_password/g" "$temp_file"
            echo "  ✅ Replaced EXIST_24_CHAR_PASSWORD"
            ((changes_made++))
        else
            echo "  ❌ Error: Failed to generate password"
        fi
    fi
    
    # Replace EXIST_32_CHAR_HEX_KEY with generated 32-char hex key
    if grep -q "EXIST_32_CHAR_HEX_KEY" "$temp_file"; then
        local hex_key_32=$(generate_32_char_hex)
        if [ -n "$hex_key_32" ]; then
            sed -i "s/EXIST_32_CHAR_HEX_KEY/$hex_key_32/g" "$temp_file"
            echo "  ✅ Replaced EXIST_32_CHAR_HEX_KEY"
            ((changes_made++))
        else
            echo "  ❌ Error: Failed to generate 32-char hex key"
        fi
    fi
    
    # Replace EXIST_64_CHAR_HEX_KEY with generated 64-char hex key
    if grep -q "EXIST_64_CHAR_HEX_KEY" "$temp_file"; then
        local hex_key_64=$(generate_64_char_hex)
        if [ -n "$hex_key_64" ]; then
            sed -i "s/EXIST_64_CHAR_HEX_KEY/$hex_key_64/g" "$temp_file"
            echo "  ✅ Replaced EXIST_64_CHAR_HEX_KEY"
            ((changes_made++))
        else
            echo "  ❌ Error: Failed to generate 64-char hex key"
        fi
    fi
    
    # Array of environment variable placeholders to replace
    local env_placeholders=("EXIST_DEFAULT_EMAIL" "EXIST_DEFAULT_USERNAME" "EXIST_TRUENAS_SERVER_ADDRESS" "EXIST_TRUENAS_CONTAINER_PATH")
    
    for placeholder in "${env_placeholders[@]}"; do
        if grep -q "=$placeholder" "$temp_file"; then
            # Get the value from environment variable with the same name
            local env_value="${!placeholder}"
            
            if [ -n "$env_value" ]; then
                # Escape special characters for sed
                local escaped_value=$(printf '%s\n' "$env_value" | sed 's/[[\.*^$()+?{|]/\\&/g')
                # Only replace the placeholder when it appears as a value (after =)
                sed -i "s/=$placeholder$/=$escaped_value/g" "$temp_file"
                echo "  ✅ Replaced $placeholder with '$env_value'"
                ((changes_made++))
            else
                echo "  ⚠️  Warning: Environment variable $placeholder is not set, skipping"
            fi
        fi
    done
    
    # If changes were made, replace the original file
    if [ $changes_made -gt 0 ]; then
        if mv "$temp_file" "$file"; then
            echo "  ✅ Successfully updated $file with $changes_made changes"
            return 0
        else
            echo "  ❌ Error: Failed to update $file"
            rm -f "$temp_file"
            return 1
        fi
    else
        echo "  ℹ️  No placeholder variables found in $file"
        rm -f "$temp_file"
        return 0
    fi
}

# Function to find and process all .env files
process_all_env_generated_files() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"  # Default to depth 2 if not specified
    local processed_count=0
    local success_count=0
    local error_count=0
    
    echo "Processing .env files in: $search_dir"
    echo "Search depth: $max_depth"
    echo "================================================"
    
    # Find all .env files (using similar logic to find_env_examples but for .generated files)
    local env_generated_files=()
    
    if command -v find >/dev/null 2>&1; then
        if [ "$max_depth" -eq 0 ]; then
            # Depth 0: only search in the current directory
            while IFS= read -r file; do
                env_generated_files+=("$file")
            done < <(find "$search_dir" -maxdepth 1 -type f -name "*.env" -not -path "*/graveyard/*" 2>/dev/null)
        else
            # Depth > 0: search subdirectories only (exclude current directory)
            while IFS= read -r file; do
                env_generated_files+=("$file")
            done < <(find "$search_dir" -mindepth 2 -maxdepth $((max_depth + 1)) -type f -name "*.env" -not -path "*/graveyard/*" 2>/dev/null)
        fi
    else
        # Fallback for systems without find
        shopt -s globstar 2>/dev/null || true
        
        if [ "$max_depth" -eq 0 ]; then
            # Depth 0: only current directory
            for file in "$search_dir"/*.env; do
                if [ -f "$file" ] && [[ "$file" != */graveyard/* ]]; then
                    env_generated_files+=("$file")
                fi
            done
        elif [ "$max_depth" -eq 1 ]; then
            # Depth 1: one level down only (skip current directory)
            for file in "$search_dir"/*/*.env; do
                if [ -f "$file" ] && [[ "$file" != */graveyard/* ]]; then
                    env_generated_files+=("$file")
                fi
            done
        elif [ "$max_depth" -eq 2 ]; then
            # Depth 2: one and two levels down (skip current directory)
            for file in "$search_dir"/*/*.env "$search_dir"/*/*/*.env; do
                if [ -f "$file" ] && [[ "$file" != */graveyard/* ]]; then
                    env_generated_files+=("$file")
                fi
            done
        else
            # Depth > 2: use full globstar (skip current directory)
            for file in "$search_dir"/**/*.env; do
                # Skip files in current directory (only include files with at least one subdirectory)
                if [ -f "$file" ] && [[ "$file" != */graveyard/* ]] && [[ "$file" == */*/* ]]; then
                    env_generated_files+=("$file")
                fi
            done
        fi
    fi
    
    if [ ${#env_generated_files[@]} -eq 0 ]; then
        echo "No .env files found in $search_dir"
        echo ""
        echo "💡 Tip: Run create_env_generated.sh first to create .env files from .env.example files"
        return 0
    fi
    
    echo "Found ${#env_generated_files[@]} .env files:"
    echo ""
    
    # Process each file
    for file in "${env_generated_files[@]}"; do
        ((processed_count++))
        
        if process_env_generated_file "$file"; then
            ((success_count++))
        else
            ((error_count++))
        fi
        
        echo ""
    done
    
    # Summary
    echo "Summary:"
    echo "========"
    echo "Processed: $processed_count files"
    echo "Success:   $success_count files"
    echo "Errors:    $error_count files"
    echo ""
    
    if [ $error_count -gt 0 ]; then
        echo "⚠️  Some files could not be processed completely."
        return 1
    else
        echo "✅ All files processed successfully!"
        return 0
    fi
}

# Function to show current environment variable values
show_env_status() {
    echo "Environment Variables Status:"
    echo "============================"
    
    local env_vars=("EXIST_DEFAULT_EMAIL" "EXIST_DEFAULT_USERNAME" "EXIST_TRUENAS_SERVER_ADDRESS" "EXIST_TRUENAS_CONTAINER_PATH")
    
    for var in "${env_vars[@]}"; do
        local value="${!var}"
        if [ -n "$value" ]; then
            echo "✅ $var = '$value'"
        else
            echo "❌ $var = (not set)"
        fi
    done
    
    echo ""
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Parse command line arguments
    search_dir="."
    depth=2
    mode="process"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --status|-s)
                mode="status"
                shift
                ;;
            --depth|-d)
                depth="$2"
                if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
                    echo "Error: Depth must be a non-negative integer"
                    exit 1
                fi
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS] [DIRECTORY]"
                echo ""
                echo "Process .env files and replace placeholder variables with actual values"
                echo ""
                echo "Placeholder Variables:"
                echo "  EXIST_24_CHAR_PASSWORD  → Generated 24-character password"
                echo "  EXIST_32_CHAR_HEX_KEY   → Generated 32-character hex key"
                echo "  EXIST_64_CHAR_HEX_KEY   → Generated 64-character hex key"
                echo "  EXIST_DEFAULT_EMAIL     → Value from \$EXIST_DEFAULT_EMAIL environment variable"
                echo "  EXIST_DEFAULT_USERNAME  → Value from \$EXIST_DEFAULT_USERNAME environment variable"
                echo ""
                echo "OPTIONS:"
                echo "  --status, -s             Show current environment variable values"
                echo "  --depth, -d DEPTH        Search depth (0=current dir only, default=2)"
                echo "  --help, -h               Show this help message"
                echo ""
                echo "DIRECTORY:"
                echo "  Directory to search for .env files (default: current directory)"
                echo ""
                echo "Examples:"
                echo "  export EXIST_DEFAULT_EMAIL='admin@example.com'"
                echo "  export EXIST_DEFAULT_USERNAME='admin'"
                echo "  $0                       # Process .env files in current directory (depth 2)"
                echo "  $0 --depth 0             # Process files in current directory only"
                echo "  $0 --depth 1 /project   # Process files 1 level deep in /project"
                echo "  $0 --status              # Show current environment variable values"
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                exit 1
                ;;
            *)
                search_dir="$1"
                shift
                ;;
        esac
    done
    
    # Execute based on mode
    if [ "$mode" = "status" ]; then
        show_env_status
    else
        echo "Checking environment variables..."
        show_env_status
        
        process_all_env_generated_files "$search_dir" "$depth"
    fi
fi
