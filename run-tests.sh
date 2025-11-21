#!/bin/bash

# LiquidityPoolFacet Test Suite Runner
# Run comprehensive tests for the LiquidityPoolFacet contract

echo "🚀 LiquidityPoolFacet Test Suite"
echo "==============================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if hardhat is available
if ! command -v npx &> /dev/null; then
    print_error "npx not found. Please install Node.js and npm"
    exit 1
fi

# Compile contracts first
print_status "Compiling contracts..."
npx hardhat compile
if [ $? -ne 0 ]; then
    print_error "Contract compilation failed"
    exit 1
fi

# Run tests based on argument
case "${1:-all}" in
    "unit")
        print_status "Running Unit Tests..."
        npx hardhat test test/LiquidityPoolFacet.test.js
        ;;
    "fuzz")
        print_status "Running Fuzz Tests..."
        npx hardhat test test/LiquidityPoolFacet.fuzz.test.js
        ;;
    "integration")
        print_status "Running Integration Tests..."
        npx hardhat test test/LiquidityPoolFacet.integration.test.js
        ;;
    "coverage")
        print_status "Running Tests with Coverage..."
        npx hardhat coverage --testfiles 'test/LiquidityPoolFacet*.js'
        ;;
    "gas")
        print_status "Running Gas Report Tests..."
        REPORT_GAS=true npx hardhat test test/LiquidityPoolFacet*.js
        ;;
    "all")
        print_status "Running All Tests..."
        npx hardhat test test/LiquidityPoolFacet*.js
        ;;
    *)
        echo "Usage: $0 [unit|fuzz|integration|coverage|gas|all]"
        echo ""
        echo "Options:"
        echo "  unit        - Run unit tests only"
        echo "  fuzz        - Run fuzz tests only"
        echo "  integration - Run integration tests only"
        echo "  coverage    - Run tests with coverage report"
        echo "  gas         - Run tests with gas reporting"
        echo "  all         - Run all tests (default)"
        exit 1
        ;;
esac

print_status "Test execution completed!"