# Windmill Admin Creation Script

## Overview

The `create_windmill_admin.sh` script automatically creates an admin user and default workspace in Windmill using the Windmill API. This script is designed to work with the Existential project's service management system.

## How It Works

### 1. Initial Setup

- Uses the `WINDMILL_SUPERADMIN_SECRET` to initialize the Windmill superadmin
- Creates a superadmin user with email `superadmin@windmill.dev`

### 2. Admin User Creation

- Creates a regular admin user with configurable credentials
- Generates a token for the admin user
- Sets up proper permissions

### 3. Workspace Creation

- Creates a default workspace (configurable)
- Adds the admin user to the workspace with admin privileges

## Configuration

The script uses the following environment variables:

### Required

- `WINDMILL_SUPERADMIN_SECRET`: The superadmin secret configured in Windmill

### Optional (with defaults)

- `WINDMILL_ADMIN_EMAIL`: Admin user email (default: `admin@localhost`)
- `WINDMILL_ADMIN_PASSWORD`: Admin user password (default: `changeme`)
- `WINDMILL_ADMIN_USERNAME`: Admin username (default: `admin`)
- `WINDMILL_DEFAULT_WORKSPACE`: Workspace ID (default: `main`)
- `WINDMILL_DEFAULT_WORKSPACE_NAME`: Workspace display name (default: `Main Workspace`)

## Usage

### Automatic (Recommended)

The script is automatically called by the `run_initial_setup.sh` script when:

1. Windmill service is enabled (`EXIST_ENABLE_SERVICES_WINDMILL=true`)
2. Windmill containers are running
3. You run the main setup: `./existential.sh` or `./automations/existential/run_initial_setup.sh`

### Manual

You can also run the script manually:

```bash
# Run as part of full setup
./automations/existential/run_initial_setup.sh windmill

# Run the script directly (ensure environment variables are set)
source .env
./automations/existential/create_windmill_admin.sh
```

## API Endpoints Used

The script uses the following Windmill API endpoints:

- `POST /api/users/first_time_setup` - Initialize superadmin
- `POST /api/auth/login` - Get authentication tokens
- `POST /api/w/admins/users/username` - Create admin user
- `POST /api/workspaces` - Create workspace
- `POST /api/w/{workspace}/users/add` - Add user to workspace

## Error Handling

The script includes comprehensive error handling:

- Validates required environment variables
- Waits for Windmill service to be ready
- Handles duplicate user/workspace creation gracefully
- Provides detailed error messages and HTTP status codes
- Cleans up temporary files

## Integration

This script is fully integrated with the Existential project:

1. **Environment Variables**: Uses the same variable patterns as other services
2. **Service Detection**: Only runs when Windmill is enabled and running
3. **Logging**: Consistent output format with other setup scripts
4. **Error Handling**: Graceful failures that don't break the overall setup

## Dependencies

- `curl`: For API requests
- `jq` (optional): For JSON parsing (fallback method included)
- `docker compose`: For service health checks

## Example Output

```
🌪️  Starting Windmill admin setup...
====================================
Using Windmill admin credentials:
  Email: admin@localhost
  Username: admin
  Workspace: main

🔄 Waiting for Windmill service to be ready...
✅ Windmill service is ready!
👤 Creating Windmill admin user...
==================================
Email: admin@localhost
Username: admin

🔐 Initializing superadmin...
✅ Superadmin user initialized (or already exists)
🔑 Getting superadmin token...
✅ Got superadmin token
👤 Creating admin user...
✅ Successfully created admin user: admin
🔑 Creating token for admin user...
✅ Successfully created token for admin user
🏢 Creating default workspace...
Workspace ID: main
Workspace Name: Main Workspace
✅ Successfully created workspace: main
👥 Adding admin user to workspace...
✅ Successfully added admin to workspace

🎉 Windmill admin setup completed successfully!
===============================================
📧 Admin Email: admin@localhost
🔑 Admin Password: changeme
🏢 Default Workspace: main
🌐 Access Windmill at: http://localhost:48008

💡 You can now log in to Windmill with these credentials
```

## Troubleshooting

### Service Not Ready

If Windmill service is not responding:

1. Check if containers are running: `docker compose ps`
2. Check container logs: `docker compose logs windmill_server`
3. Ensure port 48008 is not blocked

### Authentication Errors

If token creation fails:

1. Verify `WINDMILL_SUPERADMIN_SECRET` is correctly set
2. Check that the secret matches the one in the docker-compose configuration
3. Ensure no other Windmill instance is interfering

### JSON Parsing Errors

The script includes fallback JSON parsing for systems without `jq`:

- Primary method uses `jq` for robust parsing
- Fallback method uses `grep` and `cut` for basic token extraction
