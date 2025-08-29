# Existential Automation Scripts

This directory contains shell scripts and utilities for the Existential project automation tasks.

## Scripts

### `find_env_examples.sh`
A cross-platform bash script that recursively finds all `.env.example` files in a directory structure, excluding the graveyard directory, with configurable search depth.

**Features:**
- Cross-platform compatibility (Windows Git Bash/WSL, Mac, Linux)
- Uses basic bash operations for maximum portability
- Can be sourced by other scripts or run independently
- Provides both array storage and streaming options
- Automatically excludes `/graveyard/` directory from search results
- Configurable search depth (0=current dir only, default=2)

**Usage:**
```bash
# Run independently
./find_env_examples.sh

# Source in another script
source find_env_examples.sh
mapfile -t env_files < <(find_env_examples "." 2)  # depth 2 (default)
mapfile -t env_files < <(find_env_examples "." 0)  # current directory only
```

**Function:**
- `find_env_examples(search_dir, max_depth)` - Returns newline-separated list of .env.example files
  - `search_dir`: Directory to search (default: current directory)
  - `max_depth`: Maximum search depth (default: 2)
    - 0: Current directory only
    - 1: 1 level deep only (excludes current directory)
    - 2: 1-2 levels deep (excludes current directory, includes services/app/)
    - 3+: 1-3+ levels deep (excludes current directory)

### `interactive_cli_replacer.sh`
Interactive script that finds and replaces `EXIST_CLI` placeholders in .env files by prompting the user for values. Shows context comments before each variable to help understand what value is needed.

**Features:**
- Finds all instances of `EXIST_CLI` in files
- Shows preceding comment lines (starting with `# `) as context
- Interactive prompts for each placeholder
- Option to skip individual variables
- Processes files individually with confirmation between files
- Works with specific files or directory scanning
- Backup and rollback on errors

**Usage:**
```bash
# Process .env files in current directory (depth 2)
./interactive_cli_replacer.sh

# Process .env files in current directory only
./interactive_cli_replacer.sh --depth 0

# Process specific directory
./interactive_cli_replacer.sh services/

# Process specific files
./interactive_cli_replacer.sh file1.env file2.env

# Show help
./interactive_cli_replacer.sh --help
```

**Functions:**
- `process_files_interactive(file_paths...)` - Process specific files
- `process_env_files_interactive(search_dir, max_depth)` - Find and process .env files
- `extract_context_comments(file, line_number)` - Extract comments before a variable

### `service_enablement.sh`
Helper script for managing service enablement through individual environment variables. Each service can be enabled/disabled independently using EXIST_ENABLE_* variables.

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
Generates a secure 24-character password using mixed case letters, numbers, and safe special characters.

**Usage:**
```bash
# Run independently
./generate_password.sh

# Source in another script
source generate_password.sh
password=$(generate_24_char_password)
```

**Function:**
- `generate_24_char_password()` - Returns a 24-character secure password

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

### `create_env_generated.sh`
Creates `.env.generated` files from all `.env.example` files found recursively in a directory structure.

**Usage:**
```bash
# Create all .env.generated files in current directory
./create_env_generated.sh

# Create .env.generated files in specific directory
./create_env_generated.sh /path/to/project

# Create files with specific depth
./create_env_generated.sh --depth 0      # Current directory only
./create_env_generated.sh --depth 1      # Current + 1 level
./create_env_generated.sh --depth 2      # Current + 2 levels (default)

# Dry run - show what would be created without creating files
./create_env_generated.sh --dry-run
./create_env_generated.sh --dry-run --depth 0

# Show help
./create_env_generated.sh --help
```

**Functions:**
- `create_env_generated_files(search_dir, max_depth)` - Creates .env.generated files from .env.example files
- `list_env_generated_files(search_dir, max_depth)` - Lists what files would be created (dry run mode)

**Features:**
- Skips existing `.env.generated` files
- Creates necessary directories
- Provides detailed progress and summary
- Error handling and validation

### `process_env_placeholders.sh`
Processes `.env.generated` files and replaces placeholder variables with actual generated values or environment variables.

**Usage:**
```bash
# Set required environment variables
export EXIST_DEFAULT_EMAIL='admin@example.com'
export EXIST_DEFAULT_USERNAME='admin'

# Process all .env.generated files in current directory
./process_env_placeholders.sh

# Process .env.generated files in specific directory
./process_env_placeholders.sh /path/to/project

# Process files with specific depth
./process_env_placeholders.sh --depth 0      # Current directory only
./process_env_placeholders.sh --depth 1      # Current + 1 level
./process_env_placeholders.sh --depth 2      # Current + 2 levels (default)

# Check environment variable status
./process_env_placeholders.sh --status

# Show help
./process_env_placeholders.sh --help
```

**Placeholder Replacements:**
- `EXIST_24_CHAR_PASSWORD` → Generated 24-character secure password
- `EXIST_32_CHAR_HEX_KEY` → Generated 32-character hex key
- `EXIST_64_CHAR_HEX_KEY` → Generated 64-character hex key
- `EXIST_DEFAULT_EMAIL` → Value from `$EXIST_DEFAULT_EMAIL` environment variable
- `EXIST_DEFAULT_USERNAME` → Value from `$EXIST_DEFAULT_USERNAME` environment variable

**Functions:**
- `process_env_generated_file(file)` - Process a single .env.generated file
- `process_all_env_generated_files(search_dir, max_depth)` - Process all .env.generated files in directory
- `show_env_status()` - Display current environment variable values

## Integration

These scripts are designed to be sourced by the main `existential.sh` script in the project root, providing modular functionality for environment file processing and other automation tasks.

The generator scripts are specifically designed to replace placeholder variables in `.env.example` files:
- `EXIST_24_CHAR_PASSWORD` → Use `generate_password.sh` or `process_env_placeholders.sh`
- `EXIST_32_CHAR_HEX_KEY` → Use `generate_hex_key.sh 32` or `process_env_placeholders.sh`
- `EXIST_64_CHAR_HEX_KEY` → Use `generate_hex_key.sh 64` or `process_env_placeholders.sh`
- `EXIST_DEFAULT_EMAIL` → Set environment variable, use `process_env_placeholders.sh`
- `EXIST_DEFAULT_USERNAME` → Set environment variable, use `process_env_placeholders.sh`

**Complete Workflow:**
1. `find_env_examples.sh` - Find all .env.example files (with depth control)
2. `create_env_generated.sh` - Create .env.generated files from .env.example (with depth control)
3. `process_env_placeholders.sh` - Replace placeholders with actual values (with depth control)

**Depth Behavior Examples:**
```
. (root)                    ← Depth 0: 1 file (.env.example)
├── services/               ← Depth 1: 0 files (no .env.example here)
│   ├── nocoDB/             ← Depth 2: 17 files (.env.example files)
│   ├── appsmith/           
│   └── ...
├── hosting/                ← Depth 1: 0 files
│   ├── portainer/          ← Depth 2: included in 17 files
│   └── ...
└── .env.example            

# Usage examples:
find_env_examples "." 0     # Only root .env.example (1 file)
find_env_examples "." 1     # No files (no .env.example at depth 1)  
find_env_examples "." 2     # All service .env.example files (17 files)
```

## Adding New Scripts

When creating new shell scripts for the Existential project:
1. Place them in this directory (`automations/existential/`)
2. Use basic bash operations for cross-platform compatibility
3. Include proper error handling and documentation
4. Make them sourceable by other scripts when appropriate
5. Update this README with new script descriptions
