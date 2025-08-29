#!/bin/bash

# Service Enablement Helper
# Provides functions to check which services are enabled in the environment
# Compatible with Windows (Git Bash/WSL), Mac, and Linux

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the unified example processor for docker-compose finding functionality
if [ -f "$SCRIPT_DIR/unified_example_processor.sh" ]; then
    source "$SCRIPT_DIR/unified_example_processor.sh"
else
    echo "Error: unified_example_processor.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Function to get all available services from docker-compose files
get_all_available_services() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    
    # Use the find_docker_compose script to get service paths
    get_docker_compose_service_paths "$search_dir" "$max_depth"
}

# Function to check if a service is enabled
is_service_enabled() {
    local service_path="$1"
    
    if [ -z "$service_path" ]; then
        echo "Error: Service path is required"
        return 1
    fi
    
    # Convert service path to environment variable name
    # Example: ai/librechat -> EXIST_ENABLE_AI_LIBRECHAT
    local env_var_name
    env_var_name="EXIST_ENABLE_$(echo "$service_path" | tr '[:lower:]/' '[:upper:]_')"
    
    # Get the value of the environment variable
    local env_var_value
    env_var_value=$(eval echo "\$${env_var_name}")
    
    # Check if the value is "true" (case insensitive)
    if [[ "${env_var_value,,}" == "true" ]]; then
        return 0  # Service is enabled
    else
        return 1  # Service is disabled or not set
    fi
}

# Function to get all enabled services
get_enabled_services() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    local enabled_services=()
    
    # Get all available services dynamically
    local all_services=()
    mapfile -t all_services < <(get_all_available_services "$search_dir" "$max_depth")
    
    # Check each service
    for service in "${all_services[@]}"; do
        if is_service_enabled "$service"; then
            enabled_services+=("$service")
        fi
    done
    
    # Print enabled services
    printf '%s\n' "${enabled_services[@]}"
}

# Function to get all disabled services
get_disabled_services() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    local disabled_services=()
    
    # Get all available services dynamically
    local all_services=()
    mapfile -t all_services < <(get_all_available_services "$search_dir" "$max_depth")
    
    # Check each service
    for service in "${all_services[@]}"; do
        if ! is_service_enabled "$service"; then
            disabled_services+=("$service")
        fi
    done
    
    # Print disabled services
    printf '%s\n' "${disabled_services[@]}"
}

# Function to get available categories (profiles)
get_available_categories() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    
    # Get all service paths and extract unique categories
    local all_services=()
    mapfile -t all_services < <(get_all_available_services "$search_dir" "$max_depth")
    
    local categories=()
    for service in "${all_services[@]}"; do
        local category=$(echo "$service" | cut -d'/' -f1)
        categories+=("$category")
    done
    
    # Remove duplicates and sort
    printf '%s\n' "${categories[@]}" | sort -u
}

# Function to get available service names (for individual profiles)
get_available_service_names() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    
    # Get all service paths and extract service names
    local all_services=()
    mapfile -t all_services < <(get_all_available_services "$search_dir" "$max_depth")
    
    local service_names=()
    for service in "${all_services[@]}"; do
        local service_name=$(echo "$service" | cut -d'/' -f2 | tr '[:upper:]' '[:lower:]')
        service_names+=("$service_name")
    done
    
    # Remove duplicates and sort
    printf '%s\n' "${service_names[@]}" | sort -u
}

# Function to list all available services
list_all_services() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    
    get_all_available_services "$search_dir" "$max_depth"
}

# Function to show service status
show_service_status() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    
    echo "Service Enablement Status"
    echo "========================"
    echo ""
    
    # Get all available services dynamically
    local all_services=()
    mapfile -t all_services < <(get_all_available_services "$search_dir" "$max_depth")
    
    for service in "${all_services[@]}"; do
        local env_var_name="EXIST_ENABLE_$(echo "$service" | tr '[:lower:]/' '[:upper:]_')"
        local env_var_value=$(eval echo "\$${env_var_name}")
        local status="❌ Disabled"
        
        if [[ "${env_var_value,,}" == "true" ]]; then
            status="✅ Enabled"
        fi
        
        printf "  %-25s %s\n" "$service" "$status"
    done
    
    echo ""
    local enabled_count=$(get_enabled_services "$search_dir" "$max_depth" | wc -l)
    local total_count=${#all_services[@]}
    echo "Summary: $enabled_count of $total_count services enabled"
}

