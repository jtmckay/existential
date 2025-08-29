#!/bin/bash

# Find all .env.example files recursively using basic bash operations
# Compatible with Windows (Git Bash/WSL), Mac, and Linux
# Excludes files in the 'graveyard' directory

# Simple function to find .env.example files with depth control
find_env_examples() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"  # Default to depth 2 if not specified
    local files=()
    
    # Validate depth parameter
    if ! [[ "$max_depth" =~ ^[0-9]+$ ]]; then
        echo "Error: Depth must be a non-negative integer" >&2
        return 1
    fi
    
    # Use find with basic options - works on all platforms
    if command -v find >/dev/null 2>&1; then
        # Primary method: use find command, excluding graveyard directory
        if [ "$max_depth" -eq 0 ]; then
            # Depth 0: only search in the current directory (no subdirectories)
            while IFS= read -r file; do
                files+=("$file")
            done < <(find "$search_dir" -maxdepth 1 -type f -name "*.env.example" -not -path "*/graveyard/*" 2>/dev/null)
        else
            # Depth > 0: search subdirectories only (exclude current directory)
            while IFS= read -r file; do
                files+=("$file")
            done < <(find "$search_dir" -mindepth 2 -maxdepth $((max_depth + 1)) -type f -name "*.env.example" -not -path "*/graveyard/*" 2>/dev/null)
        fi
    else
        # Fallback for systems without find (rare but possible)
        # Use shell globbing - less efficient but more portable
        shopt -s globstar 2>/dev/null || true
        
        if [ "$max_depth" -eq 0 ]; then
            # Depth 0: only current directory
            for file in "$search_dir"/*.env.example; do
                if [ -f "$file" ] && [[ "$file" != */graveyard/* ]]; then
                    files+=("$file")
                fi
            done
        elif [ "$max_depth" -eq 1 ]; then
            # Depth 1: one level down only (skip current directory)
            for file in "$search_dir"/*/*.env.example; do
                if [ -f "$file" ] && [[ "$file" != */graveyard/* ]]; then
                    files+=("$file")
                fi
            done
        elif [ "$max_depth" -eq 2 ]; then
            # Depth 2: one and two levels down (skip current directory)
            for file in "$search_dir"/*/*.env.example "$search_dir"/*/*/*.env.example; do
                if [ -f "$file" ] && [[ "$file" != */graveyard/* ]]; then
                    files+=("$file")
                fi
            done
        else
            # Depth > 2: use full globstar (skip current directory)
            for file in "$search_dir"/**/*.env.example; do
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

# Usage examples:
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "=== Finding .env.example files ==="
    
    # Test different depth levels
    echo "Default depth (2):"
    mapfile -t env_files_default < <(find_env_examples ".")
    echo "Found ${#env_files_default[@]} files"
    
    echo ""
    echo "Depth 0 (current directory only):"
    mapfile -t env_files_depth0 < <(find_env_examples "." 0)
    echo "Found ${#env_files_depth0[@]} files:"
    for file in "${env_files_depth0[@]}"; do
        echo "  $file"
    done
    
    echo ""
    echo "Depth 1 (1 level deep only, excludes current dir):"
    mapfile -t env_files_depth1 < <(find_env_examples "." 1)
    # Filter out empty elements
    filtered_depth1=()
    for file in "${env_files_depth1[@]}"; do
        if [ -n "$file" ]; then
            filtered_depth1+=("$file")
        fi
    done
    echo "Found ${#filtered_depth1[@]} files"
    for file in "${filtered_depth1[@]}"; do
        echo "  $file"
    done
    
    echo ""
    echo "Depth 2 (1-2 levels deep, excludes current dir):"
    mapfile -t env_files_depth2 < <(find_env_examples "." 2)
    echo "Found ${#env_files_depth2[@]} files"
    
    echo ""
    echo "=== All files at default depth ==="
    for file in "${env_files_default[@]}"; do
        echo "  $file"
    done
fi
