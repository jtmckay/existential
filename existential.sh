#!/bin/bash

# Existential Script - Complete Environment File Processing Workflow
# This script provides a comprehensive environment file setup and processing workflow

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$SCRIPT_DIR/automations/existential"

# Save the original script directory before sourcing other scripts
ORIGINAL_SCRIPT_DIR="$SCRIPT_DIR"

# Source required scripts
if [ -f "$AUTOMATION_DIR/find_env_examples.sh" ]; then
    source "$AUTOMATION_DIR/find_env_examples.sh"
else
    echo "❌ Error: find_env_examples.sh not found in $AUTOMATION_DIR/"
    exit 1
fi

if [ -f "$AUTOMATION_DIR/create_env_files.sh" ]; then
    source "$AUTOMATION_DIR/create_env_files.sh"
else
    echo "❌ Error: create_env_files.sh not found in $AUTOMATION_DIR/"
    exit 1
fi

if [ -f "$AUTOMATION_DIR/interactive_cli_replacer.sh" ]; then
    source "$AUTOMATION_DIR/interactive_cli_replacer.sh"
else
    echo "❌ Error: interactive_cli_replacer.sh not found in $AUTOMATION_DIR/"
    exit 1
fi

# Restore the original script directory
SCRIPT_DIR="$ORIGINAL_SCRIPT_DIR"

if [ -f "$AUTOMATION_DIR/process_env_placeholders.sh" ]; then
    source "$AUTOMATION_DIR/process_env_placeholders.sh"
else
    echo "❌ Error: process_env_placeholders.sh not found in $AUTOMATION_DIR/"
    exit 1
fi

if [ -f "$AUTOMATION_DIR/service_enablement.sh" ]; then
    source "$AUTOMATION_DIR/service_enablement.sh"
else
    echo "❌ Error: service_enablement.sh not found in $AUTOMATION_DIR/"
    exit 1
fi

# Restore the original script directory after all sourcing
SCRIPT_DIR="$ORIGINAL_SCRIPT_DIR"

# Function to check if file has EXIST_CLI placeholders
has_exist_cli_placeholders() {
    local file="$1"
    [ -f "$file" ] && grep -q "EXIST_CLI" "$file" 2>/dev/null
}

# Function to check if file has EXIST_* placeholders (any kind)
has_exist_placeholders() {
    local file="$1"
    [ -f "$file" ] && grep -q "EXIST_" "$file" 2>/dev/null
}

# Function to count variables in a .env file
count_env_variables() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "0"
        return
    fi
    
    # Count lines that look like variable assignments (VARIABLE=value)
    # Exclude comments and empty lines
    grep -E '^[A-Z_][A-Z0-9_]*=' "$file" 2>/dev/null | wc -l
}

# Function to copy .env.example to .env if .env doesn't exist
copy_env_example_if_needed() {
    local example_file="$1"
    local env_file="${example_file%.example}"
    
    if [ ! -f "$env_file" ]; then
        if cp "$example_file" "$env_file"; then
            echo "✅ Created $env_file from $example_file"
            return 0
        else
            echo "❌ Failed to create $env_file from $example_file"
            return 1
        fi
    else
        echo "ℹ️  $env_file already exists, skipping"
        return 0
    fi
}

