#!/bin/bash

# Windmill User Creation Script
# This script creates a default user in Windmill using the Windmill API

# Function to wait for Windmill service to be ready
wait_for_windmill_service() {
    local max_attempts=30
    local attempt=1
    
    echo "🔄 Waiting for Windmill service to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        # Check if Windmill API is responding
        if curl -s "http://localhost:48008/api/version" >/dev/null 2>&1; then
            echo "✅ Windmill service is ready!"
            return 0
        fi
        
        echo "⏳ Attempt $attempt/$max_attempts - Windmill service not ready yet, waiting 3 seconds..."
        sleep 3
        ((attempt++))
    done
    
    echo "❌ Windmill service failed to become ready after $max_attempts attempts"
    return 1
}

# Function to check if superadmin user already exists
check_superadmin_exists() {
    local response
    
    # Try to create a token using the superadmin secret
    response=$(curl -s -w "%{http_code}" -o /tmp/windmill_check.json \
        -X POST "http://localhost:48008/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"admin@windmill.dev\", \"password\": \"${WINDMILL_SUPERADMIN_SECRET}\"}")
    
    local http_code="${response: -3}"
    
    if [ "$http_code" = "200" ]; then
        return 0  # Superadmin exists and secret works
    else
        return 1  # Either doesn't exist or secret doesn't work
    fi
}

