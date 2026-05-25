#!/bin/bash

# Vikunja User Creation Script
# This script creates a default user in Vikunja after the database is ready

# Function to wait for Vikunja database to be ready
wait_for_vikunja_db() {
    local max_attempts=30
    local attempt=1
    
    echo "🔄 Waiting for Vikunja database to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker compose exec vikunja_db pg_isready -U "${VIKUNJA_DATABASE_USER}" >/dev/null 2>&1; then
            echo "✅ Vikunja database is ready!"
            return 0
        fi
        
        echo "⏳ Attempt $attempt/$max_attempts - Database not ready yet, waiting 2 seconds..."
        sleep 2
        ((attempt++))
    done
    
    echo "❌ Database failed to become ready after $max_attempts attempts"
    return 1
}

# Function to wait for Vikunja service to be ready
wait_for_vikunja_service() {
    local max_attempts=30
    local attempt=1
    
    echo "🔄 Waiting for Vikunja service to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        # Check from host instead of from within container
        if curl -s "http://localhost:43456/api/v1/info" >/dev/null 2>&1; then
            echo "✅ Vikunja service is ready!"
            return 0
        fi
        
        echo "⏳ Attempt $attempt/$max_attempts - Vikunja service not ready yet, waiting 3 seconds..."
        sleep 3
        ((attempt++))
    done
    
    echo "❌ Vikunja service failed to become ready after $max_attempts attempts"
    return 1
}

# Function to check if user already exists
check_user_exists() {
    local username="$1"
    
    # Try to list users and check if our user exists
    if docker compose exec vikunja /app/vikunja/vikunja user list 2>/dev/null | grep -q "$username"; then
        return 0  # User exists
    else
        return 1  # User does not exist
    fi
}

# Function to create Vikunja user
create_vikunja_user() {
    local username="${VIKUNJA_DEFAULT_USERNAME:-admin}"
    local password="${VIKUNJA_DEFAULT_PASSWORD:-changeme}"
    local email="${VIKUNJA_DEFAULT_EMAIL:-admin@localhost}"
    
    echo "👤 Creating Vikunja user..."
    echo "=========================="
    echo "Username: $username"
    echo "Email: $email"
    echo ""
    
    # Check if user already exists
    if check_user_exists "$username"; then
        echo "ℹ️  User '$username' already exists, skipping creation"
        return 0
    fi
    
    # Create the user using the correct command format
    if docker compose exec vikunja /app/vikunja/vikunja user create \
        --username "$username" \
        --password "$password" \
        --email "$email" 2>/dev/null; then
        echo "✅ Successfully created Vikunja user: $username"
        echo "📧 Email: $email"
        echo "🔑 Password: $password"
        echo ""
        echo "💡 You can now log in to Vikunja with these credentials"
        echo "🌐 Access Vikunja at: ${VIKUNJA_SERVICE_PUBLICURL:-http://localhost:43456}"
        return 0
    else
        echo "❌ Failed to create Vikunja user"
        echo "💡 This might be because:"
        echo "   • The user already exists"
        echo "   • The database is not properly initialized"
        echo "   • There's a connectivity issue"
        echo ""
        echo "🔧 You can try creating the user manually:"
        echo "   docker compose exec vikunja /app/vikunja/vikunja user create --username $username --password $password --email $email"
        return 1
    fi
}

# Function to run the complete Vikunja user setup
setup_vikunja_user() {
    echo "🚀 Vikunja User Setup"
    echo "===================="
    echo ""
    
    # Check if Vikunja containers are running
    if ! docker compose ps vikunja | grep -q "Up"; then
        echo "❌ Vikunja container is not running"
        echo "💡 Please start Vikunja first: docker compose up vikunja vikunja_db -d"
        return 1
    fi
    
    if ! docker compose ps vikunja_db | grep -q "Up"; then
        echo "❌ Vikunja database container is not running"
        echo "💡 Please start Vikunja first: docker compose up vikunja vikunja_db -d"
        return 1
    fi
    
    # Wait for database to be ready
    if ! wait_for_vikunja_db; then
        echo "❌ Database setup failed"
        return 1
    fi
    
    # Wait for Vikunja service to be ready
    if ! wait_for_vikunja_service; then
        echo "❌ Vikunja service setup failed"
        return 1
    fi
    
    # Create the user
    if create_vikunja_user; then
        echo "🎉 Vikunja user setup completed successfully!"
        return 0
    else
        echo "⚠️  Vikunja user setup completed with warnings"
        return 1
    fi
}

# Function to check if required environment variables are set
check_vikunja_env() {
    # Use service-specific variables first, then fallback to EXIST_* variables
    VIKUNJA_DEFAULT_USERNAME="${VIKUNJA_DEFAULT_USERNAME:-${EXIST_USERNAME:-admin}}"
    VIKUNJA_DEFAULT_PASSWORD="${VIKUNJA_DEFAULT_PASSWORD:-${EXIST_PASSWORD:-changeme}}"
    VIKUNJA_DEFAULT_EMAIL="${VIKUNJA_DEFAULT_EMAIL:-${EXIST_EMAIL:-admin@example.com}}"
    
    echo "Using Vikunja credentials:"
    echo "  Username: $VIKUNJA_DEFAULT_USERNAME"
    echo "  Email: $VIKUNJA_DEFAULT_EMAIL"
    echo ""
    
    # No missing variables since we have defaults
    return 0
}

# Main execution when script is run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Change to the directory containing docker-compose.yml
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    
    cd "$PROJECT_ROOT" || {
        echo "❌ Error: Cannot change to project root directory: $PROJECT_ROOT"
        exit 1
    }
    
    # Source environment variables - first root .env, then service-specific .env
    if [ -f ".env" ]; then
        set -a
        source ".env"
        set +a
        echo "✅ Loaded root environment variables"
    else
        echo "⚠️  No .env file found in project root"
    fi
    
    # Source service-specific environment variables
    if [ -f "services/vikunja/.env" ]; then
        set -a
        source "services/vikunja/.env"
        set +a
        echo "✅ Loaded Vikunja service environment variables"
    else
        echo "⚠️  No .env file found in services/vikunja/"
        echo "💡 Some functionality may not work without environment variables"
    fi
    
    # Check for required environment variables
    if ! check_vikunja_env; then
        exit 1
    fi
    
    # Run the setup
    setup_vikunja_user
fi