# Main comprehensive workflow
run_existential_workflow() {
    local variables_processed=0
    local files_processed=0
    
    echo "🚀 Welcome to Existential - Environment Setup Workflow"
    echo "======================================================"
    echo ""
    
    # Step 0: Change to script directory for relative path operations
    cd "$SCRIPT_DIR" || {
        echo "❌ Error: Cannot change to script directory: $SCRIPT_DIR"
        exit 1
    }
    
    # Step 1: Find the top level .env.example
    echo "📋 Step 1: Finding top-level .env.example file..."
    local top_level_env_example
    if [ -f ".env.example" ]; then
        top_level_env_example=".env.example"
        echo "✅ Found top-level .env.example"
    else
        echo "⚠️  No top-level .env.example found, skipping top-level processing"
        top_level_env_example=""
    fi
    
    # Step 2: Copy .env.example to .env (if it doesn't exist)
    if [ -n "$top_level_env_example" ]; then
        echo ""
        echo "📋 Step 2: Creating top-level .env file..."
        copy_env_example_if_needed "$top_level_env_example"
        local top_level_env=".env"
    fi
    
    # Step 3: Run interactive CLI replacer on top-level .env file
    if [ -n "$top_level_env_example" ] && [ -f "$top_level_env" ]; then
        echo ""
        echo "📋 Step 3: Processing top-level EXIST_CLI placeholders..."
        
        if has_exist_cli_placeholders "$top_level_env"; then
            echo "🔧 Found EXIST_CLI placeholders in $top_level_env"
            if process_file_interactive "$top_level_env"; then
                ((files_processed++))
            fi
        else
            echo "ℹ️  No EXIST_CLI placeholders found in $top_level_env"
        fi
    fi
    
    # Step 4: Run placeholder processing on top-level .env file
    if [ -n "$top_level_env_example" ] && [ -f "$top_level_env" ]; then
        echo ""
        echo "📋 Step 4: Processing top-level EXIST_* placeholders..."
        
        if has_exist_placeholders "$top_level_env"; then
            local pre_count=$(count_env_variables "$top_level_env")
            echo "🔧 Found EXIST_* placeholders in $top_level_env"
            if process_env_generated_file "$top_level_env"; then
                local post_count=$(count_env_variables "$top_level_env")
                local processed_vars=$((post_count - pre_count))
                if [ $processed_vars -gt 0 ]; then
                    variables_processed=$((variables_processed + processed_vars))
                fi
                ((files_processed++))
            fi
        else
            echo "ℹ️  No EXIST_* placeholders found in $top_level_env"
        fi
    fi
    
    # Step 5: Source the top-level .env file
    if [ -n "$top_level_env_example" ] && [ -f "$top_level_env" ]; then
        echo ""
        echo "📋 Step 5: Loading top-level environment variables..."
        
        # Count variables before sourcing
        local env_var_count=$(count_env_variables "$top_level_env")
        
        if set -a && source "$top_level_env" && set +a; then
            echo "✅ Successfully loaded $env_var_count environment variables from $top_level_env"
            variables_processed=$((variables_processed + env_var_count))
        else
            echo "❌ Failed to source $top_level_env"
        fi
    fi
    
    # Step 6: Find all .env.example files at depth 2 (excluding top level)
    echo ""
    echo "📋 Step 6: Finding service-level .env.example files..."
    
    local service_env_examples=()
    mapfile -t service_env_examples < <(find_env_examples "." 2)
    
    # Filter out the top-level .env.example if it exists
    local filtered_service_examples=()
    for file in "${service_env_examples[@]}"; do
        if [ "$file" != "./.env.example" ] && [ "$file" != ".env.example" ]; then
            filtered_service_examples+=("$file")
        fi
    done
    
    echo "✅ Found ${#filtered_service_examples[@]} service-level .env.example files"
    
    # Copy .env.example to .env for each service file
    if [ ${#filtered_service_examples[@]} -gt 0 ]; then
        echo ""
        echo "📋 Step 6b: Creating service-level .env files..."
        
        for example_file in "${filtered_service_examples[@]}"; do
            copy_env_example_if_needed "$example_file"
        done
    fi
    
    # Step 7: Run interactive CLI replacer for all service-level .env files
    echo ""
    echo "📋 Step 7: Processing service-level EXIST_CLI placeholders..."
    
    local service_env_files=()
    for example_file in "${filtered_service_examples[@]}"; do
        local env_file="${example_file%.example}"
        if [ -f "$env_file" ]; then
            service_env_files+=("$env_file")
        fi
    done
    
    if [ ${#service_env_files[@]} -gt 0 ]; then
        local files_with_cli=()
        for env_file in "${service_env_files[@]}"; do
            if has_exist_cli_placeholders "$env_file"; then
                files_with_cli+=("$env_file")
            fi
        done
        
        if [ ${#files_with_cli[@]} -gt 0 ]; then
            echo "🔧 Found EXIST_CLI placeholders in ${#files_with_cli[@]} service files"
            process_files_interactive "${files_with_cli[@]}"
            files_processed=$((files_processed + ${#files_with_cli[@]}))
        else
            echo "ℹ️  No EXIST_CLI placeholders found in service-level .env files"
        fi
    else
        echo "ℹ️  No service-level .env files to process"
    fi
    
    # Step 8: Run placeholder processing on all service-level .env files
    echo ""
    echo "📋 Step 8: Processing service-level EXIST_* placeholders..."
    
    if [ ${#service_env_files[@]} -gt 0 ]; then
        local files_with_placeholders=()
        for env_file in "${service_env_files[@]}"; do
            if has_exist_placeholders "$env_file"; then
                files_with_placeholders+=("$env_file")
            fi
        done
        
        if [ ${#files_with_placeholders[@]} -gt 0 ]; then
            echo "🔧 Found EXIST_* placeholders in ${#files_with_placeholders[@]} service files"
            for env_file in "${files_with_placeholders[@]}"; do
                local pre_count=$(count_env_variables "$env_file")
                if process_env_generated_file "$env_file"; then
                    local post_count=$(count_env_variables "$env_file")
                    local processed_vars=$((post_count - pre_count))
                    if [ $processed_vars -gt 0 ]; then
                        variables_processed=$((variables_processed + processed_vars))
                    fi
                fi
            done
            files_processed=$((files_processed + ${#files_with_placeholders[@]}))
        else
            echo "ℹ️  No EXIST_* placeholders found in service-level .env files"
        fi
    else
        echo "ℹ️  No service-level .env files to process"
    fi
    
    # Step 9: Generate docker-compose.yml from enabled services
    echo ""
    echo "📋 Step 9: Generating docker-compose.yml from enabled services..."
    
    local compose_output="docker-compose.yml"
    local generate_diff=false
    
    # Check if docker-compose.yml already exists
    if [ -f "$compose_output" ]; then
        echo "ℹ️  Existing $compose_output found, generating docker-compose.generated.yml instead"
        compose_output="docker-compose.generated.yml"
        generate_diff=true
    fi
    
    if "$AUTOMATION_DIR/service_enablement.sh" generate-compose "$compose_output" > /dev/null 2>&1; then
        if [ -f "$compose_output" ]; then
            local service_count=$(grep -c "^  [a-zA-Z]" "$compose_output" 2>/dev/null || echo "0")
            echo "✅ Successfully generated $compose_output with $service_count services"
            echo "📄 Docker Compose file ready for: docker compose up"
            
            # Generate diff file if requested
            if [ "$generate_diff" = true ]; then
                local diff_file="docker-compose.diff.yml"
                echo ""
                echo "🔍 Generating difference file: $diff_file"
                
                if diff -u "docker-compose.yml" "$compose_output" > "$diff_file" 2>/dev/null; then
                    # No differences found
                    echo "NO CHANGES" > "$diff_file"
                    echo "ℹ️  No changes detected between docker-compose.yml and $compose_output"
                else
                    # Differences found
                    local change_count=$(grep -c "^[+-]" "$diff_file" 2>/dev/null || echo "0")
                    echo "📊 Generated $diff_file with $change_count line changes"
                fi
            fi
        else
            echo "⚠️  Docker Compose generation completed but no output file created"
        fi
    else
        echo "❌ Failed to generate Docker Compose file"
        echo "💡 Try running: ./automations/existential/service_enablement.sh generate-compose"
    fi
    
    # Step 10: Thank the user and report results
    echo ""
    echo "🎉 Thank you for using Existential!"
    echo "=================================="
    echo ""
    echo "📊 Processing Summary:"
    echo "  • Files processed: $files_processed"
    echo "  • Variables configured: $variables_processed"
    echo "  • Top-level .env: $([ -f "$top_level_env" ] && echo "✅ Ready" || echo "❌ Not found")"
    echo "  • Service .env files: ${#service_env_files[@]}"
    echo "  • Docker Compose: $([ -f "$compose_output" ] && echo "✅ Generated ($compose_output)" || echo "❌ Not generated")"
    if [ "$generate_diff" = true ] && [ -f "docker-compose.diff.yml" ]; then
        echo "  • Diff file: ✅ Generated (docker-compose.diff.yml)"
    fi
    echo ""
    
    # Show service enablement status if .env file exists
    if [ -f "$top_level_env" ]; then
        echo "🔧 Service Configuration:"
        echo "========================="
        show_service_status
    fi
    
    if [ $files_processed -gt 0 ]; then
        echo "✅ Your environment is now configured and ready to use!"
        echo ""
        echo "💡 Tips:"
        echo "  • Your environment variables are loaded in this shell session"
        echo "  • Run 'source .env' in other terminals to load the top-level variables"
        echo "  • Each service directory has its own .env file for service-specific configuration"
        echo "  • Use './automations/existential/service_enablement.sh' to manage service configuration"
    else
        echo "ℹ️  No environment files needed processing - you're all set!"
    fi
    
    echo ""
    return 0
}

# Legacy functions for backward compatibility
get_env_example_files() {
    local search_dir="${1:-.}"
    mapfile -t env_example_files < <(find_env_examples "$search_dir")
    printf '%s\n' "${env_example_files[@]}"
}

process_env_files() {
    local search_dir="${1:-.}"
    local action="${2:-list}"
    
    echo "Processing .env files in: $search_dir"
    echo "======================================="
    
    case "$action" in
        "list")
            mapfile -t env_files < <(get_env_example_files "$search_dir")
            
            echo "Found ${#env_files[@]} .env.example files:"
            echo ""
            
            for i in "${!env_files[@]}"; do
                printf "%2d: %s\n" $((i+1)) "${env_files[i]}"
            done
            
            echo ""
            echo "Array variable 'env_files' contains all found files."
            ;;
        "interactive-cli")
            echo "Starting interactive EXIST_CLI replacement..."
            process_env_files_interactive "$search_dir" 2
            ;;
        "services")
            echo "Service enablement management..."
            shift  # Remove 'services' from arguments
            "$AUTOMATION_DIR/service_enablement.sh" "$@"
            ;;
        "workflow")
            run_existential_workflow
            ;;
        *)
            echo "Unknown action: $action"
            echo "Available actions: list, interactive-cli, services, workflow"
            return 1
            ;;
    esac
    
    return 0
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    action="${1:-workflow}"
    search_dir="${2:-.}"
    
    case "$action" in
        "--help"|"-h")
            echo "Existential - Complete Environment Setup Workflow"
            echo "================================================="
            echo ""
            echo "Usage: $0 [ACTION] [DIRECTORY]"
            echo ""
            echo "ACTIONS:"
            echo "  workflow          Complete environment setup workflow (default)"
            echo "  list              List all .env.example files"
            echo "  interactive-cli   Interactively replace EXIST_CLI placeholders only"
            echo "  services [cmd]    Manage service enablement (see services --help)"
            echo "  generate-compose  Generate merged docker-compose.yml from enabled services"
            echo "  profiles          Show available Docker Compose profiles"
            echo "  --help, -h        Show this help message"
            echo ""
            echo "ARGUMENTS:"
            echo "  DIRECTORY         Directory to search (default: current directory)"
            echo ""
            echo "WORKFLOW STEPS (when using 'workflow' action):"
            echo "  1. Find top-level .env.example file"
            echo "  2. Create .env from .env.example (if .env doesn't exist)"
            echo "  3. Interactively replace EXIST_CLI placeholders in .env"
            echo "  4. Automatically replace other EXIST_* placeholders in .env"
            echo "  5. Source .env to load variables into shell environment"
            echo "  6. Find and create service-level .env files (depth 2)"
            echo "  7. Interactively replace EXIST_CLI in service .env files"
            echo "  8. Automatically replace EXIST_* in service .env files"
            echo "  9. Generate docker-compose.yml from enabled services (or .generated.yml if exists)"
            echo " 10. Report completion summary and thank you"
            echo ""
            echo "Examples:"
            echo "  $0                        # Run complete workflow"
            echo "  $0 workflow               # Run complete workflow"
            echo "  $0 list services/         # List .env.example files in services/"
            echo "  $0 interactive-cli        # Only process EXIST_CLI placeholders"
            echo "  $0 services status        # Show which services are enabled/disabled"
            echo "  $0 services enabled       # List only enabled services"
            echo "  $0 generate-compose       # Generate docker-compose.generated.yml"
            echo "  $0 generate-compose prod.yml  # Generate custom filename"
            echo "  $0 profiles               # Show available Docker Compose profiles"
            echo ""
            echo "Features:"
            echo "  • Never overwrites existing .env files"
            echo "  • Shows context comments for interactive prompts"
            echo "  • Automatically generates secure passwords and keys"
            echo "  • Loads environment variables for immediate use"
            echo "  • Processes both top-level and service configurations"
            echo "  • Individual service enable/disable control"
            echo "  • Automatic Docker Compose generation with diff tracking"
            ;;
        "services")
            shift  # Remove 'services' from arguments
            "$AUTOMATION_DIR/service_enablement.sh" "$@"
            ;;
        "generate-compose")
            echo "Generating merged docker-compose.yml from enabled services..."
            output_file="${2:-docker-compose.generated.yml}"
            "$AUTOMATION_DIR/service_enablement.sh" generate-compose "$output_file"
            ;;
        "profiles")
            "$AUTOMATION_DIR/service_enablement.sh" profiles
            ;;
        *)
            search_dir="${2:-.}"
            process_env_files "$search_dir" "$action"
            ;;
    esac
fi

