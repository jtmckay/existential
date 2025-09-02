#!/bin/bash

# Initial Setup Scripts Runner
# This script runs all necessary setup scripts after containers are started

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Function to check if a service is enabled
is_service_enabled() {
    local service_name="$1"
    # Use the correct EXIST_ENABLE_* pattern to match service_enablement.sh
    local var_name="EXIST_ENABLE_${service_name}"
    local enabled_value="${!var_name}"
    
    if [ "$enabled_value" = "true" ] || [ "$enabled_value" = "1" ] || [ "$enabled_value" = "yes" ]; then
        return 0
    else
        return 1
    fi
}

# Function to check if a service is running
is_service_running() {
    local service_name="$1"
    docker compose ps "$service_name" 2>/dev/null | grep -q "Up"
}

# Function to run Vikunja user setup
setup_vikunja() {
    echo "🔧 Setting up Vikunja..."
    echo "======================"
    
    if ! is_service_enabled "SERVICES_VIKUNJA"; then
        echo "ℹ️  Vikunja is not enabled, skipping setup"
        return 0
    fi
    
    if ! is_service_running "vikunja"; then
        echo "⚠️  Vikunja service is not running, skipping user creation"
        echo "💡 Start Vikunja first: docker compose up vikunja vikunja_db -d"
        return 1
    fi
    
    # Load service-specific environment variables before calling the setup
    if [ -f "services/vikunja/.env" ]; then
        set -a
        source "services/vikunja/.env"
        set +a
        echo "✅ Loaded Vikunja service environment variables"
    fi
    
    # Set fallback environment variables for Vikunja
    VIKUNJA_DEFAULT_USERNAME="${VIKUNJA_DEFAULT_USERNAME:-${EXIST_DEFAULT_USERNAME:-admin}}"
    VIKUNJA_DEFAULT_PASSWORD="${VIKUNJA_DEFAULT_PASSWORD:-${EXIST_DEFAULT_PASSWORD:-changeme}}"
    VIKUNJA_DEFAULT_EMAIL="${VIKUNJA_DEFAULT_EMAIL:-${EXIST_DEFAULT_EMAIL:-admin@example.com}}"
    
    echo "Using Vikunja credentials:"
    echo "  Username: $VIKUNJA_DEFAULT_USERNAME"
    echo "  Email: $VIKUNJA_DEFAULT_EMAIL"
    echo ""
    
    # Source the Vikunja user creation script
    if [ -f "$SCRIPT_DIR/create_vikunja_user.sh" ]; then
        source "$SCRIPT_DIR/create_vikunja_user.sh"
        setup_vikunja_user
    else
        echo "❌ Vikunja user creation script not found"
        return 1
    fi
}

# Function to run Windmill admin setup
setup_windmill() {
    echo "🔧 Setting up Windmill..."
    echo "========================"
    
    if ! is_service_enabled "SERVICES_WINDMILL"; then
        echo "ℹ️  Windmill is not enabled, skipping setup"
        return 0
    fi
    
    if ! is_service_running "windmill_server"; then
        echo "⚠️  Windmill server is not running, skipping admin creation"
        echo "💡 Start Windmill first: docker compose up windmill_server windmill_pg -d"
        return 1
    fi
    
    # Load service-specific environment variables before calling the setup
    if [ -f "services/windmill/.env" ]; then
        set -a
        source "services/windmill/.env"
        set +a
        echo "✅ Loaded Windmill service environment variables"
    fi
    
    # Source the Windmill admin creation script
    if [ -f "$SCRIPT_DIR/create_windmill_admin.sh" ]; then
        source "$SCRIPT_DIR/create_windmill_admin.sh"
        setup_windmill_admin
    else
        echo "❌ Windmill admin creation script not found"
        return 1
    fi
}

