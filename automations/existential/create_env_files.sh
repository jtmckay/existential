#!/bin/bash

# Create .env files from .env.example files
# Finds all .env.example files and creates corresponding .env files
# Compatible with Windows (Git Bash/WSL), Mac, and Linux

# Get the directory where this script is located
CREATE_ENV_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the find_env_examples.sh script to get the find_env_examples function
if [ -f "$CREATE_ENV_SCRIPT_DIR/find_env_examples.sh" ]; then
    source "$CREATE_ENV_SCRIPT_DIR/find_env_examples.sh"
else
    echo "Error: find_env_examples.sh not found in $CREATE_ENV_SCRIPT_DIR"
    exit 1
fi

# Function to create .env files from .env.example files
create_env_generated_files() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"  # Default to depth 2 if not specified
    local created_count=0
    local skipped_count=0
    local error_count=0
    
    echo "Creating .env files from .env.example files in: $search_dir"
    echo "Search depth: $max_depth"
    echo "=================================================================="
    
    # Get all .env.example files with specified depth
    mapfile -t env_example_files < <(find_env_examples "$search_dir" "$max_depth")
    
    if [ ${#env_example_files[@]} -eq 0 ]; then
        echo "No .env.example files found in $search_dir"
        return 0
    fi
    
    echo "Found ${#env_example_files[@]} .env.example files:"
    echo ""
    
    # Process each .env.example file
    for env_example_file in "${env_example_files[@]}"; do
        # Generate the corresponding .env filename
        # Remove .example suffix and add .generated
        local env_generated_file="${env_example_file%.example}.generated"
        
        echo "Processing: $env_example_file"
        echo "  → Creating: $env_generated_file"
        
        # Check if source file exists and is readable
        if [ ! -r "$env_example_file" ]; then
            echo "  ❌ Error: Cannot read $env_example_file"
            ((error_count++))
            continue
        fi
        
        # Check if target file already exists
        if [ -f "$env_generated_file" ]; then
            echo "  ⚠️  Warning: $env_generated_file already exists, skipping"
            ((skipped_count++))
            continue
        fi
        
        # Create the directory for the target file if it doesn't exist
        local target_dir="$(dirname "$env_generated_file")"
        if [ ! -d "$target_dir" ]; then
            if ! mkdir -p "$target_dir"; then
                echo "  ❌ Error: Cannot create directory $target_dir"
                ((error_count++))
                continue
            fi
        fi
        
        # Copy the .env.example file to .env
        if cp "$env_example_file" "$env_generated_file"; then
            echo "  ✅ Successfully created $env_generated_file"
            ((created_count++))
        else
            echo "  ❌ Error: Failed to create $env_generated_file"
            ((error_count++))
        fi
        
        echo ""
    done
    
    # Summary
    echo "Summary:"
    echo "========="
    echo "Created: $created_count files"
    echo "Skipped: $skipped_count files (already exist)"
    echo "Errors:  $error_count files"
    echo ""
    
    if [ $error_count -gt 0 ]; then
        echo "⚠️  Some files could not be processed. Check permissions and disk space."
        return 1
    elif [ $created_count -eq 0 ]; then
        echo "ℹ️  No new files were created."
        return 0
    else
        echo "✅ Successfully created $created_count .env files!"
        return 0
    fi
}

# Function to list all .env files that would be created (dry run)
list_env_generated_files() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"  # Default to depth 2 if not specified
    
    echo "Listing .env files that would be created in: $search_dir"
    echo "Search depth: $max_depth"
    echo "================================================================"
    
    # Get all .env.example files with specified depth
    mapfile -t env_example_files < <(find_env_examples "$search_dir" "$max_depth")
    
    if [ ${#env_example_files[@]} -eq 0 ]; then
        echo "No .env.example files found in $search_dir"
        return 0
    fi
    
    echo "Found ${#env_example_files[@]} .env.example files:"
    echo ""
    
    # Show what would be created
    for i in "${!env_example_files[@]}"; do
        local env_example_file="${env_example_files[i]}"
        local env_generated_file="${env_example_file%.example}.generated"
        
        printf "%2d: %s\n" $((i+1)) "$env_example_file"
        printf "    → %s" "$env_generated_file"
        
        if [ -f "$env_generated_file" ]; then
            echo " (already exists)"
        else
            echo " (new file)"
        fi
    done
    
    echo ""
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Parse command line arguments
    search_dir="."
    depth=2
    mode="create"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|--list|-l)
                mode="list"
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
                echo "Create .env files from .env.example files"
                echo ""
                echo "OPTIONS:"
                echo "  --dry-run, --list, -l    Show what files would be created (don't create them)"
                echo "  --depth, -d DEPTH        Search depth (0=current dir only, default=2)"
                echo "  --help, -h               Show this help message"
                echo ""
                echo "DIRECTORY:"
                echo "  Directory to search for .env.example files (default: current directory)"
                echo ""
                echo "Examples:"
                echo "  $0                       # Create .env files in current directory (depth 2)"
                echo "  $0 --depth 0             # Create .env files in current directory only"
                echo "  $0 --depth 1 /project   # Create files 1 level deep in /project"
                echo "  $0 --dry-run --depth 0   # Show what would be created in current dir only"
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
    if [ "$mode" = "list" ]; then
        list_env_generated_files "$search_dir" "$depth"
    else
        create_env_generated_files "$search_dir" "$depth"
    fi
fi
