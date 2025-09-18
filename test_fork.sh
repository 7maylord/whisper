#!/bin/bash

# Comprehensive Test Script for Whisper CoW Hook
echo "🚀 Starting Whisper Test Suite..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to run tests with status
run_test() {
    local test_name=$1
    local test_cmd=$2

    echo -e "${BLUE}Running: $test_name${NC}"
    if eval $test_cmd; then
        echo -e "${GREEN}✅ $test_name passed${NC}"
        return 0
    else
        echo -e "${RED}❌ $test_name failed${NC}"
        return 1
    fi
    echo ""
}

# Test counters
total_tests=0
passed_tests=0

echo ""
echo "=== LOCAL TESTS (No Fork Required) ==="
echo ""

# Test 1: Clean AVS Tests
total_tests=$((total_tests + 1))
if run_test "Clean AVS Configuration Tests" "forge test --match-contract CleanAVSTest -v"; then
    passed_tests=$((passed_tests + 1))
fi

# Test 2: Simple Whisper Tests
total_tests=$((total_tests + 1))
if run_test "Simple CoWMatcher Tests" "forge test --match-contract SimpleWhisperTest -v"; then
    passed_tests=$((passed_tests + 1))
fi

# Test 3: Whisper Core Tests
total_tests=$((total_tests + 1))
if run_test "Whisper Core Integration Tests" "forge test --match-contract WhisperTest -v"; then
    passed_tests=$((passed_tests + 1))
fi

# Test 4: Hook Tests
total_tests=$((total_tests + 1))
if run_test "Simple Hook Tests (permissions, storage, thresholds)" "forge test --match-contract SimpleHookTest -v"; then
    passed_tests=$((passed_tests + 1))
fi

echo ""
echo "=== FORK TESTS (Require Network Connection) ==="
echo ""

# Set RPC URL (you'll need to replace with your RPC)
ARB_SEPOLIA_RPC="https://sepolia-rollup.arbitrum.io/rpc"

# Alternative RPCs you can try:
# ARB_SEPOLIA_RPC="https://arbitrum-sepolia.infura.io/v3/YOUR_KEY"
# ARB_SEPOLIA_RPC="https://arb-sepolia.g.alchemy.com/v2/YOUR_KEY"

echo "Using RPC: $ARB_SEPOLIA_RPC"
echo ""

# Test 5: Simple Fork Tests
total_tests=$((total_tests + 1))
if run_test "Simple Fork Integration" "forge test --fork-url $ARB_SEPOLIA_RPC --match-contract SimpleForkTest -v"; then
    passed_tests=$((passed_tests + 1))
fi

# Test 6: Fork CoW Tests
total_tests=$((total_tests + 1))
if run_test "Fork CoW Functionality" "forge test --fork-url $ARB_SEPOLIA_RPC --match-contract ForkCoWTest -v"; then
    passed_tests=$((passed_tests + 1))
fi

# Test 7: Comprehensive Fork Tests
total_tests=$((total_tests + 1))
if run_test "Comprehensive Fork Tests" "forge test --fork-url $ARB_SEPOLIA_RPC --match-contract ComprehensiveForkTest -v"; then
    passed_tests=$((passed_tests + 1))
fi

echo ""
echo "=== TEST SUMMARY ==="
echo ""

if [ $passed_tests -eq $total_tests ]; then
    echo -e "${GREEN}🎉 All tests passed! ($passed_tests/$total_tests)${NC}"
    echo ""
    echo -e "${GREEN}✅ Your Whisper CoW Hook is ready for deployment!${NC}"
    echo "Deploy with: forge script script/Deploy.s.sol --rpc-url $ARB_SEPOLIA_RPC --private-key \$PRIVATE_KEY --broadcast"
else
    echo -e "${YELLOW}⚠️  Some tests failed: $passed_tests/$total_tests passed${NC}"
    failed_tests=$((total_tests - passed_tests))
    echo -e "${RED}❌ $failed_tests test(s) failed${NC}"
    echo ""
    echo "Run specific failing tests with more verbosity using:"
    echo "forge test --match-contract <TestContract> -vvv"
fi

echo ""
echo "=== QUICK TEST COMMANDS ==="
echo ""
echo "Local only:     forge test"
echo "Hook tests:     forge test --match-contract SimpleHookTest -v"
echo "Fork tests:     forge test --fork-url $ARB_SEPOLIA_RPC -v"
echo "Specific test:  forge test --match-test <test_name> -vv"
echo "Coverage:       forge coverage"