# Function to extract only the services section from a docker-compose.yml file
get_compose_services_only() {
    local compose_file="$1"
    
    if [ ! -f "$compose_file" ]; then
        return 1
    fi
    
    # Extract the services section using awk
    awk '
    /^services:/ { 
        in_services = 1
        next
    }
    /^[a-zA-Z]/ && in_services && !/^[[:space:]]/ { 
        in_services = 0 
    }
    in_services {
        print $0
    }' "$compose_file"
}

# Function to update relative paths in docker-compose content
update_relative_paths() {
    local service_path="$1"
    local services_content="$2"
    
    if [ -z "$services_content" ]; then
        return 0
    fi
    
    # Process the services content line by line and update relative volume paths and env_file paths
    echo "$services_content" | awk -v service_path="$service_path" '
    BEGIN {
        in_volumes = 0
        in_env_file = 0
    }
    
    # env_file section start
    /^[[:space:]]*env_file:[[:space:]]*$/ {
        in_env_file = 1
        print $0
        next
    }
    
    # env_file line with relative path (starts with ./ or just . or filename without path)
    in_env_file && /^[[:space:]]*-[[:space:]]*[^\/]/ {
        # Extract the env file path
        line = $0
        # Remove leading whitespace and dash
        gsub(/^[[:space:]]*-[[:space:]]*/, "", line)
        
        # If line doesn'\''t start with /, it'\''s relative, so prefix with service path
        if (substr(line, 1, 1) != "/") {
            print "      - " service_path "/" line
        } else {
            # Absolute path, keep as is
            print "      - " line
        }
        next
    }
    
    # End of env_file section when we hit another service-level key
    in_env_file && /^[[:space:]]{2,}[a-zA-Z]/ && !/^[[:space:]]*-/ {
        in_env_file = 0
        print $0
        next
    }
    
    # Any other line in env_file section (absolute paths, etc.)
    in_env_file {
        print $0
        next
    }
    
    # Volumes section start
    /^[[:space:]]*volumes:[[:space:]]*$/ {
        in_volumes = 1
        print $0
        next
    }
    
    # Volume line with relative path (starts with ./ or just .)
    in_volumes && /^[[:space:]]*-[[:space:]]*\./ {
        # Extract the volume definition
        line = $0
        # Remove leading whitespace and dash
        gsub(/^[[:space:]]*-[[:space:]]*/, "", line)
        
        # Split on colon to get source and target
        colon_pos = index(line, ":")
        if (colon_pos > 0) {
            source = substr(line, 1, colon_pos - 1)
            target = substr(line, colon_pos)
            
            # If source starts with ./ remove it, if it starts with . remove it
            if (substr(source, 1, 2) == "./") {
                source = substr(source, 3)
            } else if (substr(source, 1, 1) == ".") {
                source = substr(source, 2)
                if (substr(source, 1, 1) == "/") {
                    source = substr(source, 2)
                }
            }
            
            # Clean up any remaining leading slashes or dots
            while (substr(source, 1, 1) == "/" || substr(source, 1, 1) == ".") {
                if (substr(source, 1, 2) == "./") {
                    source = substr(source, 3)
                } else {
                    source = substr(source, 2)
                }
            }
            
            # Reconstruct with service path
            new_source = "./" service_path "/" source
            print "      - " new_source target
        } else {
            # No colon found, just prefix the path
            if (substr(line, 1, 2) == "./") {
                line = substr(line, 3)
            } else if (substr(line, 1, 1) == ".") {
                line = substr(line, 2)
                if (substr(line, 1, 1) == "/") {
                    line = substr(line, 2)
                }
            }
            
            # Clean up any remaining leading slashes or dots
            while (substr(line, 1, 1) == "/" || substr(line, 1, 1) == ".") {
                if (substr(line, 1, 2) == "./") {
                    line = substr(line, 3)
                } else {
                    line = substr(line, 2)
                }
            }
            
            print "      - ./" service_path "/" line
        }
        next
    }
    
    # End of volumes section when we hit another service-level key
    in_volumes && /^[[:space:]]{2,}[a-zA-Z]/ && !/^[[:space:]]*-/ {
        in_volumes = 0
        print $0
        next
    }
    
    # Any other line in volumes section (named volumes, bind mounts with absolute paths, etc.)
    in_volumes {
        print $0
        next
    }
    
    # All other lines
    {
        print $0
    }
    '
}

