#!/bin/bash

# Existential Script - Unified Example File Processing
# This script provides a comprehensive workflow for processing ALL .example files systematically
# It combines environment file processing with any other .example file types

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$SCRIPT_DIR/automations/existential"

# Save the original script directory before sourcing other scripts
ORIGINAL_SCRIPT_DIR="$SCRIPT_DIR"

# Source the unified example processor
if [ -f "$AUTOMATION_DIR/unified_example_processor.sh" ]; then
    source "$AUTOMATION_DIR/unified_example_processor.sh"
else
    echo "❌ Error: unified_example_processor.sh not found in $AUTOMATION_DIR/"
    exit 1
fi

# Source service management for docker-compose generation
if [ -f "$AUTOMATION_DIR/service_enablement.sh" ]; then
    source "$AUTOMATION_DIR/service_enablement.sh"
else
    echo "❌ Error: service_enablement.sh not found in $AUTOMATION_DIR/"
    exit 1
fi

# Restore the original script directory after all sourcing
SCRIPT_DIR="$ORIGINAL_SCRIPT_DIR"

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

# Main unified workflow that processes ALL example files systematically
run_existential_workflow() {
    local variables_processed=0
    local files_processed=0
    
    echo "🚀 Existential - Unified Example File Processing"
    echo "================================================"
    echo ""
    
    # Step 0: Change to script directory for relative path operations
    cd "$SCRIPT_DIR" || {
        echo "❌ Error: Cannot change to script directory: $SCRIPT_DIR"
        exit 1
    }
    
    # Step 1: Process ALL .example files systematically
    echo "📋 Processing ALL .example files in the project..."
    echo "=================================================="
    
    if process_all_example_files "." 2 "*.example" true "$FORCE_OVERWRITE"; then
        echo "✅ All .example files processed successfully!"
    else
        echo "⚠️  Some .example files had processing issues - check output above"
    fi
    
    echo ""
    
    # Step 1.5: Source the root .env file to load environment variables for service enablement
    if [ -f ".env" ]; then
        echo "📋 Loading environment variables from .env..."
        echo "=============================================="
        set -a  # Automatically export all variables
        source ".env"
        set +a  # Turn off automatic export
        echo "✅ Environment variables loaded successfully!"
        echo ""
    else
        echo "⚠️  No .env file found - service enablement may not work correctly"
        echo ""
    fi
    
    # Step 2: Generate docker-compose.yml from enabled services
    echo "📋 Generating docker-compose.yml from enabled services..."
    echo "======================================================="
    
    local compose_output="docker-compose.yml"
    local generate_diff=false
    
    # Check if docker-compose.yml already exists - use .generated.yml instead
    if [ -f "$compose_output" ]; then
        echo "ℹ️  Existing $compose_output found, generating docker-compose.generated.yml instead"
        compose_output="docker-compose.generated.yml"
        generate_diff=true
    fi
    
    if (set -a; source ".env" 2>/dev/null; "$AUTOMATION_DIR/service_enablement.sh" generate-compose "$compose_output") > /dev/null 2>&1; then
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
    
    # Step 3: Report final status
    echo ""
    echo "🎉 Existential Processing Complete!"
    echo "=================================="
    echo ""
    
    # Count the results
    local env_files_count=$(find . -maxdepth 3 -name ".env" -not -path "*/graveyard/*" 2>/dev/null | wc -l)
    local example_files_count=$(find . -maxdepth 3 -name "*.example" -not -path "*/graveyard/*" 2>/dev/null | wc -l)
    local generated_files_count=$(find . -maxdepth 3 -name "*" -not -name "*.example" -not -path "*/graveyard/*" 2>/dev/null | while read -r file; do
        local example_counterpart="${file}.example"
        if [ -f "$example_counterpart" ]; then
            echo "$file"
        fi
    done | wc -l)
    
    echo "📊 Processing Summary:"
    echo "  • Example files found: $example_files_count"
    echo "  • Generated/updated files: $generated_files_count"
    echo "  • Environment files: $env_files_count"
    echo "  • Top-level .env: $([ -f ".env" ] && echo "✅ Ready" || echo "❌ Not found")"
    echo "  • Docker Compose: $([ -f "$compose_output" ] && echo "✅ Generated ($compose_output)" || echo "❌ Not generated")"
    if [ "$generate_diff" = true ] && [ -f "docker-compose.diff.yml" ]; then
        echo "  • Diff file: ✅ Generated (docker-compose.diff.yml)"
    fi
    echo ""
    
    # Show service enablement status if .env file exists
    if [ -f ".env" ]; then
        echo "🔧 Service Configuration:"
        echo "========================="
        show_service_status
    fi
    
    echo ""
    echo "✅ Your entire project configuration is now processed and ready to use!"
    echo ""
    echo "💡 What happened:"
    echo "  • All .example files in your project were found and processed"
    echo "  • Counterpart files were created (removing .example extension)"  
    echo "  • EXIST_CLI placeholders were replaced interactively"
    echo "  • EXIST_* placeholders were replaced automatically"
    echo "  • Root-level .env was sourced to load environment variables"
    echo "  • Docker Compose configuration was generated from enabled services"
    echo ""
    echo "💡 Next steps:"
    echo "  • Run 'source .env' in other terminals to load top-level variables"
    echo "  • Use 'docker compose up' to start your services"
    echo "  • Use './automations/existential/service_enablement.sh' to manage services"
    echo "  • Check individual service directories for their specific .env files"
    echo ""
    
    return 0
}

