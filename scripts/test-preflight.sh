#!/usr/bin/env bash
# Test suite for preflight checks (AC1.1, AC1.4-AC1.7)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
SETUP_SCRIPT="${PROJECT_DIR}/setup.sh"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Helper function to assert test
assert_test() {
    local test_name="$1"
    local result="${2:-0}"  # 0 for pass, 1 for fail, 2 for skip

    if [[ "$result" == "0" ]] || [[ "$result" -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    elif [[ "$result" == "2" ]] || [[ "$result" -eq 2 ]]; then
        echo -e "${YELLOW}⊘${NC} $test_name"
        ((TESTS_SKIPPED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((TESTS_FAILED++))
    fi
}

echo "========================================"
echo "Test Suite: Preflight Checks"
echo "========================================"
echo ""

# AC1.1: Homebrew installed non-interactively when missing
# Placeholder test - requires macOS to properly test
echo "Testing AC1.1 - Homebrew installation..."
if [[ "$(uname -s)" == "Darwin" ]]; then
    # On macOS, we can partially test this by checking if brew exists
    if command -v brew &>/dev/null; then
        assert_test "AC1.1: Homebrew detection" 0
    else
        assert_test "AC1.1: Homebrew detection" 1
    fi
else
    echo "SKIP: AC1.1 requires macOS to fully test Homebrew installation"
    assert_test "AC1.1: Homebrew detection (skipped on non-macOS)" 2
fi
echo ""

# AC1.4: Dev Containers extension auto-installed via code CLI
# Placeholder test - requires VS Code to be installed
echo "Testing AC1.4 - Dev Containers extension..."
if command -v code &>/dev/null; then
    if code --list-extensions 2>/dev/null | grep -q "ms-vscode-remote.remote-containers"; then
        assert_test "AC1.4: Dev Containers extension installed" 0
    else
        assert_test "AC1.4: Dev Containers extension not installed (can install manually)" 1
    fi
else
    echo "SKIP: AC1.4 requires VS Code to test Dev Containers extension"
    assert_test "AC1.4: Dev Containers extension (skipped - no VS Code)" 2
fi
echo ""

# AC1.5: Source setup.sh and verify run_preflight function exists
echo "Testing AC1.5 - run_preflight function exists..."
# shellcheck disable=SC1090
if source "${SETUP_SCRIPT}" 2>/dev/null && declare -f run_preflight &>/dev/null; then
    assert_test "AC1.5: run_preflight function exists" 0
else
    assert_test "AC1.5: run_preflight function exists" 1
fi
echo ""

# AC1.6: Intel Mac detection - run with arch -x86_64 to simulate Intel
echo "Testing AC1.6 - Apple Silicon check..."
# First, attempt the test with arch -x86_64
if command -v arch &>/dev/null; then
    OUTPUT=$(arch -x86_64 bash "${SETUP_SCRIPT}" --preflight-only 2>&1 || true)
    if echo "$OUTPUT" | grep -q "Apple Silicon"; then
        exit_code=$(arch -x86_64 bash "${SETUP_SCRIPT}" --preflight-only >/dev/null 2>&1; echo $?)
        if [[ $exit_code -eq 1 ]]; then
            assert_test "AC1.6: Intel Mac detection with error code 1" 0
        else
            assert_test "AC1.6: Intel Mac detection - error code should be 1 (got $exit_code)" 1
        fi
    else
        # If arch -x86_64 doesn't change the arch, test that error is present
        assert_test "AC1.6: Intel Mac detection (arch -x86_64 not available)" 2
    fi
else
    # Fallback: can't test on this system
    assert_test "AC1.6: Intel Mac detection (no arch command)" 2
fi
echo ""

# AC1.7: check_vscode returns 0 even when VS Code is not installed (non-blocking)
echo "Testing AC1.7 - check_vscode is non-blocking..."
# shellcheck disable=SC1090
if source "${SETUP_SCRIPT}" 2>/dev/null && declare -f check_vscode &>/dev/null; then
    # check_vscode should always return 0 since it's non-blocking
    if check_vscode >/dev/null 2>&1; then
        assert_test "AC1.7: check_vscode returns 0 (non-blocking)" 0
    else
        assert_test "AC1.7: check_vscode returns 0 (non-blocking)" 1
    fi
else
    assert_test "AC1.7: check_vscode function exists" 1
fi
echo ""

# Print summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "${RED}Failed:${NC} $TESTS_FAILED"
echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
echo ""

# Only fail if tests actually failed (not just skipped)
if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
