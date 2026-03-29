#!/usr/bin/env bash
# Test suite for bootstrap-secrets.sh

set -uo pipefail

BOOTSTRAP_SCRIPT="/private/tmp/claude-mac-env/config/bootstrap-secrets.sh"
INTERFACE_SCRIPT="/private/tmp/claude-mac-env/config/secrets-interface.sh"
TEMP_DIR=$(mktemp -d)
TEST_CONFIG_FILE="$TEMP_DIR/config.json"

cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================"
echo "Test Suite: bootstrap-secrets.sh"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

assert_success() {
    local test_name="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        echo "✓ $test_name"
        ((TESTS_PASSED++))
    else
        echo "✗ $test_name"
        "$@" 2>&1 | head -5
        ((TESTS_FAILED++))
    fi
}

assert_failure() {
    local test_name="$1"
    shift

    if ! "$@" >/dev/null 2>&1; then
        echo "✓ $test_name"
        ((TESTS_PASSED++))
    else
        echo "✗ $test_name (expected failure but succeeded)"
        ((TESTS_FAILED++))
    fi
}

assert_output_contains() {
    local test_name="$1"
    local search_text="$2"
    shift 2

    local output
    output=$("$@" 2>&1)

    if echo "$output" | grep -q "$search_text"; then
        echo "✓ $test_name"
        ((TESTS_PASSED++))
    else
        echo "✗ $test_name (output did not contain '$search_text')"
        echo "  Got: $output"
        ((TESTS_FAILED++))
    fi
}

# Test 1: "none" provider exits cleanly with code 0
cat > "$TEST_CONFIG_FILE" <<'EOF'
{
  "secrets": {
    "provider": "none"
  }
}
EOF

assert_success "none provider exits 0" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$BOOTSTRAP_SCRIPT' && main"

# Test 2: Missing config file is handled gracefully
assert_success "missing config handled gracefully" \
    bash -c "export USER_CONFIG='/nonexistent/config.json' && source '$INTERFACE_SCRIPT' && source '$BOOTSTRAP_SCRIPT' && main"

# Test 3: Non-existent provider script is handled
cat > "$TEST_CONFIG_FILE" <<'EOF'
{
  "secrets": {
    "provider": "nonexistent"
  }
}
EOF

assert_output_contains "nonexistent provider generates warning" "warning" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$BOOTSTRAP_SCRIPT' && main 2>&1"

# Test 4: Empty provider (not set) exits cleanly
cat > "$TEST_CONFIG_FILE" <<'EOF'
{
  "secrets": {}
}
EOF

assert_success "empty provider exits cleanly" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$BOOTSTRAP_SCRIPT' && main"

# Test 5: Invalid JSON config file is handled
cat > "$TEST_CONFIG_FILE" <<'EOF'
{invalid json}
EOF

assert_success "invalid JSON handled gracefully" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$BOOTSTRAP_SCRIPT' && main"

# Summary
echo ""
echo "========================================"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