# Specialized function to process only .env.example files (backward compatibility)
run_env_only_workflow() {
    echo "🚀 Environment-Only Processing Workflow"
    echo "======================================="
    echo ""
    
    # Change to script directory
    cd "$SCRIPT_DIR" || {
        echo "❌ Error: Cannot change to script directory: $SCRIPT_DIR"
        exit 1
    }
    
    # Process only .env.example files
    if process_all_example_files "." 2 "*.env.example" true "$FORCE_OVERWRITE"; then
        echo "✅ All .env.example files processed successfully!"
    else
        echo "⚠️  Some .env.example files had processing issues"
    fi
    
    return 0
}

# Function to process specific file patterns
process_specific_pattern() {
    local pattern="$1"
    local depth="${2:-2}"
    local description="${3:-$pattern files}"
    
    echo "🚀 Processing $description"
    echo "=================================="
    echo ""
    
    cd "$SCRIPT_DIR" || {
        echo "❌ Error: Cannot change to script directory: $SCRIPT_DIR"
        exit 1
    }
    
    if process_all_example_files "." "$depth" "$pattern" true "$FORCE_OVERWRITE"; then
        echo "✅ All $description processed successfully!"
    else
        echo "⚠️  Some $description had processing issues"
    fi
    
    return 0
}

# Function to show available example files by type
show_example_file_types() {
    echo "📋 Example File Types in Project"
    echo "================================"
    
    cd "$SCRIPT_DIR" || {
        echo "❌ Error: Cannot change to script directory: $SCRIPT_DIR"
        return 1
    }
    
    # Find all example files and group by extension
    local extensions=()
    while IFS= read -r file; do
        # Extract the extension before .example
        local basename=$(basename "$file")
        local extension="${basename%.example}"
        extension="${extension##*.}"
        extensions+=("$extension")
    done < <(find . -name "*.example" -not -path "*/graveyard/*" 2>/dev/null)
    
    # Count occurrences of each extension
    local extension_counts=()
    for ext in $(printf '%s\n' "${extensions[@]}" | sort | uniq); do
        local count=$(printf '%s\n' "${extensions[@]}" | grep -c "^$ext$")
        extension_counts+=("$ext:$count")
    done
    
    echo ""
    echo "File types found:"
    for item in "${extension_counts[@]}"; do
        local ext="${item%:*}"
        local count="${item#*:}"
        printf "  %-15s %3d files\n" ".$ext.example" "$count"
    done
    
    echo ""
    echo "Usage examples:"
    echo "  $0 env-only          # Process only .env.example files"
    echo "  $0 pattern '*.yml.example'  # Process only .yml.example files"
    echo "  $0 pattern '*.json.example' # Process only .json.example files"
    echo ""
}
    
