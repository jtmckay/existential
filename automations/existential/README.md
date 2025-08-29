# Existential Automation Scripts

This directory contains shell scripts and utilities for the Existential project automation tasks.


## 🚀 Quick Start

Get your entire Existential environment configured in one command:

```bash
./existential.sh
```

This unified script will:
- **Find ALL `.example` files** in your project (30+ configuration files)
- **Create counterpart files** by removing the `.example` extension
- **Process placeholders** interactively and automatically
- **Load environment variables** from your root `.env` file
- **Generate Docker Compose configuration** from enabled services
- **Provide comprehensive reporting** of what was configured

### What Gets Processed

The unified processor handles **7 different file types** across your entire project:

- **18** `.env.example` files → Environment configuration
- **5** `.pem.example` files → SSL certificates and keys  
- **2** `.json.example` files → JSON configuration
- **2** `.yml.example` files → YAML configuration
- **1** `.yaml.example` file → YAML configuration
- **1** `.Caddyfile.example` file → Reverse proxy configuration
- **1** `.conf.example` file → Server configuration

### 🔒 Safe Processing & File Protection

The system is designed with safety in mind:
- **Never modifies existing files** - Only creates new files from `.example` templates
- **Clear messaging** when files already exist with guidance to delete and regenerate if needed
- **Root-level priority** - Processes root `.env.example` first with CLI prompts and password generation
- **Environment sourcing** - Automatically loads root `.env` variables after creation

### 🌟 Dynamic Variable System

Use `EXIST_DEFAULT_*` variables in your root `.env` file to automatically propagate values across all service configurations:

```bash
# In root .env file
EXIST_DEFAULT_EMAIL=your@email.com
EXIST_DEFAULT_USERNAME=yourusername
EXIST_DEFAULT_PASSWORD=generated_password
```

These values automatically replace matching variables in all service `.env` files:
```bash
# In services/nocodb/.env (automatically replaced)
NOCODB_ADMIN_EMAIL=your@email.com  # was EXIST_DEFAULT_EMAIL
```

### Advanced Usage

```bash
# See what example file types exist in your project
./existential.sh types

# Process only environment files
./existential.sh env-only

# Process only YAML configuration files
./existential.sh pattern '*.yml.example'

# Process only SSL certificate files
./existential.sh pattern '*.pem.example'

# Manage individual services
./existential.sh services status
./existential.sh services enable mealie
./existential.sh services disable windmill

# Generate Docker Compose configuration
./existential.sh generate-compose
```

## Main Scripts

### `unified_example_processor.sh`
A comprehensive cross-platform bash script that systematically processes ALL `.example` files in the project, creating configuration files and handling placeholder replacements.

**Features:**
- **Universal file processing**: Handles 7+ different file types (`.env`, `.pem`, `.yml`, `.json`, `.yaml`, `.conf`, `.Caddyfile`)
- **Dynamic variable system**: `EXIST_DEFAULT_*` variables from root `.env` automatically propagate to all services
- **Safe processing**: Never modifies existing files, only creates new ones from templates
- **Interactive prompts**: `EXIST_CLI` placeholders prompt for user input
- **Automatic generation**: Passwords, hex keys, timestamps, and UUIDs generated automatically
- **Cross-platform compatibility**: Works on Windows (Git Bash/WSL), Mac, and Linux
- **Root-first processing**: Prioritizes root-level files for environment sourcing

**Usage:**
```bash
# Process all .example files in the project
./unified_example_processor.sh

# Process with custom parameters
./unified_example_processor.sh "search_dir" "max_depth" "file_pattern" "process_root_first"

# Example: Process only .env files with depth 3
./unified_example_processor.sh "." "3" "*.env.example" "true"
```

**Functions:**
- `process_all_example_files(dir, depth, pattern, root_first)` - Main processing function
- `find_example_files(dir, depth, pattern)` - File discovery with pattern matching
- `process_example_file(file, is_root_level)` - Individual file processing
- `get_exist_default_variables()` - Extract dynamic variables from root `.env`
### `interactive_cli_replacer.sh`
Interactive script that finds and replaces `EXIST_CLI` placeholders in files by prompting the user for values. Shows context comments before each variable to help understand what value is needed.

**Features:**
- Finds all instances of `EXIST_CLI` in files
- Shows preceding comment lines (starting with `# `) as context
- Interactive prompts for each placeholder
- Option to skip individual variables
- Processes files individually with confirmation between files
- Backup and rollback on errors
- Proper escaping for special characters including `/`

