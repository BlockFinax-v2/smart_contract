#!/bin/bash

# BaseModule Test Runner Script
# This script helps you run BaseModule tests easily

echo "🧪 BlockFinax BaseModule Test Suite"
echo "===================================="

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to run BaseModule tests
run_basemodule_tests() {
    echo -e "${YELLOW}Running BaseModule Standalone Tests...${NC}"
    
    # Temporarily isolate BaseModule for clean testing
    mkdir -p temp_backup
    
    # Backup files that cause compilation issues
    if [ -d "src" ] && [ "$(ls -A src)" ]; then
        echo "Backing up src files..."
        cp -r src/* temp_backup/ 2>/dev/null || true
        find src -name "*.sol" ! -name "BaseModule.sol" -delete 2>/dev/null || true
    fi
    
    if [ -d "script" ]; then
        echo "Backing up script directory..."
        mv script temp_backup_script 2>/dev/null || true
    fi
    
    if [ -d "tests" ]; then
        echo "Backing up test files..."
        find tests -name "Test*.sol" -exec mv {} temp_backup/ \; 2>/dev/null || true
    fi
    
    # Run the standalone test
    echo -e "${YELLOW}Executing tests...${NC}"
    if forge test --match-path "*BaseModuleStandalone.t.sol" -v; then
        echo -e "${GREEN}✅ All BaseModule tests passed!${NC}"
        test_result=0
    else
        echo -e "${RED}❌ Some tests failed.${NC}"
        test_result=1
    fi
    
    # Restore backed up files
    echo "Restoring backed up files..."
    if [ -d "temp_backup" ]; then
        cp -r temp_backup/* src/ 2>/dev/null || true
        rm -rf temp_backup
    fi
    
    if [ -d "temp_backup_script" ]; then
        mv temp_backup_script script
    fi
    
    return $test_result
}

# Function to run with gas reporting
run_with_gas_report() {
    echo -e "${YELLOW}Running tests with gas reporting...${NC}"
    
    # Same isolation process
    mkdir -p temp_backup
    cp -r src/* temp_backup/ 2>/dev/null || true
    find src -name "*.sol" ! -name "BaseModule.sol" -delete 2>/dev/null || true
    [ -d "script" ] && mv script temp_backup_script 2>/dev/null || true
    find tests -name "Test*.sol" -exec mv {} temp_backup/ \; 2>/dev/null || true
    
    # Run with gas report
    forge test --match-path "*BaseModuleStandalone.t.sol" --gas-report
    
    # Restore files
    cp -r temp_backup/* src/ 2>/dev/null || true
    rm -rf temp_backup
    [ -d "temp_backup_script" ] && mv temp_backup_script script
}

# Function to check contract compilation
check_compilation() {
    echo -e "${YELLOW}Checking BaseModule compilation...${NC}"
    if forge build src/BaseModule.sol; then
        echo -e "${GREEN}✅ BaseModule compiles successfully!${NC}"
        return 0
    else
        echo -e "${RED}❌ Compilation failed.${NC}"
        return 1
    fi
}

# Main menu
case "${1:-menu}" in
    "test")
        run_basemodule_tests
        ;;
    "gas")
        run_with_gas_report
        ;;
    "compile")
        check_compilation
        ;;
    "all")
        echo "Running complete test suite..."
        check_compilation && run_basemodule_tests && run_with_gas_report
        ;;
    "menu"|*)
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  test     - Run BaseModule tests"
        echo "  gas      - Run tests with gas reporting"
        echo "  compile  - Check compilation only"
        echo "  all      - Run all checks (compile + test + gas report)"
        echo ""
        echo "Examples:"
        echo "  $0 test     # Quick test run"
        echo "  $0 gas      # Test with gas usage details"
        echo "  $0 all      # Complete test suite"
        ;;
esac
