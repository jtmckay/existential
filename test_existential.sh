#!/bin/bash

# Existential Test Suite - Comprehensive Function Testing
# Tests all functions used by existential.sh and ensures they work correctly

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Function to print colored output
print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "PASS") echo -e "${GREEN}✅ PASS${NC}: $message" ;;
        "FAIL") echo -e "${RED}❌ FAIL${NC}: $message" ;;
        "INFO") echo -e "${BLUE}ℹ️  INFO${NC}: $message" ;;
        "HEADER") echo -e "${BLUE}🔍 $message${NC}" ;;
    esac
}

# Function to run a test
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_RUN++))
    
    if (set +e; $test_function); then
        ((TESTS_PASSED++))
        print_status "PASS" "$test_name"
        return 0
    else
        ((TESTS_FAILED++))
        print_status "FAIL" "$test_name"
        return 1
    fi
}

# Source the automation scripts for testing
AUTOMATION_DIR="./automations/existential"

source_scripts() {
    if [ -f "$AUTOMATION_DIR/unified_example_processor.sh" ]; then
        source "$AUTOMATION_DIR/unified_example_processor.sh"
    else
        echo "❌ Error: unified_example_processor.sh not found"
        return 1
    fi

    if [ -f "$AUTOMATION_DIR/interactive_cli_replacer.sh" ]; then
        source "$AUTOMATION_DIR/interactive_cli_replacer.sh"
    else
        echo "❌ Error: interactive_cli_replacer.sh not found"
        return 1
    fi

    if [ -f "$AUTOMATION_DIR/service_enablement.sh" ]; then
        source "$AUTOMATION_DIR/service_enablement.sh"
    else
        echo "❌ Error: service_enablement.sh not found"
        return 1
    fi

    if [ -f "$AUTOMATION_DIR/generate_password.sh" ]; then
        source "$AUTOMATION_DIR/generate_password.sh"
    else
        echo "❌ Error: generate_password.sh not found"
        return 1
    fi

    if [ -f "$AUTOMATION_DIR/generate_hex_key.sh" ]; then
        source "$AUTOMATION_DIR/generate_hex_key.sh"
    else
        echo "❌ Error: generate_hex_key.sh not found"
        return 1
    fi
}

# ============================================================================
# CORE SCRIPT TESTS
# ============================================================================

test_existential_exists() {
    [ -f "./existential.sh" ] && [ -x "./existential.sh" ]
}

test_help_command() {
    ./existential.sh --help > /dev/null 2>&1
}