# Global variables for options
FORCE_OVERWRITE=false

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Parse options first
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_OVERWRITE=true
                shift
                ;;
            *)
                # Not an option, break and process as action
                break
                ;;
        esac
    done
    
    action="${1:-workflow}"
    
    case "$action" in
        "--help"|"-h")
            echo "Existential - Unified Example File Processor"
            echo "============================================"
            echo ""
            echo "Usage: $0 [OPTIONS] [ACTION] [ACTION_OPTIONS...]"
            echo ""
            echo "OPTIONS (must come before ACTION):"
            echo "  --force               Force overwrite existing files (skip safety check)"
            echo ""
            echo "ACTIONS:"
            echo "  workflow              Complete workflow for ALL .example files (default)"
            echo "  env-only              Process only .env.example files"
            echo "  pattern PATTERN       Process files matching specific pattern"
            echo "  types                 Show all example file types in project"
            echo "  services [cmd]        Manage service enablement"
            echo "  generate-compose      Generate docker-compose.yml from enabled services"
            echo "  profiles              Show available Docker Compose profiles"
            echo "  --help, -h            Show this help message"
            echo ""
            echo "PATTERN EXAMPLES:"
            echo "  '*.env.example'   Only environment files"
            echo "  '*.yml.example'   Only YAML configuration files"
            echo "  '*.json.example'  Only JSON configuration files"
            echo "  '*.pem.example'   Only certificate/key files"
            echo ""
            echo "UNIFIED WORKFLOW (default):"
            echo "  1. Find ALL .example files in project (excluding graveyard/)"
            echo "  2. Process root-level .example files first"
            echo "  3. Create counterpart files (remove .example extension)"
            echo "  4. Process EXIST_CLI placeholders interactively"
            echo "  5. Process EXIST_* placeholders automatically"
            echo "  6. Source root-level .env to load environment variables"
            echo "  7. Process service-level .example files"
            echo "  8. Generate docker-compose.yml from enabled services"
            echo "  9. Generate diff file if docker-compose.yml exists"
            echo " 10. Report comprehensive summary"
            echo ""
            echo "Features:"
            echo "  • Processes ANY file type with .example extension"
            echo "  • Never overwrites existing files (unless --force is used)"
            echo "  • Root-level files processed first and sourced"
            echo "  • Interactive CLI placeholder replacement"
            echo "  • Automatic password/key generation"
            echo "  • Service enablement integration"
            echo "  • Docker Compose generation with diff tracking"
            echo ""
            echo "Examples:"
            echo "  $0                          # Process all .example files"
            echo "  $0 --force                  # Process all files, overwrite existing"
            echo "  $0 workflow                 # Same as first example (explicit)"
            echo "  $0 --force env-only         # Only .env.example files, overwrite existing"
            echo "  $0 pattern '*.yml.example'  # Only YAML files"
            echo "  $0 --force pattern '*.yml.example'  # Only YAML files, overwrite existing"
            echo "  $0 types                    # Show what file types exist"
            echo "  $0 services status          # Show service enablement status"
            echo ""
            ;;
        "workflow")
            run_existential_workflow
            ;;
        "env-only")
            run_env_only_workflow
            ;;
        "pattern")
            pattern="$2"
            depth="${3:-2}"
            if [ -z "$pattern" ]; then
                echo "❌ Error: Pattern is required"
                echo "Usage: $0 pattern 'PATTERN' [DEPTH]"
                echo "Example: $0 pattern '*.yml.example' 2"
                exit 1
            fi
            process_specific_pattern "$pattern" "$depth" "$pattern"
            ;;
        "types")
            show_example_file_types
            ;;
        "services")
            shift  # Remove 'services' from arguments
            "$AUTOMATION_DIR/service_enablement.sh" "$@"
            ;;
        "generate-compose")
            echo "Generating merged docker-compose.yml from enabled services..."
            output_file="${2:-docker-compose.yml}"
            generate_diff=false
            
            # Check if docker-compose.yml already exists and no custom output specified
            if [ -f "docker-compose.yml" ] && [ "$output_file" = "docker-compose.yml" ]; then
                echo "ℹ️  Existing docker-compose.yml found, generating docker-compose.generated.yml instead"
                output_file="docker-compose.generated.yml"
                generate_diff=true
            fi
            
            if (set -a; source ".env" 2>/dev/null; "$AUTOMATION_DIR/service_enablement.sh" generate-compose "$output_file"); then
                echo "Generated merged docker-compose.yml as: $output_file"
                
                # Generate diff file if requested
                if [ "$generate_diff" = true ] && [ -f "docker-compose.yml" ] && [ -f "$output_file" ]; then
                    diff_file="docker-compose.diff.yml"
                    echo ""
                    echo "🔍 Generating difference file: $diff_file"
                    
                    if diff -u "docker-compose.yml" "$output_file" > "$diff_file" 2>/dev/null; then
                        # No differences found
                        echo "NO CHANGES" > "$diff_file"
                        echo "ℹ️  No changes detected between docker-compose.yml and $output_file"
                    else
                        # Differences found
                        change_count=$(grep -c "^[+-]" "$diff_file" 2>/dev/null || echo "0")
                        echo "📊 Generated $diff_file with $change_count line changes"
                    fi
                fi
            fi
            ;;
        "profiles")
            "$AUTOMATION_DIR/service_enablement.sh" profiles
            ;;
        *)
            echo "❌ Unknown action: $action"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
fi