# Function to setup other services that need post-startup configuration
setup_other_services() {
    echo "🔧 Checking for other services needing setup..."
    echo "=============================================="
    
    local services_needing_setup=()
    
    # Add other services here that need post-startup setup
    # For example:
    # - Database migrations
    # - Admin user creation
    # - Initial configuration
    
    # RabbitMQ works fine out of the box with environment variables
    # No additional setup needed
    
    if [ ${#services_needing_setup[@]} -eq 0 ]; then
        echo "ℹ️  No additional services require post-startup setup"
        echo "💡 Most services (RabbitMQ, Portainer, etc.) work immediately with environment variables"
        return 0
    fi
    
    # Process any services that do need setup
    for service in "${services_needing_setup[@]}"; do
        echo "Setting up $service..."
        # Add service-specific setup calls here
    done
}

# Function to check for other services that might need setup
setup_other_services() {
    echo "🔧 Checking other services for setup requirements..."
    echo "=================================================="
    
    local setup_needed=false
    
    # Add checks for other services that might need initial setup
    # For example:
    # - Database migrations
    # - Admin user creation
    # - Initial configuration
    
    if [ "$setup_needed" = false ]; then
        echo "ℹ️  No additional service setup required"
    fi
}

# Function to display service URLs and access information
show_service_access_info() {
    echo "🌐 Service Access Information"
    echo "============================"
    echo ""
    
    if is_service_enabled "SERVICES_VIKUNJA" && is_service_running "vikunja"; then
        echo "📝 Vikunja (Task Management):"
        echo "   URL: ${VIKUNJA_SERVICE_PUBLICURL:-http://localhost:43456}"
        echo "   Username: ${VIKUNJA_DEFAULT_USERNAME:-admin}"
        echo "   Password: ${VIKUNJA_DEFAULT_PASSWORD:-changeme}"
        echo ""
    fi
    
    if is_service_enabled "SERVICES_WINDMILL" && is_service_running "windmill_server"; then
        echo "⚡ Windmill (Workflow Automation):"
        echo "   URL: ${WINDMILL_PUBLIC_URL:-http://localhost:48008}"
        echo "   Email: ${WINDMILL_ADMIN_EMAIL:-admin@localhost}"
        echo "   Password: ${WINDMILL_ADMIN_PASSWORD:-changeme}"
        echo ""
    fi
    
    if is_service_enabled "SERVICES_RABBITMQ" && is_service_running "rabbitmq"; then
        echo "🐰 RabbitMQ Management:"
        echo "   URL: ${RABBITMQ_MANAGEMENT_URL:-http://localhost:15672}"
        echo "   Username: ${RABBITMQ_DEFAULT_USER:-admin}"
        echo "   Password: ${RABBITMQ_DEFAULT_PASS:-changeme}"
        echo "   💡 Ready to use - no additional setup required"
        echo ""
    fi
    
    # Add other services as needed
    if is_service_enabled "HOSTING_PORTAINER" && is_service_running "portainer"; then
        echo "🐳 Portainer (Docker Management):"
        echo "   URL: ${PORTAINER_URL:-http://localhost:9000}"
        echo ""
    fi
}

# Function to run all setup scripts
run_all_setup() {
    echo "🚀 Running Initial Setup Scripts"
    echo "================================"
    echo ""
    
    # Change to project root
    cd "$PROJECT_ROOT" || {
        echo "❌ Error: Cannot change to project root directory: $PROJECT_ROOT"
        exit 1
    }
    
    # Source environment variables
    if [ -f ".env" ]; then
        set -a
        source ".env"
        set +a
        echo "✅ Environment variables loaded from .env"
    else
        echo "⚠️  No .env file found - some setups may not work"
    fi
    
    echo ""
    
    # Run individual setup functions
    local setup_results=()
    
    # Vikunja setup (actually needs user creation)
    if setup_vikunja; then
        setup_results+=("✅ Vikunja")
    else
        setup_results+=("⚠️  Vikunja")
    fi
    
    echo ""
    
    # Windmill setup (needs admin user creation)
    if setup_windmill; then
        setup_results+=("✅ Windmill")
    else
        setup_results+=("⚠️  Windmill")
    fi
    
    echo ""
    
    # Check for other services that need setup
    setup_other_services
    setup_results+=("✅ Other Services")
    
    echo ""
    echo "📊 Setup Summary:"
    for result in "${setup_results[@]}"; do
        echo "  $result"
    done
    
    echo ""
    show_service_access_info
    
    echo "🎉 Initial setup completed!"
    echo ""
    echo "💡 Next steps:"
    echo "  • Access your services using the URLs above"
    echo "  • Check service logs: docker compose logs [service_name]"
    echo "  • Monitor service status: docker compose ps"
    echo ""
}

# Function to show available setup options
show_setup_options() {
    echo "Available setup commands:"
    echo "  all       Run all setup scripts (default)"
    echo "  vikunja   Set up Vikunja user only"
    echo "  windmill  Set up Windmill admin only"
    echo "  info      Show service access information only"
    echo "  --help    Show this help message"
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    action="${1:-all}"
    
    case "$action" in
        "--help"|"-h")
            echo "Initial Setup Scripts Runner"
            echo "==========================="
            echo ""
            echo "Usage: $0 [ACTION]"
            echo ""
            show_setup_options
            echo ""
            echo "This script runs setup scripts for services that require"
            echo "initial configuration after containers are started."
            ;;
        "all")
            run_all_setup
            ;;
        "vikunja")
            cd "$PROJECT_ROOT" || exit 1
            if [ -f ".env" ]; then
                set -a; source ".env"; set +a
            fi
            setup_vikunja
            ;;
        "windmill")
            cd "$PROJECT_ROOT" || exit 1
            if [ -f ".env" ]; then
                set -a; source ".env"; set +a
            fi
            setup_windmill
            ;;
        "info")
            cd "$PROJECT_ROOT" || exit 1
            if [ -f ".env" ]; then
                set -a; source ".env"; set +a
            fi
            show_service_access_info
            ;;
        *)
            echo "❌ Unknown action: $action"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
fi
