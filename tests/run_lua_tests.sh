#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}ConsoleLog Lua Test Suite${NC}"
echo -e "${BLUE}================================${NC}\n"

TEST_DIR="tests/lua"
FAILED_TESTS=()
PASSED_TESTS=()

run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .lua)
    
    echo -e "${CYAN}Running: ${test_name}${NC}"
    
    nvim --headless --clean -c "lua package.path = './lua/?.lua;./lua/?/init.lua;./tests/lua/?.lua;' .. package.path" -c "lua local ok, err = pcall(dofile, '$test_file'); if not ok then print('FAILED: ' .. err) end" -c "qa!" 2>&1 | tee /tmp/test_output.txt
    local nvim_exit=${PIPESTATUS[0]}
    
    # Check for FAILED: lines emitted by test assertions
    if grep -q "FAILED:" /tmp/test_output.txt || [ $nvim_exit -ne 0 ]; then
        echo -e "${RED}✗ FAILED: ${test_name}${NC}\n"
        FAILED_TESTS+=("$test_name")
        return 1
    else
        echo -e "${GREEN}✓ PASSED: ${test_name}${NC}\n"
        PASSED_TESTS+=("$test_name")
        return 0
    fi
}

echo -e "${YELLOW}Starting Lua tests...${NC}\n"

for test_file in $TEST_DIR/*_spec.lua; do
    if [ -f "$test_file" ]; then
        run_test "$test_file"
    fi
done

echo -e "\n${BLUE}================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}================================${NC}\n"

echo -e "${GREEN}Passed tests (${#PASSED_TESTS[@]}):${NC}"
for test in "${PASSED_TESTS[@]}"; do
    echo -e "  ${GREEN}✓${NC} $test"
done

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "\n${RED}Failed tests (${#FAILED_TESTS[@]}):${NC}"
    for test in "${FAILED_TESTS[@]}"; do
        echo -e "  ${RED}✗${NC} $test"
    done
fi

TOTAL_TESTS=$((${#PASSED_TESTS[@]} + ${#FAILED_TESTS[@]}))
echo -e "\n${CYAN}Total: ${#PASSED_TESTS[@]}/${TOTAL_TESTS} tests passed${NC}"

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi