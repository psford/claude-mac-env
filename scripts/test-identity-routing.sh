#!/usr/bin/env bash
# Test suite for identity routing and feature selection (AC2.1, AC2.2, AC2.5, AC2.6)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/setup.sh" ]]; then
    SETUP_SCRIPT="${SCRIPT_DIR}/setup.sh"
else
    PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
    SETUP_SCRIPT="${PROJECT_DIR}/setup.sh"
fi

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# Helper function
assert_test() {
    local test_name="$1"
    local result="$2"

    if [[ "$result" -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((TESTS_FAILED++))
    fi
}

echo "========================================"
echo "Test Suite: Identity Routing & Features"
echo "========================================"
echo ""

# Test 1: Source setup.sh and verify select_features function exists
echo "Testing AC2.1-AC2.6 - Function presence and logic..."
result=1
if bash -c "source '$SETUP_SCRIPT' 2>/dev/null && declare -f select_features >/dev/null 2>&1"; then
    result=0
fi
assert_test "AC2: select_features function exists" $result
echo ""

# Test 2: Verify psford detection in code
echo "Testing AC2.1 - psford user detection logic..."
result=0
if grep -q '"psford"' "$SETUP_SCRIPT" && grep -q 'All Features enabled for psford' "$SETUP_SCRIPT"; then
    result=0
else
    result=1
fi
assert_test "AC2.1: psford all-features logic in setup.sh" $result
echo ""

# Test 3: Verify that psford-personal is only offered conditionally
echo "Testing AC2.5 - psford-personal in setup.sh..."
result=0
if grep -q '"psford-personal"' "$SETUP_SCRIPT"; then
    result=0
else
    result=1
fi
assert_test "AC2.5: psford-personal in setup.sh" $result
echo ""

# Test 4: Verify fallback logic for empty/failed manifest
echo "Testing AC2.6 - Empty manifest fallback..."
result=0
if grep -q 'Falling back to claude-skills only' "$SETUP_SCRIPT" && grep -q '"claude-skills"' "$SETUP_SCRIPT"; then
    result=0
else
    result=1
fi
assert_test "AC2.6: Fallback to claude-skills on manifest failure" $result
echo ""

# Test 5: Verify tiered selection logic
echo "Testing AC2.2/AC2.3/AC2.4 - Tiered selection prompts..."
result=0
if grep -q 'Universal development tools available' "$SETUP_SCRIPT" && grep -q '.NET tools available' "$SETUP_SCRIPT"; then
    result=0
else
    result=1
fi
assert_test "AC2.2-AC2.4: Tiered selection prompts present" $result
echo ""

# Print summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "${RED}Failed:${NC} $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