# Function to resolve environment variables in docker-compose content
resolve_env_variables() {
    local content="$1"
    local service_path="$2"
    
    # Process content line by line to resolve ${VARIABLE} and ${VARIABLE:-default} patterns
    echo "$content" | while IFS= read -r line; do
        resolved_line="$line"
        
        # Find all ${...} patterns in the line
        while [[ "$resolved_line" =~ \$\{([^}]+)\} ]]; do
            local full_match="${BASH_REMATCH[0]}"
            local var_expr="${BASH_REMATCH[1]}"
            local var_name=""
            local default_value=""
            
            # Check if it has a default value (VARIABLE:-default format)
            if [[ "$var_expr" =~ ^([^:]+):-(.*)$ ]]; then
                var_name="${BASH_REMATCH[1]}"
                default_value="${BASH_REMATCH[2]}"
            else
                var_name="$var_expr"
                default_value=""
            fi
            
            # Get the actual value from environment
            local actual_value
            actual_value=$(eval echo "\$${var_name}")
            
            # Use default if variable is empty or unset
            if [ -z "$actual_value" ]; then
                actual_value="$default_value"
            fi
            
            # Replace the placeholder with the actual value
            resolved_line="${resolved_line//$full_match/$actual_value}"
        done
        
        echo "$resolved_line"
    done
}