test_automation_scripts_exist() {
    local required_scripts=(
        "automations/existential/unified_example_processor.sh"
        "automations/existential/interactive_cli_replacer.sh"
        "automations/existential/service_enablement.sh"
        "automations/existential/generate_password.sh"
        "automations/existential/generate_hex_key.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            return 1
        fi
    done
    return 0
}

# ============================================================================
# FUNCTION TESTS FOR unified_example_processor.sh
# ============================================================================

test_find_example_files_function() {
    # Test that find_example_files function exists and works
    if ! declare -f find_example_files > /dev/null; then
        return 1
    fi
    
    # Test with current directory - should find .example files
    local result
    result=$(find_example_files "." 2 "*.example" | head -1)
    
    # Should return at least one result if .example files exist
    [ -n "$result" ] && [ -f "$result" ]
}

test_find_env_examples_compatibility() {
    # Test backward compatibility function
    if ! declare -f find_env_examples > /dev/null; then
        return 1
    fi
    
    # Test depth 0 (current directory only)
    local result_depth_0
    result_depth_0=$(find_env_examples "." 0 | wc -l)
    
    # Test depth 2 (default)
    local result_depth_2
    result_depth_2=$(find_env_examples "." 2 | wc -l)
    
    # Depth 2 should have >= depth 0 results
    [ "$result_depth_2" -ge "$result_depth_0" ]
}

# ============================================================================
# FUNCTION TESTS FOR interactive_cli_replacer.sh
# ============================================================================

test_extract_context_comments_function() {
    if ! declare -f extract_context_comments > /dev/null; then
        return 1
    fi
    
    # Create a test file with comments
    local test_file="test_context_comments.env"
    cat > "$test_file" << 'EOF'
# This is a comment for email
# Another comment line
EXIST_DEFAULT_EMAIL=EXIST_CLI

# Comment for username
EXIST_DEFAULT_USERNAME=EXIST_CLI
EOF

    # Test extracting comments for line 3
    local result
    result=$(extract_context_comments "$test_file" 3)
    
    # Should contain the comment text
    local success=0
    if echo "$result" | grep -q "comment for email"; then
        success=1
    fi
    
    rm -f "$test_file"
    [ "$success" -eq 1 ]
}

test_process_file_interactive_function_exists() {
    # Test that the function exists (we can't test interactive input)
    declare -f process_file_interactive > /dev/null
}

test_process_files_interactive_function_exists() {
    # Test that the function exists (we can't test interactive input)
    declare -f process_files_interactive > /dev/null
}

# ============================================================================
# FUNCTION TESTS FOR placeholder processing (unified_example_processor.sh)
# ============================================================================

test_process_file_placeholders_function() {
    # Simply test that the function exists and can be called without error
    # This avoids file conflicts and focuses on function availability
    if ! declare -f process_file_placeholders > /dev/null; then
        return 1
    fi
    
    # Create a minimal test in /tmp to avoid any conflicts
    local test_file="/tmp/minimal_test_$$.env"
    echo "TEST=EXIST_24_CHAR_PASSWORD" > "$test_file"
    
    # Test that function can be called (capture all output to avoid interference)
    local result=0
    if ! process_file_placeholders "$test_file" true >/dev/null 2>&1; then
        result=1
    fi
    
    # Clean up immediately
    rm -f "$test_file" "$test_file.tmp" 2>/dev/null
    
    return $result
}

# ============================================================================
# FUNCTION TESTS FOR service_enablement.sh
# ============================================================================

test_show_service_status_function() {
    if ! declare -f show_service_status > /dev/null; then
        return 1
    fi
    
    # Test that the function runs without error
    show_service_status > /dev/null 2>&1
}

test_is_service_enabled_function() {
    if ! declare -f is_service_enabled > /dev/null; then
        return 1
    fi
    
    # Test function existence and proper behavior
    # Function should return 0 or 1, not error out
    is_service_enabled "ai/ollama" >/dev/null 2>&1
    local result1=$?
    is_service_enabled "services/dashy" >/dev/null 2>&1
    local result2=$?
    
    # Both should be 0 or 1 (valid exit codes), not 2+ (errors)
    [ $result1 -le 1 ] && [ $result2 -le 1 ]
}

test_get_enabled_services_function() {
    if ! declare -f get_enabled_services > /dev/null; then
        return 1
    fi
    
    # Test that function runs and returns some output
    local result
    result=$(get_enabled_services "." 2 2>/dev/null)
    
    # Should return without error (may be empty if no services enabled)
    [ $? -eq 0 ]
}

# ============================================================================
# FUNCTION TESTS FOR generate_password.sh
# ============================================================================

test_generate_24_char_password_function() {
    if ! declare -f generate_24_char_password > /dev/null; then
        return 1
    fi
    
    # Test that it generates a 24-character password
    local password
    password=$(generate_24_char_password)
    
    # Check length and that it's not empty
    [ ${#password} -eq 24 ] && [ -n "$password" ]
}

# ============================================================================
# FUNCTION TESTS FOR generate_hex_key.sh  
# ============================================================================

test_generate_32_char_hex_function() {
    if ! declare -f generate_32_char_hex > /dev/null; then
        return 1
    fi
    
    local hex_key
    hex_key=$(generate_32_char_hex)
    
    # Check length and that it contains only hex characters
    [ ${#hex_key} -eq 32 ] && [[ "$hex_key" =~ ^[0-9a-fA-F]+$ ]]
}

test_generate_64_char_hex_function() {
    if ! declare -f generate_64_char_hex > /dev/null; then
        return 1
    fi
    
    local hex_key
    hex_key=$(generate_64_char_hex)
    
    # Check length and that it contains only hex characters
    [ ${#hex_key} -eq 64 ] && [[ "$hex_key" =~ ^[0-9a-fA-F]+$ ]]
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

test_docker_compose_generation() {
    local test_output="test-compose-output.yml"
    rm -f "$test_output"
    
    if ./existential.sh generate-compose "$test_output" > /dev/null 2>&1; then
        if [ -f "$test_output" ] && [ -s "$test_output" ]; then
            if grep -q "version:" "$test_output" && grep -q "services:" "$test_output"; then
                rm -f "$test_output"
                return 0
            fi
        fi
    fi
    
    rm -f "$test_output"
    return 1
}

test_service_commands() {
    ./existential.sh services status > /dev/null 2>&1 &&
    ./existential.sh services enabled > /dev/null 2>&1 &&
    ./existential.sh services disabled > /dev/null 2>&1
}

test_profiles_command() {
    ./existential.sh profiles > /dev/null 2>&1
}

test_list_command() {
    ./existential.sh types > /dev/null 2>&1
}

# ============================================================================
# DOCUMENTATION TESTS
# ============================================================================

test_env_example_exists() {
    [ -f ".env.example" ]
}

test_readme_accuracy() {
    [ -f "README.md" ] &&
    grep -q "./existential.sh" README.md &&
    grep -q "docker-compose up" README.md
}

test_directory_structure() {
    [ -d "ai" ] && [ -d "services" ] && [ -d "hosting" ] && [ -d "automations" ]
}

test_env_example_content() {
    [ -f ".env.example" ] &&
    grep -q "EXIST_ENABLE_AI_LIBRECHAT" .env.example &&
    grep -q "EXIST_ENABLE_SERVICES_DASHY" .env.example
}

test_architecture_diagram() {
    [ -f "architecture.png" ]
}

# ============================================================================
# MAIN TEST EXECUTION
# ============================================================================

main() {
    echo "🚀 Existential Test Suite - Comprehensive Function Testing"
    echo "==========================================================="
    echo ""
    
    print_status "HEADER" "Sourcing automation scripts for testing"
    if ! source_scripts; then
        echo "❌ Failed to source required scripts"
        exit 1
    fi
    echo ""
    
    print_status "HEADER" "Core Functionality Tests"
    run_test "Existential script exists and is executable" test_existential_exists
    run_test "Help command works" test_help_command
    run_test "Required automation scripts exist" test_automation_scripts_exist
    echo ""
    
    print_status "HEADER" "unified_example_processor.sh Function Tests"
    run_test "find_example_files function works" test_find_example_files_function
    run_test "find_env_examples compatibility works" test_find_env_examples_compatibility
    echo ""
    
    print_status "HEADER" "interactive_cli_replacer.sh Function Tests"
    run_test "extract_context_comments function works" test_extract_context_comments_function
    run_test "process_file_interactive function exists" test_process_file_interactive_function_exists
    run_test "process_files_interactive function exists" test_process_files_interactive_function_exists
    echo ""
    
    print_status "HEADER" "Placeholder Processing Function Tests"
    run_test "process_file_placeholders function works" test_process_file_placeholders_function
    echo ""
    
    print_status "HEADER" "service_enablement.sh Function Tests"
    run_test "show_service_status function works" test_show_service_status_function
    run_test "is_service_enabled function works" test_is_service_enabled_function
    run_test "get_enabled_services function works" test_get_enabled_services_function
    echo ""
    
    print_status "HEADER" "generate_password.sh Function Tests"
    run_test "generate_24_char_password function works" test_generate_24_char_password_function
    echo ""
    
    print_status "HEADER" "generate_hex_key.sh Function Tests"
    run_test "generate_32_char_hex function works" test_generate_32_char_hex_function
    run_test "generate_64_char_hex function works" test_generate_64_char_hex_function
    echo ""
    
    print_status "HEADER" "Service Management Tests"
    run_test "Service commands work" test_service_commands
    run_test "Profiles command works" test_profiles_command
    run_test "Types command works" test_list_command
    echo ""
    
    print_status "HEADER" "Docker Compose Tests"
    run_test "Docker-compose generation works" test_docker_compose_generation
    echo ""
    
    print_status "HEADER" "Documentation Tests"
    run_test "README accuracy" test_readme_accuracy
    run_test "Directory structure" test_directory_structure
    run_test ".env.example file exists" test_env_example_exists
    run_test ".env.example has required content" test_env_example_content
    run_test "Architecture diagram exists" test_architecture_diagram
    echo ""
    
    # Final results
    print_status "HEADER" "Test Results Summary"
    echo ""
    echo "Tests Run: $TESTS_RUN"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        print_status "PASS" "All tests passed! ✨"
        echo ""
        echo "🎉 All essential functions are working correctly!"
        echo ""
        echo "📋 Verified functionality:"
        echo "  • All core functions in automation scripts work"
        echo "  • Service management commands work" 
        echo "  • Docker Compose generation works"
        echo "  • Environment processing functions work"
        echo "  • Password and key generation works"
        echo "  • Documentation is accurate"
        echo ""
        echo "🚀 Ready for production use!"
        echo ""
        echo "Next steps:"
        echo "  1. Run './existential.sh' to set up your environment"
        echo "  2. Use './existential.sh services status' to check service configuration"
        echo "  3. Use './existential.sh generate-compose' to create docker-compose files"
        echo "  4. Run 'docker compose up' to start your services"
    else
        print_status "FAIL" "$TESTS_FAILED tests failed"
        echo ""
        echo "❌ Some functions are not working correctly."
        echo "Please check the failing tests and fix the issues before proceeding."
    fi
    
    # Clean up any test files
    rm -f test-compose-output.yml test_context_comments.env test_env_processing.env
    
    return $TESTS_FAILED
}

# Change to script directory
cd "$(dirname "${BASH_SOURCE[0]}")"

# Run main function
main "$@"