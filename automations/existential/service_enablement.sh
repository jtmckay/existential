#!/bin/bash

# Service Enablement Helper
# Provides functions to check which services are enabled in the environment
# Compatible with Windows (Git Bash/WSL), Mac, and Linux

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the docker compose finder
if [ -f "$SCRIPT_DIR/find_docker_compose.sh" ]; then
    source "$SCRIPT_DIR/find_docker_compose.sh"
else
    echo "Error: find_docker_compose.sh not found in $SCRIPT_DIR"
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

# Function to show available profiles
show_available_profiles() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    
    echo "Available Docker Compose Profiles"
    echo "================================="
    echo ""
    
    echo "🌐 Global Profiles:"
    echo "  all                   - All services"
    echo ""
    
    echo "📂 Category Profiles:"
    local categories=()
    mapfile -t categories < <(get_available_categories "$search_dir" "$max_depth")
    
    for category in "${categories[@]}"; do
        local services_in_category=()
        mapfile -t services_in_category < <(get_all_available_services "$search_dir" "$max_depth" | grep "^$category/")
        echo "  $category$(printf "%*s" $((20 - ${#category})) "")- ${#services_in_category[@]} services ($(echo "${services_in_category[@]}" | sed "s|$category/||g" | tr ' ' ',' | tr '\n' ' ' | sed 's/, $//'))"
    done
    
    echo ""
    echo "🔧 Individual Service Profiles:"
    local service_names=()
    mapfile -t service_names < <(get_available_service_names "$search_dir" "$max_depth")
    
    local col_count=0
    for service_name in "${service_names[@]}"; do
        printf "  %-20s" "$service_name"
        ((col_count++))
        if [ $((col_count % 3)) -eq 0 ]; then
            echo ""
        fi
    done
    
    if [ $((col_count % 3)) -ne 0 ]; then
        echo ""
    fi
    
    echo ""
    echo "💡 Usage Examples:"
    echo "  docker-compose --profile ai up -d           # Start all AI services"
    echo "  docker-compose --profile hosting up -d      # Start all hosting services"
    echo "  docker-compose --profile librechat up -d    # Start only LibreChat service"
    echo "  docker-compose --profile all up -d          # Start all enabled services"
}

# Function to generate profile usage documentation
generate_profile_documentation() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    
    echo "# Docker Compose Profiles Usage"
    echo ""
    echo "This docker-compose.yml file uses profiles to organize services by category and individual services."
    echo ""
    echo "## Available Profiles"
    echo ""
    
    echo "### Global"
    echo "- \`all\` - All services"
    echo ""
    
    echo "### Categories"
    local categories=()
    mapfile -t categories < <(get_available_categories "$search_dir" "$max_depth")
    
    for category in "${categories[@]}"; do
        local services_in_category=()
        mapfile -t services_in_category < <(get_all_available_services "$search_dir" "$max_depth" | grep "^$category/")
        echo "- \`$category\` - ${#services_in_category[@]} services:"
        for service_path in "${services_in_category[@]}"; do
            local service_name=$(echo "$service_path" | cut -d'/' -f2)
            echo "  - $service_name"
        done
        echo ""
    done
    
    echo "### Individual Services"
    local service_names=()
    mapfile -t service_names < <(get_available_service_names "$search_dir" "$max_depth")
    
    for service_name in "${service_names[@]}"; do
        echo "- \`$service_name\`"
    done
    
    echo ""
    echo "## Usage Examples"
    echo ""
    echo "\`\`\`bash"
    echo "# Start all services"
    echo "docker-compose --profile all up -d"
    echo ""
    echo "# Start AI services only"
    echo "docker-compose --profile ai up -d"
    echo ""
    echo "# Start hosting services only"
    echo "docker-compose --profile hosting up -d"
    echo ""
    echo "# Start specific service"
    echo "docker-compose --profile librechat up -d"
    echo ""
    echo "# Combine profiles"
    echo "docker-compose --profile ai --profile hosting up -d"
    echo ""
    echo "# Stop services by profile"
    echo "docker-compose --profile ai down"
    echo "\`\`\`"
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

# Function to generate merged docker-compose.yml based on enabled services
generate_compose_override() {
    local search_dir="${1:-.}"
    local max_depth="${2:-2}"
    local output_file="${3:-docker-compose.generated.yml}"
    
    local enabled_services=()
    mapfile -t enabled_services < <(get_enabled_services "$search_dir" "$max_depth")
    
    echo "# Generated docker-compose.yml based on enabled services"
    echo "# This file is auto-generated from individual service docker-compose.yml files"
    echo "# Services enabled: ${#enabled_services[@]}"
    echo "# Generated on: $(date)"
    echo ""
    echo "version: '3.8'"
    echo ""
    echo "services:"
    
    if [ ${#enabled_services[@]} -eq 0 ]; then
        echo "  # No services enabled"
        echo ""
        echo "networks:"
        echo "  exist:"
        echo "    external: true"
        return 0
    fi
    
    local all_volumes=()
    local has_networks=false
    
    # Process each enabled service
    for service in "${enabled_services[@]}"; do
        local compose_file="$search_dir/$service/docker-compose.yml"
        
        if [ ! -f "$compose_file" ]; then
            echo "  # Warning: docker-compose.yml not found for $service" >&2
            continue
        fi
        
        echo ""
        echo "  # Services from $service"
        
        # Extract services section and add env_file references
        local services_content
        services_content=$(get_compose_services_only "$compose_file")
        
        if [ -n "$services_content" ]; then
            # Add env_file and profiles to each service in the content
            add_env_file_and_profiles_to_services "$service" "$services_content"
        else
            echo "  # No services found in $compose_file"
        fi
        
        # Extract volumes section - only get actual named volume definitions
        local volumes_section
        volumes_section=$(awk '
        /^volumes:/ { in_volumes = 1; depth = 0; next }
        /^[a-zA-Z]/ && in_volumes && !/^[[:space:]]/ { in_volumes = 0 }
        in_volumes {
            # Count indentation to determine if this is a top-level volume definition
            indent = match($0, /[^ ]/) - 1
            if (indent == 2 && /^[[:space:]]*[a-zA-Z0-9_-]+:/) {
                # This is a volume name at the correct indentation level
                gsub(/:.*$/, "", $1)
                gsub(/^[[:space:]]*/, "", $1)
                # Skip known driver option keys
                if ($1 != "driver" && $1 != "driver_opts" && $1 != "external") {
                    print $1
                }
            }
        }' "$compose_file")
        
        if [ -n "$volumes_section" ]; then
            while IFS= read -r volume; do
                # Remove trailing colon
                volume="${volume%:}"
                all_volumes+=("$volume")
            done <<< "$volumes_section"
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
        # Remove duplicates and sort
        printf '%s\n' "${all_volumes[@]}" | sort -u | while IFS= read -r volume; do
            echo "  $volume:"
        done
    fi
    
    # Always add the exist network
    echo ""
    echo "networks:"
    echo "  exist:"
    echo "    external: true"
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
