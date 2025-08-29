#!/bin/bash

# Unified Example File Processor
# This script systematically finds and processes ALL .example files in a project
# It creates counterpart files and processes placeholders with special handling for root-level files
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

if [ -f "$SCRIPT_DIR/interactive_cli_replacer.sh" ]; then
    source "$SCRIPT_DIR/interactive_cli_replacer.sh"
else
    echo "Error: interactive_cli_replacer.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Backward compatibility functions
find_env_examples() {
    find_example_files "$1" "$2" "*.env.example"
}

# Function to find docker-compose.yml files (for service enablement compatibility)
find_docker_compose_files() {
    find_example_files "$1" "$2" "docker-compose.yml"
}

# Function to get docker-compose files as service paths (directory names)
get_docker_compose_service_paths() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    
    local compose_files=()
    mapfile -t compose_files < <(find_docker_compose_files "$search_dir" "$max_depth")
    
    local service_paths=()
    for file in "${compose_files[@]}"; do
        # Get directory containing the docker-compose.yml
        local service_dir=$(dirname "$file")
        # Convert to relative path from search_dir
        local relative_path="${service_dir#$search_dir/}"
        # Remove leading ./ if present
        relative_path="${relative_path#./}"
        service_paths+=("$relative_path")
    done
    
    # Remove duplicates and sort
    if [ ${#service_paths[@]} -gt 0 ]; then
        printf '%s\n' "${service_paths[@]}" | sort -u
    fi
}
find_example_files() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    local file_pattern="${3:-*.example}"  # Default to *.example, can be customized
    local files=()
    
    # Validate depth parameter
    if ! [[ "$max_depth" =~ ^[0-9]+$ ]]; then
        echo "Error: Depth must be a non-negative integer" >&2
        return 1
    fi
    
    # Use find with basic options - works on all platforms
    if command -v find >/dev/null 2>&1; then
        if [ "$max_depth" -eq 0 ]; then
            # Depth 0: only search in the current directory (no subdirectories)
            while IFS= read -r file; do
                files+=("$file")
            done < <(find "$search_dir" -maxdepth 1 -type f -name "$file_pattern" -not -path "*/graveyard/*" 2>/dev/null)
        else
            # Depth > 0: search subdirectories only (exclude current directory)
            while IFS= read -r file; do
                files+=("$file")
            done < <(find "$search_dir" -mindepth 2 -maxdepth $((max_depth + 1)) -type f -name "$file_pattern" -not -path "*/graveyard/*" 2>/dev/null)
        fi
    else
        # Fallback for systems without find (rare but possible)
        # Use shell globbing - less efficient but more portable
        shopt -s globstar 2>/dev/null || true
        
        if [ "$max_depth" -eq 0 ]; then
            # Depth 0: only current directory
            for file in "$search_dir"/$file_pattern; do
                if [ -f "$file" ] && [[ "$file" != */graveyard/* ]]; then
                    files+=("$file")
                fi
            done
        elif [ "$max_depth" -eq 1 ]; then
            # Depth 1: one level down only (skip current directory)
            for file in "$search_dir"/*/$file_pattern; do
                if [ -f "$file" ] && [[ "$file" != */graveyard/* ]]; then
                    files+=("$file")
                fi
            done
        elif [ "$max_depth" -eq 2 ]; then
            # Depth 2: one and two levels down (skip current directory)
            for file in "$search_dir"/*/$file_pattern "$search_dir"/*/*/$file_pattern; do
                if [ -f "$file" ] && [[ "$file" != */graveyard/* ]]; then
                    files+=("$file")
                fi
            done
        else
            # Depth > 2: use full globstar (skip current directory)
            for file in "$search_dir"/**/$file_pattern; do
                # Skip files in current directory (only include files with at least one subdirectory)
                if [ -f "$file" ] && [[ "$file" != */graveyard/* ]] && [[ "$file" == */*/* ]]; then
                    files+=("$file")
                fi
            done
        fi
    fi
    
    # Return the array elements
    printf '%s\n' "${files[@]}"
}

# Function to check if file has EXIST_CLI placeholders
has_exist_cli_placeholders() {
    local file="$1"
    [ -f "$file" ] && grep -q "EXIST_CLI" "$file" 2>/dev/null
}

# Function to check if file has EXIST_* placeholders (any kind)
has_exist_placeholders() {
    local file="$1"
    [ -f "$file" ] && grep -q "EXIST_" "$file" 2>/dev/null
}

# Function to get all EXIST_DEFAULT_* variables from root .env file
get_exist_default_variables() {
    local root_env_file="${1:-.env}"
    local defaults=()
    
    if [ ! -f "$root_env_file" ]; then
        echo "⚠️  Warning: Root .env file not found: $root_env_file" >&2
        return 0
    fi
    
    # Extract all EXIST_DEFAULT_* variables from the file
    while IFS='=' read -r var_name var_value; do
        # Skip comments and empty lines
        [[ "$var_name" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$var_name" ]] && continue
        
        # Check if this is an EXIST_DEFAULT_ variable
        if [[ "$var_name" =~ ^EXIST_DEFAULT_ ]]; then
            # Remove any surrounding quotes from the value
            var_value="${var_value%\"}"
            var_value="${var_value#\"}"
            var_value="${var_value%\'}"
            var_value="${var_value#\'}"
            
            defaults+=("$var_name:$var_value")
            echo "  📝 Found default variable: $var_name = '$var_value'" >&2
        fi
    done < <(grep -E '^[^#]*=' "$root_env_file" 2>/dev/null || true)
    
    # Return the array elements
    printf '%s\n' "${defaults[@]}"
}

# Function to process placeholders in a file (unified version)
process_file_placeholders() {
    local file="$1"
    local use_dynamic_defaults="${2:-true}"  # Enable dynamic defaults by default
    local temp_file="${file}.tmp"
    local changes_made=0
    
    echo "  🔧 Processing placeholders in: $file"
    
    # Check if file exists and is readable
    if [ ! -r "$file" ]; then
        echo "    ❌ Error: Cannot read $file"
        return 1
    fi
    
    # Create a temporary file to store the processed content
    if ! cp "$file" "$temp_file"; then
        echo "    ❌ Error: Cannot create temporary file"
        return 1
    fi
    
    # STEP 1: Replace generated placeholders first (passwords, keys, etc.)
    # These need to be processed before dynamic defaults to avoid conflicts
    
    # Replace EXIST_24_CHAR_PASSWORD with generated password
    if grep -q "EXIST_24_CHAR_PASSWORD" "$temp_file"; then
        local password=$(generate_24_char_password)
        if [ -n "$password" ]; then
            # Escape special characters for sed
            local escaped_password=$(printf '%s\n' "$password" | sed 's/[[\.*^$()+?{|]/\\&/g')
            sed -i "s/EXIST_24_CHAR_PASSWORD/$escaped_password/g" "$temp_file"
            echo "    ✅ Replaced EXIST_24_CHAR_PASSWORD"
            ((changes_made++))
        else
            echo "    ❌ Error: Failed to generate password"
        fi
    fi
    
    # Replace EXIST_32_CHAR_HEX_KEY with generated 32-char hex key
    if grep -q "EXIST_32_CHAR_HEX_KEY" "$temp_file"; then
        local hex_key_32=$(generate_32_char_hex)
        if [ -n "$hex_key_32" ]; then
            sed -i "s/EXIST_32_CHAR_HEX_KEY/$hex_key_32/g" "$temp_file"
            echo "    ✅ Replaced EXIST_32_CHAR_HEX_KEY"
            ((changes_made++))
        else
            echo "    ❌ Error: Failed to generate 32-char hex key"
        fi
    fi
    
    # Replace EXIST_64_CHAR_HEX_KEY with generated 64-char hex key
    if grep -q "EXIST_64_CHAR_HEX_KEY" "$temp_file"; then
        local hex_key_64=$(generate_64_char_hex)
        if [ -n "$hex_key_64" ]; then
            sed -i "s/EXIST_64_CHAR_HEX_KEY/$hex_key_64/g" "$temp_file"
            echo "    ✅ Replaced EXIST_64_CHAR_HEX_KEY"
            ((changes_made++))
        else
            echo "    ❌ Error: Failed to generate 64-char hex key"
        fi
    fi
    
    # STEP 2: Dynamic EXIST_DEFAULT_* variable replacement
    # Only process files other than the root .env to avoid circular references
    local current_file_path=$(realpath "$file" 2>/dev/null || echo "$file")
    local root_env_path=$(realpath ".env" 2>/dev/null || echo "./.env")
    if [ "$use_dynamic_defaults" = true ] && [ "$current_file_path" != "$root_env_path" ]; then
        echo "    🔍 Processing dynamic EXIST_DEFAULT_* variables..."
        local defaults=()
        mapfile -t defaults < <(get_exist_default_variables ".env")
        
        for default_entry in "${defaults[@]}"; do
            if [ -n "$default_entry" ]; then
                local var_name="${default_entry%%:*}"
                local var_value="${default_entry#*:}"
                
                # Only process if there's a value and it doesn't contain EXIST_ placeholders
                if [ -n "$var_value" ] && ! [[ "$var_value" =~ EXIST_ ]]; then
                    # Check if this variable exists in the file
                    if grep -q "=$var_name" "$temp_file" || grep -q "=$var_name$" "$temp_file"; then
                        # Escape special characters for sed
                        local escaped_value=$(printf '%s\n' "$var_value" | sed 's/[[\.*^$()+?{|/]/\\&/g')
                        # Replace the variable when it appears as a value (after =)
                        sed -i "s/=$var_name$/=$escaped_value/g" "$temp_file"
                        sed -i "s/=$var_name\([^A-Z0-9_]\)/=$escaped_value\1/g" "$temp_file"
                        echo "    ✅ Replaced dynamic variable $var_name with '$var_value'"
                        ((changes_made++))
                    fi
                elif [ -n "$var_value" ] && [[ "$var_value" =~ EXIST_ ]]; then
                    echo "    ⚠️  Skipping $var_name (contains unresolved EXIST_ placeholder: $var_value)"
                fi
            fi
        done
    fi
    
    # If changes were made, replace the original file
    if [ $changes_made -gt 0 ]; then
        if mv "$temp_file" "$file"; then
            echo "    ✅ Successfully updated $file with $changes_made changes"
            return 0
        else
            echo "    ❌ Error: Failed to update $file"
            rm -f "$temp_file"
            return 1
        fi
    else
        echo "    ℹ️  No placeholder variables found in $file"
        rm -f "$temp_file"
        return 0
    fi
}

# Function to process a single example file and create its counterpart
process_example_file() {
    local example_file="$1"
    local is_root_level="$2"  # true/false
    local target_file="${example_file%.example}"
    local success=true
    
    echo "📄 Processing: $example_file"
    
    # Check if source file exists and is readable
    if [ ! -r "$example_file" ]; then
        echo "  ❌ Error: Cannot read $example_file"
        return 1
    fi
    
    # CRITICAL: Never modify existing files - only create new ones
    if [ -f "$target_file" ]; then
        echo "  ℹ️  $target_file already exists - skipping to avoid overwriting"
        echo "  💡 If you want to regenerate $target_file, delete it first and re-run"
        return 0
    fi
    
    # Step 1: Create the target file by copying the example file
    # Create the directory for the target file if it doesn't exist
    local target_dir="$(dirname "$target_file")"
    if [ ! -d "$target_dir" ]; then
        if ! mkdir -p "$target_dir"; then
            echo "  ❌ Error: Cannot create directory $target_dir"
            return 1
        fi
    fi
    
    # Copy the .example file to create the target file
    if cp "$example_file" "$target_file"; then
        echo "  ✅ Created $target_file from $example_file"
    else
        echo "  ❌ Error: Failed to create $target_file"
        return 1
    fi
    
    # Step 2: For root-level files, process CLI placeholders first
    if [ "$is_root_level" = true ]; then
        echo "  🔧 Processing root-level file with CLI prompts..."
        
        # Process CLI placeholders first
        if has_exist_cli_placeholders "$target_file"; then
            echo "  � Found EXIST_CLI placeholders, running interactive replacer..."
            if ! process_file_interactive "$target_file"; then
                echo "  ❌ Error: Failed to process EXIST_CLI placeholders"
                success=false
            fi
        fi
        
        # Then process other placeholders (passwords, keys, etc.)
        if has_exist_placeholders "$target_file"; then
            echo "  🔧 Found EXIST_* placeholders, processing automatically..."
            # For root .env file, disable dynamic defaults to avoid circular references
            if ! process_file_placeholders "$target_file" false; then
                echo "  ❌ Error: Failed to process EXIST_* placeholders"
                success=false
            fi
        fi
        
        # Finally, if this is the root .env file, source it to load environment variables
        if [ "$success" = true ] && [[ "$target_file" == *.env ]] && ([ "$target_file" = ".env" ] || [ "$target_file" = "./.env" ]); then
            echo "  🌍 Loading environment variables from root-level .env file..."
            if set -a && source "$target_file" && set +a; then
                echo "  ✅ Successfully sourced $target_file"
            else
                echo "  ❌ Error: Failed to source $target_file"
                success=false
            fi
        fi
    else
        # Step 3: For non-root files, process CLI placeholders if they exist
        if has_exist_cli_placeholders "$target_file"; then
            echo "  💬 Found EXIST_CLI placeholders, running interactive replacer..."
            if ! process_file_interactive "$target_file"; then
                echo "  ❌ Error: Failed to process EXIST_CLI placeholders"
                success=false
            fi
        fi
        
        # Step 4: Process other EXIST_* placeholders with dynamic defaults enabled
        if has_exist_placeholders "$target_file"; then
            echo "  🔧 Found EXIST_* placeholders, processing with dynamic defaults..."
            if ! process_file_placeholders "$target_file" true; then
                echo "  ❌ Error: Failed to process EXIST_* placeholders"
                success=false
            fi
        fi
    fi
    
    echo ""
    
    if [ "$success" = true ]; then
        return 0
    else
        return 1
    fi
}

# Main function to process all example files systematically
process_all_example_files() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    local file_pattern="${3:-*.example}"
    local root_first="${4:-true}"  # Process root-level files first by default
    
    local processed_count=0
    local success_count=0
    local error_count=0
    
    echo "🚀 Unified Example File Processor"
    echo "=================================="
    echo "Search directory: $search_dir"
    echo "Max depth: $max_depth"
    echo "File pattern: $file_pattern"
    echo "Process root first: $root_first"
    echo ""
    
    # Change to search directory for consistent relative path handling
    local original_dir="$(pwd)"
    cd "$search_dir" || {
        echo "❌ Error: Cannot change to directory: $search_dir"
        return 1
    }
    
    # Step 1: Process root-level files first if requested
    if [ "$root_first" = true ]; then
        echo "📋 Step 1: Processing root-level .example files..."
        local root_files=()
        mapfile -t root_files < <(find_example_files "." 0 "$file_pattern")
        
        if [ ${#root_files[@]} -gt 0 ]; then
            echo "Found ${#root_files[@]} root-level .example files"
            for file in "${root_files[@]}"; do
                ((processed_count++))
                if process_example_file "$file" true; then
                    ((success_count++))
                else
                    ((error_count++))
                fi
            done
        else
            echo "No root-level .example files found"
        fi
        echo ""
    fi
    
    # Step 2: Process non-root files
    echo "📋 Step 2: Processing service-level .example files..."
    local service_files=()
    mapfile -t service_files < <(find_example_files "." "$max_depth" "$file_pattern")
    
    # Filter out root-level files if we already processed them
    local filtered_files=()
    for file in "${service_files[@]}"; do
        # Check if this is a root-level file (no subdirectories)
        local relative_path="${file#./}"
        if [[ "$relative_path" != *"/"* ]]; then
            # This is a root-level file
            if [ "$root_first" != true ]; then
                # Include it only if we didn't process root files first
                filtered_files+=("$file")
            fi
            # Otherwise skip it since we already processed it
        else
            # This is a non-root file, always include it
            filtered_files+=("$file")
        fi
    done
    
    if [ ${#filtered_files[@]} -gt 0 ]; then
        echo "Found ${#filtered_files[@]} service-level .example files"
        for file in "${filtered_files[@]}"; do
            ((processed_count++))
            if process_example_file "$file" false; then
                ((success_count++))
            else
                ((error_count++))
            fi
        done
    else
        echo "No service-level .example files found"
    fi
    
    # Return to original directory
    cd "$original_dir" || {
        echo "⚠️  Warning: Could not return to original directory"
    }
    
    # Summary
    echo ""
    echo "📊 Processing Summary"
    echo "===================="
    echo "Total processed: $processed_count files"
    echo "Successful: $success_count files"
    echo "Errors: $error_count files"
    echo ""
    
    if [ $error_count -gt 0 ]; then
        echo "⚠️  Some files could not be processed completely. Check the output above for details."
        return 1
    elif [ $success_count -eq 0 ]; then
        echo "ℹ️  No files were processed."
        return 0
    else
        echo "🎉 All files processed successfully!"
        return 0
    fi
}

# Usage examples and main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "=== Unified Example File Processor Test ==="
    
    # Test 1: Process all .example files (default behavior)
    echo "Test 1: Processing all .example files with default settings..."
    process_all_example_files "." 2 "*.example" true
    
    echo ""
    echo "=== Additional Usage Examples ==="
    echo "# Process only .env.example files:"
    echo "process_all_example_files \".\" 2 \"*.env.example\" true"
    echo ""
    echo "# Process all .example files but don't prioritize root:"
    echo "process_all_example_files \".\" 2 \"*.example\" false"
    echo ""
    echo "# Process with deeper search:"
    echo "process_all_example_files \".\" 3 \"*.example\" true"
fi