# Function to generate merged docker-compose.yml based on enabled services
generate_compose_override() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    local output_file="${3:-docker-compose.generated.yml}"
    
    local enabled_services=()
    mapfile -t enabled_services < <(get_enabled_services "$search_dir" "$max_depth")
    
    echo "# Generated docker-compose.yml based on enabled services"
    echo "# This file is auto-generated from individual service docker-compose.yml files"
    echo "# Environment variables have been resolved to their actual values"
    echo "# Services enabled: ${#enabled_services[@]}"
    echo "# Generated on: $(date)"
    echo ""
    echo "services:"
    
    if [ ${#enabled_services[@]} -eq 0 ]; then
        echo "  # No services enabled"
        echo ""
        echo "networks:"
        echo "  exist:"
        echo "    driver: bridge"
        return 0
    fi
    
    local all_volumes=()
    local has_networks=false
    
    # Process each enabled service
    for service in "${enabled_services[@]}"; do
        local compose_file="$search_dir/$service/docker-compose.yml"
        local env_file="$search_dir/$service/.env"
        
        if [ ! -f "$compose_file" ]; then
            echo "  # Warning: docker-compose.yml not found for $service" >&2
            continue
        fi
        
        # Source the service-specific .env file if it exists
        if [ -f "$env_file" ]; then
            set -a  # Automatically export all variables
            source "$env_file"
            set +a  # Turn off automatic export
        fi
        
        echo ""
        echo "  # Services from $service"
        
        # Extract services section and add env_file references
        local services_content
        services_content=$(get_compose_services_only "$compose_file")
        
        if [ -n "$services_content" ]; then
            # Update relative paths for env_file and volumes
            local path_updated_content
            path_updated_content=$(update_relative_paths "$service" "$services_content")
            
            # Resolve environment variables in the content
            local resolved_services_content
            resolved_services_content=$(resolve_env_variables "$path_updated_content" "$service")
            
            echo "$resolved_services_content"
        else
            echo "  # No services found in $compose_file"
        fi
        
        # Extract volumes section - get complete volume definitions
        local volumes_section
        volumes_section=$(awk '
        /^volumes:/ { in_volumes = 1; next }
        /^[a-zA-Z]/ && in_volumes && !/^[[:space:]]/ { in_volumes = 0 }
        in_volumes { print $0 }' "$compose_file")
        
        if [ -n "$volumes_section" ]; then
            # Resolve variables in the volumes section content
            local resolved_volumes_section
            resolved_volumes_section=$(resolve_env_variables "$volumes_section" "$service")
            
            # Add to global volumes collection (we'll deduplicate later)
            all_volumes+=("$resolved_volumes_section")
        fi
        
        # Check if this compose file has networks
        if grep -q "^networks:" "$compose_file"; then
            has_networks=true
        fi
    done
    
    # Add volumes section if any volumes were found
    if [ ${#all_volumes[@]} -gt 0 ]; then
        echo ""
        echo "volumes:"
        
        # Create a temporary file to track declared volumes
        local temp_file=$(mktemp)
        
        # Process each volume section and output unique volume definitions
        for volume_section in "${all_volumes[@]}"; do
            if [ -n "$volume_section" ]; then
                echo "$volume_section" | while IFS= read -r line; do
                    # Check if this is a volume definition line (starts with 2 spaces and has a colon)
                    if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):[[:space:]]*(.*) ]]; then
                        local volume_name="${BASH_REMATCH[1]}"
                        local volume_config="${BASH_REMATCH[2]}"
                        
                        # Check if we've already declared this volume
                        if ! grep -q "^$volume_name$" "$temp_file" 2>/dev/null; then
                            echo "$volume_name" >> "$temp_file"
                            echo "$line"
                        fi
                    elif [[ "$line" =~ ^[[:space:]]{4,} ]]; then
                        # This is a continuation line for the previous volume (driver config, etc.)
                        echo "$line"
                    fi
                done
            fi
        done
        
        # Clean up temporary file
        rm -f "$temp_file"
    fi
    
    # Always add the exist network with bridge driver (single-node setup)
    echo ""
    echo "networks:"
    echo "  exist:"
    echo "    driver: bridge"
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Parse command line arguments
    action="${1:-status}"
    
    case "$action" in
        "enabled")
            get_enabled_services "." 2
            ;;
        "disabled")
            get_disabled_services "." 2
            ;;
        "all")
            list_all_services "." 2
            ;;
        "status")
            show_service_status "." 2
            ;;
        "generate-override")
            generate_compose_override "." 2
            ;;
        "generate-compose")
            output_file="${2:-docker-compose.generated.yml}"
            generate_compose_override "." 2 > "$output_file"
            echo "Generated merged docker-compose.yml as: $output_file" >&2
            ;;
        "profiles")
            show_available_profiles "." 2
            ;;
        "profile-docs")
            generate_profile_documentation "." 2
            ;;
        "categories")
            get_available_categories "." 2
            ;;
        "service-names")
            get_available_service_names "." 2
            ;;
        "check")
            service_path="$2"
            if [ -z "$service_path" ]; then
                echo "Usage: $0 check <service_path>"
                echo "Example: $0 check ai/ollama"
                exit 1
            fi
            
            if is_service_enabled "$service_path"; then
                echo "✅ Service $service_path is enabled"
                exit 0
            else
                echo "❌ Service $service_path is disabled"
                exit 1
            fi
            ;;
        "--help"|"-h")
            echo "Service Enablement Helper"
            echo "========================"
            echo ""
            echo "Usage: $0 [ACTION] [OPTIONS]"
            echo ""
            echo "ACTIONS:"
            echo "  status              Show status of all services (default)"
            echo "  enabled             List only enabled services"
            echo "  disabled            List only disabled services"
            echo "  all                 List all available services"
            echo "  check <service>     Check if a specific service is enabled"
            echo "  generate-override   Generate merged docker-compose content to stdout"
            echo "  generate-compose    Generate merged docker-compose.yml file"
            echo "  profiles            Show available Docker Compose profiles"
            echo "  profile-docs        Generate profile usage documentation"
            echo "  categories          List available categories"
            echo "  service-names       List available service names"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "EXAMPLES:"
            echo "  $0                           # Show service status"
            echo "  $0 enabled                   # List enabled services"
            echo "  $0 check ai/ollama           # Check if ollama is enabled"
            echo "  $0 generate-override > docker-compose.yml"
            echo "  $0 generate-compose docker-compose.prod.yml"
            echo "  $0 profiles                  # Show available profiles"
            echo "  $0 profile-docs > PROFILES.md # Generate profile documentation"
            echo ""
            echo "ENVIRONMENT VARIABLES:"
            echo "  Service enablement is controlled by EXIST_ENABLE_* variables:"
            echo "  EXIST_ENABLE_AI_LIBRECHAT=true"
            echo "  EXIST_ENABLE_SERVICES_NOCODB=false"
            echo "  etc."
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use '$0 --help' for usage information"
            exit 1
            ;;
    esac
fi
