#!/bin/bash

# Find Docker Compose Files Script
# Recursively finds all docker-compose.yml files in a directory structure
# Excludes graveyard directory and provides configurable search depth
# Compatible with Windows (Git Bash/WSL), Mac, and Linux

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to find docker-compose.yml files
find_docker_compose_files() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    
    # Validate inputs
    if [ ! -d "$search_dir" ]; then
        echo "Error: Directory $search_dir does not exist" >&2
        return 1
    fi
    
    if ! [[ "$max_depth" =~ ^[0-9]+$ ]]; then
        echo "Error: max_depth must be a non-negative integer" >&2
        return 1
    fi
    
    local compose_files=()
    
    # Use find command if available and depth is reasonable
    if command -v find >/dev/null 2>&1 && [ "$max_depth" -le 10 ]; then
        if [ "$max_depth" -eq 0 ]; then
            # Search only in current directory
            while IFS= read -r -d '' file; do
                compose_files+=("$file")
            done < <(find "$search_dir" -maxdepth 1 -type f -name "docker-compose.yml" -not -path "*/graveyard/*" -print0 2>/dev/null)
        else
            # Search with depth > 0, exclude current directory
            while IFS= read -r -d '' file; do
                compose_files+=("$file")
            done < <(find "$search_dir" -mindepth 2 -maxdepth $((max_depth + 1)) -type f -name "docker-compose.yml" -not -path "*/graveyard/*" -print0 2>/dev/null)
        fi
    else
        # Fallback to shell globbing for cross-platform compatibility
        if [ "$max_depth" -eq 0 ]; then
            # Only current directory
            for file in "$search_dir"/docker-compose.yml; do
                if [ -f "$file" ] && [[ "$file" != *"/graveyard/"* ]]; then
                    compose_files+=("$file")
                fi
            done
        elif [ "$max_depth" -eq 1 ]; then
            # 1 level deep only (exclude current directory)
            for file in "$search_dir"/*/docker-compose.yml; do
                if [ -f "$file" ] && [[ "$file" != *"/graveyard/"* ]]; then
                    compose_files+=("$file")
                fi
            done
        elif [ "$max_depth" -eq 2 ]; then
            # 1-2 levels deep (exclude current directory)
            for file in "$search_dir"/*/docker-compose.yml "$search_dir"/*/*/docker-compose.yml; do
                if [ -f "$file" ] && [[ "$file" != *"/graveyard/"* ]]; then
                    compose_files+=("$file")
                fi
            done
        else
            # For deeper levels, use a more comprehensive approach
            for file in "$search_dir"/**/**/docker-compose.yml; do
                if [ -f "$file" ] && [[ "$file" != *"/graveyard/"* ]]; then
                    # Calculate depth
                    local relative_path="${file#$search_dir/}"
                    local depth=$(echo "$relative_path" | tr -cd '/' | wc -c)
                    if [ "$depth" -le "$max_depth" ] && [ "$depth" -ge 1 ]; then
                        compose_files+=("$file")
                    fi
                fi
            done
        fi
    fi
    
    # Remove duplicates and sort
    if [ ${#compose_files[@]} -gt 0 ]; then
        printf '%s\n' "${compose_files[@]}" | sort -u
    fi
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

# Function to check if a path has a docker-compose.yml file
has_docker_compose() {
    local service_path="$1"
    local search_dir="${2:-.}"
    
    if [ -z "$service_path" ]; then
        return 1
    fi
    
    local compose_file="$search_dir/$service_path/docker-compose.yml"
    [ -f "$compose_file" ]
}

# Function to get docker-compose.yml content without version and top-level sections
get_compose_services_only() {
    local compose_file="$1"
    
    if [ ! -f "$compose_file" ]; then
        echo "Error: Docker compose file $compose_file not found" >&2
        return 1
    fi
    
    # Extract only the services section content (everything under services:)
    # Skip version, networks, volumes at the top level
    awk '
    /^services:/ { in_services = 1; next }
    /^[a-zA-Z]/ && in_services && !/^[[:space:]]/ { in_services = 0 }
    in_services { print }
    ' "$compose_file"
}

# Function to extract and convert volumes to local paths
convert_volumes_to_local_paths() {
    local service_dir="$1"
    local compose_content="$2"
    
    # Process volume mounts in services, converting named volumes to local paths
    echo "$compose_content" | awk -v service_dir="$service_dir" '
    /^[[:space:]]*volumes:$/ {
        in_volumes = 1
        print
        next
    }
    
    # If we hit a non-indented line that starts a new section, exit volumes section
    in_volumes && /^[[:space:]]*[a-zA-Z0-9_-]+:/ && !/^[[:space:]]*-/ && !/^[[:space:]]*[a-z_]+:/ {
        in_volumes = 0
    }
    
    # Handle long-form volume with "source:" 
    in_volumes && /^[[:space:]]*source:/ {
        # Extract the source path and convert relative paths
        if (match($0, /^([[:space:]]*)source:[[:space:]]*(.*)$/, parts)) {
            source_path = parts[2]
            # If it starts with ./ then convert to service-relative path
            if (substr(source_path, 1, 2) == "./") {
                source_path = "./" service_dir "/" substr(source_path, 3)
            }
            printf "%ssource: %s\n", parts[1], source_path
        } else {
            print
        }
        next
    }
    
    # Handle short-form volume mounts (skip long-form entries)
    in_volumes && /^[[:space:]]*-[[:space:]]*[^:]*:[^:]*/ && !/^[[:space:]]*-[[:space:]]*type:/ {
        line = $0
        
        # Extract volume mount (source:target or source:target:options)
        if (match(line, /^([[:space:]]*-[[:space:]]*)([^:]+):(.*)$/, parts)) {
            source_path = parts[2]
            rest_of_mount = parts[3]
            
            # Skip malformed entries (like single letters from NFS options)
            if (length(source_path) <= 2 && source_path !~ /^\./) {
                print line
                next
            }
            
            # Convert relative paths and named volumes to local paths
            if (substr(source_path, 1, 1) == ".") {
                # Already a relative path, make it relative to service dir
                if (substr(source_path, 1, 2) == "./") {
                    source_path = "./" service_dir "/" substr(source_path, 3)
                } else {
                    source_path = "./" service_dir "/" source_path
                }
            } else if (source_path !~ /^\//) {
                # Named volume, convert to local directory
                source_path = "./" service_dir "/" source_path
            }
            # Absolute paths remain unchanged
            
            printf "%s%s:%s\n", parts[1], source_path, rest_of_mount
        } else {
            print line
        }
        next
    }
    
    # Print all other lines as-is (including long-form volume entries)
    { print }
    '
}

# Function to add env_file reference and profiles to services
add_env_file_and_profiles_to_services() {
    local service_dir="$1"
    local services_content="$2"
    
    # Extract category and service name from service_dir
    # e.g., "ai/libreChat" -> category="ai", service="librechat"
    local category=$(echo "$service_dir" | cut -d'/' -f1)
    local service_name=$(echo "$service_dir" | cut -d'/' -f2 | tr '[:upper:]' '[:lower:]')
    
    # First convert volumes to local paths
    local content_with_local_volumes
    content_with_local_volumes=$(convert_volumes_to_local_paths "$service_dir" "$services_content")
    
    # Process each service to remove existing env_file and add new env_file + profiles
    echo "$content_with_local_volumes" | awk -v service_dir="$service_dir" -v category="$category" -v service_name="$service_name" '
    BEGIN {
        current_service = 0
        in_env_file = 0
        pending_service = ""
    }
    
    /^  [a-zA-Z0-9_-]*:$/ {
        # If we were in a previous service, close it out
        if (current_service) {
            print "    env_file:"
            print "      - " service_dir "/.env"
            print "    profiles:"
            print "      - all"
            print "      - " category
            print "      - " service_name
        }
        
        # Start new service
        current_service = 1
        in_env_file = 0
        print $0
        next
    }
    
    # Skip existing env_file sections entirely
    current_service && /^[[:space:]]*env_file:/ {
        in_env_file = 1
        next  # Skip the env_file: line
    }
    
    # Skip env_file entries (lines that start with - under env_file)
    current_service && in_env_file && /^[[:space:]]*-/ {
        next  # Skip env_file entry lines
    }
    
    # When we hit a non-env_file line after being in env_file section
    current_service && in_env_file && !/^[[:space:]]*-/ && !/^[[:space:]]*env_file:/ {
        in_env_file = 0
        # Fall through to process this line normally
    }
    
    # Print all other lines (except when we are skipping env_file)
    !in_env_file { print }
    
    # Handle end of file - add env_file and profiles to last service
    END {
        if (current_service) {
            print "    env_file:"
            print "      - " service_dir "/.env"
            print "    profiles:"
            print "      - all"
            print "      - " category
            print "      - " service_name
        }
    }
    '
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Parse command line arguments
    search_dir="."
    depth=2
    action="list"
    
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
            --services|-s)
                action="services"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS] [DIRECTORY]"
                echo ""
                echo "Find docker-compose.yml files recursively with configurable depth"
                echo ""
                echo "OPTIONS:"
                echo "  --depth, -d DEPTH        Search depth (default=2)"
                echo "  --services, -s           Return service paths instead of file paths"
                echo "  --help, -h               Show this help message"
                echo ""
                echo "ARGUMENTS:"
                echo "  DIRECTORY                Directory to search (default: current directory)"
                echo ""
                echo "DEPTH BEHAVIOR:"
                echo "  0: Current directory only"
                echo "  1: 1 level deep only (excludes current directory)"
                echo "  2: 1-2 levels deep (excludes current directory)"
                echo "  3+: 1-3+ levels deep (excludes current directory)"
                echo ""
                echo "Examples:"
                echo "  $0                       # Find all docker-compose.yml files (depth 2)"
                echo "  $0 --depth 0             # Find docker-compose.yml in current directory only"
                echo "  $0 --services            # Return service directory paths"
                echo "  $0 --depth 1 services/   # Find compose files 1 level deep in services/"
                echo ""
                echo "Output:"
                echo "  Default: List of docker-compose.yml file paths"
                echo "  --services: List of service directory paths"
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
    
    # Execute based on action
    case "$action" in
        "services")
            get_docker_compose_service_paths "$search_dir" "$depth"
            ;;
        *)
            find_docker_compose_files "$search_dir" "$depth"
            ;;
    esac
fi