# Function to create admin user using superadmin secret
create_admin_user() {
    local email="${WINDMILL_ADMIN_EMAIL:-admin@localhost}"
    local password="${WINDMILL_ADMIN_PASSWORD:-changeme}"
    local username="${WINDMILL_ADMIN_USERNAME:-admin}"
    
    echo "👤 Creating Windmill admin user..."
    echo "=================================="
    echo "Email: $email"
    echo "Username: $username"
    echo ""
    
    # Create the admin user directly using superadmin secret as bearer token
    echo "� Creating admin user with superadmin secret..."
    local user_response
    user_response=$(curl -s -w "%{http_code}" -o /tmp/windmill_user.json \
        -X POST "http://localhost:48008/api/users/create" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${WINDMILL_SUPERADMIN_SECRET}" \
        -d "{
            \"email\": \"$email\",
            \"username\": \"$username\",
            \"password\": \"$password\",
            \"super_admin\": true
        }")
    
    local user_http_code="${user_response: -3}"
    
    if [ "$user_http_code" = "201" ]; then
        echo "✅ Successfully created admin user: $username"
        echo "📧 Email: $email"
        echo "🔑 Password: [set from environment variable]"
    elif [ "$user_http_code" = "400" ]; then
        echo "ℹ️  User '$username' may already exist"
    else
        echo "❌ Failed to create admin user (HTTP $user_http_code)"
        echo "Response: $(cat /tmp/windmill_user.json 2>/dev/null)"
        return 1
    fi
    
    # Create a token for the admin user
    echo "🔑 Creating token for admin user..."
    local admin_token_response
    admin_token_response=$(curl -s -w "%{http_code}" -o /tmp/windmill_admin_token.json \
        -X POST "http://localhost:48008/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"$email\", \"password\": \"$password\"}")
    
    local admin_token_http_code="${admin_token_response: -3}"
    
    if [ "$admin_token_http_code" = "200" ]; then
        local admin_token
        admin_token=$(cat /tmp/windmill_admin_token.json 2>/dev/null | tr -d '
')
        
        if [ -n "$admin_token" ] && [ "$admin_token" != "null" ]; then
            echo "✅ Successfully created token for admin user"
            export WINDMILL_ADMIN_TOKEN="$admin_token"
            
            # Create a default workspace using the admin token
            create_default_workspace "$admin_token" "$email"
        else
            echo "⚠️  Admin user created but failed to extract token"
        fi
    else
        echo "⚠️  Admin user created but failed to generate token (HTTP $admin_token_http_code)"
    fi
    
    return 0
}

# Function to create a default workspace
create_default_workspace() {
    local admin_token="$1"
    local admin_email="$2"
    local workspace_id="${WINDMILL_DEFAULT_WORKSPACE:-main}"
    local workspace_name="${WINDMILL_DEFAULT_WORKSPACE_NAME:-Main Workspace}"
    local admin_username="${WINDMILL_ADMIN_USERNAME:-admin}"
    
    echo "🏢 Creating default workspace..."
    echo "Workspace ID: $workspace_id"
    echo "Workspace Name: $workspace_name"
    
    # Create workspace using the correct endpoint
    local workspace_response
    workspace_response=$(curl -s -w "%{http_code}" -o /tmp/windmill_workspace.json \
        -X POST "http://localhost:48008/api/workspaces/create" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $admin_token" \
        -d "{
            \"id\": \"$workspace_id\",
            \"name\": \"$workspace_name\"
        }")
    
    local workspace_http_code="${workspace_response: -3}"
    
    if [ "$workspace_http_code" = "200" ] || [ "$workspace_http_code" = "201" ]; then
        echo "✅ Successfully created workspace: $workspace_id"
    elif [ "$workspace_http_code" = "400" ]; then
        echo "ℹ️  Workspace '$workspace_id' may already exist"
    else
        echo "❌ Failed to create workspace (HTTP $workspace_http_code)"
        echo "Response: $(cat /tmp/windmill_workspace.json 2>/dev/null)"
        return 1
    fi
    
    # Add admin user to workspace
    echo "👥 Adding admin user to workspace..."
    local member_response
    member_response=$(curl -s -w "%{http_code}" -o /tmp/windmill_member.json \
        -X POST "http://localhost:48008/api/w/$workspace_id/workspaces/add_user" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $admin_token" \
        -d "{
            \"email\": \"$admin_email\",
            \"username\": \"$admin_username\",
            \"is_admin\": true,
            \"operator\": true
        }")
    
    local member_http_code="${member_response: -3}"
    
    if [ "$member_http_code" = "200" ] || [ "$member_http_code" = "201" ]; then
        echo "✅ Successfully added admin to workspace"
    elif [ "$member_http_code" = "400" ]; then
        echo "ℹ️  Admin user may already be in workspace"
    else
        echo "⚠️  Failed to add admin to workspace (HTTP $member_http_code)"
        echo "Response: $(cat /tmp/windmill_member.json 2>/dev/null)"
    fi
    
    export WINDMILL_DEFAULT_WORKSPACE_ID="$workspace_id"
    return 0
}

# Function to cleanup temporary files
cleanup_temp_files() {
    rm -f /tmp/windmill_*.json
}

# Main setup function
setup_windmill_admin() {
    echo "🌪️  Starting Windmill admin setup..."
    echo "===================================="
    
    # Validate required environment variables
    if [ -z "$WINDMILL_SUPERADMIN_SECRET" ]; then
        echo "❌ WINDMILL_SUPERADMIN_SECRET is required but not set"
        return 1
    fi
    
    # Set default values for admin user
    WINDMILL_ADMIN_EMAIL="${WINDMILL_ADMIN_EMAIL:-admin@localhost}"
    WINDMILL_ADMIN_PASSWORD="${WINDMILL_ADMIN_PASSWORD:-changeme}"
    WINDMILL_ADMIN_USERNAME="${WINDMILL_ADMIN_USERNAME:-admin}"
    WINDMILL_DEFAULT_WORKSPACE="${WINDMILL_DEFAULT_WORKSPACE:-existential}"
    WINDMILL_DEFAULT_WORKSPACE_NAME="${WINDMILL_DEFAULT_WORKSPACE_NAME:-Existential}"
    
    echo "Using Windmill admin credentials:"
    echo "  Email: $WINDMILL_ADMIN_EMAIL"
    echo "  Username: $WINDMILL_ADMIN_USERNAME"
    echo "  Workspace: $WINDMILL_DEFAULT_WORKSPACE"
    echo ""
    
    # Wait for service to be ready
    if ! wait_for_windmill_service; then
        echo "❌ Windmill service is not ready, cannot proceed"
        return 1
    fi
    
    # Create admin user and workspace
    if create_admin_user; then
        echo ""
        echo "🎉 Windmill admin setup completed successfully!"
        echo "==============================================="
        echo "📧 Admin Email: $WINDMILL_ADMIN_EMAIL"
        echo "🔑 Admin Password: [set from environment variable]"
        echo "🏢 Default Workspace: $WINDMILL_DEFAULT_WORKSPACE"
        echo "🌐 Access Windmill at: http://localhost:48008"
        echo ""
        echo "💡 You can now log in to Windmill with these credentials"
        
        # Cleanup temporary files
        cleanup_temp_files
        
        return 0
    else
        echo "❌ Failed to setup Windmill admin"
        cleanup_temp_files
        return 1
    fi
}

# If this script is run directly (not sourced), run the setup
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    setup_windmill_admin
fi