**Usage:**
```bash
# Process specific files
./interactive_cli_replacer.sh file1.env file2.env

# Show help
./interactive_cli_replacer.sh --help
```

**Functions:**
- `process_files_interactive(file_paths...)` - Process specific files
- `extract_context_comments(file, line_number)` - Extract comments before a variable

### `service_enablement.sh`
Helper script for managing service enablement through individual environment variables. Each service can be enabled/disabled independently using `EXIST_ENABLE_*` variables.

**Features:**
- Individual service control via environment variables
- Service status reporting and management
- Docker compose override generation
- Cross-platform compatibility
- Integration with existential.sh workflow

**Usage:**
```bash
# Show status of all services
./service_enablement.sh status

# List only enabled services
./service_enablement.sh enabled

# Check specific service
./service_enablement.sh check ai/ollama

# Generate docker-compose override
./service_enablement.sh generate-override > docker-compose.override.yml

# Via main script
./existential.sh services status
./existential.sh services enabled
```

**Functions:**
- `is_service_enabled(service_path)` - Check if a service is enabled
- `get_enabled_services()` - List all enabled services
- `get_disabled_services()` - List all disabled services
- `show_service_status()` - Display comprehensive service status
- `generate_compose_override()` - Generate docker-compose configuration

**Environment Variables:**
Service enablement uses individual boolean variables:
```bash
EXIST_ENABLE_AI_LIBRECHAT=true
EXIST_ENABLE_AI_OLLAMA=true
EXIST_ENABLE_SERVICES_NOCODB=true
EXIST_ENABLE_HOSTING_PORTAINER=false
# etc.
```

### `generate_password.sh`
Generates secure passwords of various lengths using mixed case letters, numbers, and safe special characters.

**Usage:**
```bash
# Run independently
./generate_password.sh

# Source in another script
source generate_password.sh
password=$(generate_password 24)  # Generate 24-character password
password_24=$(generate_24_char_password)  # Convenience function
```

**Functions:**
- `generate_password(length)` - Returns a secure password of specified length
- `generate_24_char_password()` - Convenience function for 24-character passwords

### `generate_hex_key.sh`
Generates hexadecimal keys of any specified length (0-9, a-f) suitable for API keys, tokens, and encryption keys.

**Usage:**
```bash
# Run independently
./generate_hex_key.sh 32    # Generate 32-character hex key
./generate_hex_key.sh 64    # Generate 64-character hex key
./generate_hex_key.sh       # Generate 32-character hex key (default)

# Source in another script
source generate_hex_key.sh
hex_key_32=$(generate_32_char_hex)
hex_key_64=$(generate_64_char_hex)
hex_key_custom=$(generate_hex_key 48)
```

**Functions:**
- `generate_hex_key(length)` - Returns hex key of specified length
- `generate_32_char_hex()` - Convenience function for 32-character hex keys
- `generate_64_char_hex()` - Convenience function for 64-character hex keys

## Placeholder Processing

The system supports several types of placeholders that are automatically processed:

### Interactive Placeholders
- `EXIST_CLI` - Prompts user for input during processing

### Generated Values
- `EXIST_24_CHAR_PASSWORD` - Generates secure 24-character passwords
- `EXIST_32_CHAR_HEX_KEY` - Generates 32-character hex keys  
- `EXIST_64_CHAR_HEX_KEY` - Generates 64-character hex keys
- `EXIST_TIMESTAMP` - Generates current timestamp (YYYYMMDD_HHMMSS)
- `EXIST_UUID` - Generates UUID (or timestamp-based fallback)

### Dynamic Variables
- `EXIST_DEFAULT_*` - Any variable starting with this prefix in root `.env` automatically propagates to all service configurations

## Integration

These scripts are integrated into the main `existential.sh` workflow:

```bash
./existential.sh           # Uses unified_example_processor.sh
./existential.sh env-only   # Processes only .env.example files
./existential.sh services   # Uses service_enablement.sh
```

## Development Notes

All scripts follow these patterns:
- **Cross-platform compatibility**: Work on Windows (Git Bash/WSL), Mac, and Linux
- **Safe operations**: Never overwrite existing files without explicit confirmation
- **Comprehensive error handling**: Clear error messages and graceful failures
- **Modular design**: Can be sourced by other scripts or run independently
- **Consistent interfaces**: Similar parameter patterns across scripts

## Adding New Scripts

When creating new shell scripts for the Existential project:
1. Place them in this directory (`automations/existential/`)
2. Use basic bash operations for cross-platform compatibility
3. Include proper error handling and documentation
4. Make them sourceable by other scripts when appropriate
5. Update this README with new script descriptions
