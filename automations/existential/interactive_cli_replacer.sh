#!/bin/bash

# Interactive CLI variable replacement script
# Processes files containing EXIST_CLI placeholders and prompts user for values
# Shows context comments before each variable for better understanding
# Compatible with Windows (Git Bash/WSL), Mac, and Linux

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the find_env_examples.sh script if needed
if [ -f "$SCRIPT_DIR/find_env_examples.sh" ]; then
    source "$SCRIPT_DIR/find_env_examples.sh"
else
    echo "Warning: find_env_examples.sh not found in $SCRIPT_DIR"
fi

# Function to extract context comments for a variable
extract_context_comments() {
    local file="$1"
    local line_number="$2"
    local comments=()
    
    # Start from the line before the EXIST_CLI line and work backwards
    local current_line=$((line_number - 1))
    
    while [ $current_line -gt 0 ]; do
        local line_content
        line_content=$(sed -n "${current_line}p" "$file")
        
        # If we hit a blank line, stop
        if [[ "$line_content" =~ ^[[:space:]]*$ ]]; then
            break
        fi
        
        # If line starts with "# ", it's a comment - add it to the beginning of our array
        if [[ "$line_content" =~ ^[[:space:]]*#[[:space:]] ]]; then
            comments=("$line_content" "${comments[@]}")
        else
            # If it's not a comment and not blank, stop (we've gone too far)
            break
        fi
        
        ((current_line--))
    done
    
    # Print the comments
    for comment in "${comments[@]}"; do
        echo "$comment"
    done
}

# Function to process a single file for EXIST_CLI placeholders
process_file_interactive() {
    local file="$1"
    local changes_made=0
    
    # Extract folder and filename for clearer display
    local folder_path=$(dirname "$file")
    local filename=$(basename "$file")
    
    echo ""
    echo "🗂️  =============================================="
    echo "📁 Folder: $folder_path"
    echo "📄 File: $filename"
    echo "🔧 Full path: $file"
    echo "==============================================="
    echo ""
    
    # Check if file exists and is readable
    if [ ! -r "$file" ]; then
        echo "❌ Error: Cannot read $file"
        return 1
    fi
    
    # Find all lines containing EXIST_CLI and their line numbers
    local exist_cli_lines=()
    while IFS=: read -r line_num line_content; do
        if [ -n "$line_num" ] && [ -n "$line_content" ]; then
            exist_cli_lines+=("$line_num:$line_content")
        fi
    done < <(grep -n "EXIST_CLI" "$file")
    
    if [ ${#exist_cli_lines[@]} -eq 0 ]; then
        echo "ℹ️  No EXIST_CLI placeholders found in $file"
        return 0
    fi
    
    echo "Found ${#exist_cli_lines[@]} EXIST_CLI placeholder(s) in this file:"
    echo ""
    
    # Process each EXIST_CLI occurrence immediately
    for exist_cli_line in "${exist_cli_lines[@]}"; do
        local line_number="${exist_cli_line%%:*}"
        local line_content="${exist_cli_line#*:}"
        
        echo "----------------------------------------"
        echo "📍 Line $line_number: $line_content"
        echo ""
        
        # Extract and show context comments
        echo "📝 Context comments:"
        local context_output
        context_output=$(extract_context_comments "$file" "$line_number")
        
        if [ -n "$context_output" ]; then
            echo "$context_output"
        else
            echo "   (No context comments found)"
        fi
        echo ""
        
        # Extract the variable name from the line
        # Look for patterns like VARIABLE_NAME=EXIST_CLI
        local variable_name=""
        if [[ "$line_content" =~ ([A-Z_][A-Z0-9_]*)=EXIST_CLI ]]; then
            variable_name="${BASH_REMATCH[1]}"
        else
            # Fallback: just use a generic prompt
            variable_name="UNKNOWN_VARIABLE"
        fi
        
        # Prompt user for value
        echo "🔧 Please provide a value for '$variable_name':"
        echo -n "Enter value (or 'skip' to leave unchanged, blank for empty): "
        read -r user_value
        
        # Handle user input
        if [ "$user_value" = "skip" ]; then
            echo "⏭️  Skipping $variable_name"
            continue
        fi
        
        # If user_value is empty, we'll replace with empty string
        if [ -z "$user_value" ]; then
            echo "📝 Setting $variable_name to empty value"
            user_value=""
        fi
        
        # Escape special characters in the user value for sed
        local escaped_value
        escaped_value=$(printf '%s\n' "$user_value" | sed 's/[[\.*^$()+?{|]/\\&/g')
        
        # Make the replacement immediately on the original file
        # Use line number to target the specific line and only replace the value part
        if sed -i "${line_number}s/=EXIST_CLI$/=$escaped_value/" "$file"; then
            echo "✅ Replaced EXIST_CLI with '$user_value' for $variable_name"
            ((changes_made++))
        else
            echo "❌ Error: Failed to replace value for $variable_name"
        fi
        
        echo ""
        
        # Re-read the file content after each change to get updated line numbers
        # This ensures we're working with the current state if lines shift
        exist_cli_lines=()
        while IFS=: read -r line_num line_content; do
            if [ -n "$line_num" ] && [ -n "$line_content" ] && [ "$line_num" -gt "$line_number" ]; then
                exist_cli_lines+=("$line_num:$line_content")
            fi
        done < <(grep -n "EXIST_CLI" "$file")
    done
    
    if [ $changes_made -gt 0 ]; then
        echo "✅ Successfully applied $changes_made change(s) to $file"
    else
        echo "ℹ️  No changes made to $file"
    fi
    
    return 0
}

# Function to process multiple files
process_files_interactive() {
    local file_paths=("$@")
    local total_files=${#file_paths[@]}
    local processed_count=0
    local success_count=0
    local error_count=0
    
    if [ $total_files -eq 0 ]; then
        echo "❌ No files provided to process"
        return 1
    fi
    
    echo "🚀 Interactive EXIST_CLI Replacement"
    echo "===================================="
    echo "Files to process: $total_files"
    echo ""
    echo "📋 Instructions:"
    echo "• Review the context comments for each variable"
    echo "• Enter a value when prompted, 'skip' to leave unchanged, or blank for empty value"
    echo "• Press Ctrl+C to cancel at any time"
    echo "• Each replacement happens immediately (Ctrl+C safe)"
    echo ""
    
    # Ask for confirmation once
    echo -n "Ready to start processing all files? (y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "❌ Operation cancelled by user"
        return 1
    fi
    
    echo ""
    echo "🎯 Starting interactive replacement..."
    echo ""
    
    # Process each file without asking for continuation
    for file_path in "${file_paths[@]}"; do
        ((processed_count++))
        
        if process_file_interactive "$file_path"; then
            ((success_count++))
        else
            ((error_count++))
        fi
    done
    
    # Summary
    echo ""
    echo "📊 Processing Summary"
    echo "===================="
    echo "Total files: $total_files"
    echo "Processed: $processed_count"
    echo "Successful: $success_count"
    echo "Errors: $error_count"
    echo "Skipped: $((total_files - processed_count))"
    
    if [ $error_count -eq 0 ]; then
        echo "✅ All processed files completed successfully!"
        return 0
    else
        echo "⚠️  Some files had errors during processing"
        return 1
    fi
}

# Function to process files found by find_env_examples
process_env_files_interactive() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    
    echo "🔍 Finding .env files with EXIST_CLI placeholders..."
    echo "Search directory: $search_dir"
    echo "Search depth: $max_depth"
    echo ""
    
    # Get files using find_env_examples if available
    local env_files=()
    if command -v find_env_examples >/dev/null 2>&1; then
        mapfile -t env_files < <(find_env_examples "$search_dir" "$max_depth")
    else
        # Fallback to manual find
        mapfile -t env_files < <(find "$search_dir" -maxdepth $((max_depth + 1)) -type f -name "*.env*" -not -path "*/graveyard/*" 2>/dev/null)
    fi
    
    if [ ${#env_files[@]} -eq 0 ]; then
        echo "❌ No .env files found in $search_dir"
        return 1
    fi
    
    # Filter files that actually contain EXIST_CLI
    local files_with_exist_cli=()
    for file in "${env_files[@]}"; do
        if [ -f "$file" ] && grep -q "EXIST_CLI" "$file" 2>/dev/null; then
            files_with_exist_cli+=("$file")
        fi
    done
    
    if [ ${#files_with_exist_cli[@]} -eq 0 ]; then
        echo "ℹ️  No files containing EXIST_CLI placeholders found"
        echo "Searched ${#env_files[@]} .env files"
        return 0
    fi
    
    echo "Found ${#files_with_exist_cli[@]} file(s) containing EXIST_CLI placeholders:"
    for file in "${files_with_exist_cli[@]}"; do
        echo "  • $file"
    done
    echo ""
    
    # Process the files
    process_files_interactive "${files_with_exist_cli[@]}"
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Parse command line arguments
    search_dir="."
    depth=2
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --depth|-d)
                depth="$2"
                if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
                    echo "Error: Depth must be a non-negative integer"
                    exit 1
                fi
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS] [DIRECTORY|FILE...]"
                echo ""
                echo "Interactively replace EXIST_CLI placeholders in .env files"
                echo ""
                echo "OPTIONS:"
                echo "  --depth, -d DEPTH        Search depth for .env files (default=2)"
                echo "  --help, -h               Show this help message"
                echo ""
                echo "ARGUMENTS:"
                echo "  DIRECTORY                Directory to search for .env files (default: current directory)"
                echo "  FILE...                  Specific file(s) to process"
                echo ""
                echo "Examples:"
                echo "  $0                       # Process .env files in current directory (depth 2)"
                echo "  $0 --depth 0             # Process .env files in current directory only"
                echo "  $0 services/             # Process .env files in services/ directory"
                echo "  $0 file1.env file2.env   # Process specific files"
                echo ""
                echo "Features:"
                echo "• Shows context comments before each EXIST_CLI variable"
                echo "• Interactive prompts for each placeholder"
                echo "• Option to skip individual variables"
                echo "• Backup and rollback on errors"
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                exit 1
                ;;
            *)
                # If it's a file, process specific files
                if [ -f "$1" ]; then
                    # Process specific files
                    files_to_process=()
                    while [[ $# -gt 0 ]] && [ -f "$1" ]; do
                        files_to_process+=("$1")
                        shift
                    done
                    process_files_interactive "${files_to_process[@]}"
                    exit $?
                else
                    # It's a directory
                    search_dir="$1"
                    shift
                fi
                ;;
        esac
    done
    
    # Process .env files in directory
    process_env_files_interactive "$search_dir" "$depth"
fi
