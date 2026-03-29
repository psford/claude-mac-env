#!/usr/bin/env bash
# Test suite for secrets-env.sh provider

set -uo pipefail

PROVIDER_SCRIPT="/private/tmp/claude-mac-env/config/secrets-env.sh"
INTERFACE_SCRIPT="/private/tmp/claude-mac-env/config/secrets-interface.sh"
TEMP_DIR=$(mktemp -d)
TEST_ENV_FILE="$TEMP_DIR/test.env"
TEST_OUTPUT_FILE="$TEMP_DIR/secrets.env"
TEST_CONFIG_FILE="$TEMP_DIR/config.json"

cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================"
echo "Test Suite: secrets-env.sh Provider"
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

# Test 1: secrets_describe() returns expected text
assert_output_contains "describe returns correct text" "Read secrets from a .env file" \
    bash -c "source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_describe"

# Test 2: secrets_validate() fails when .env file doesn't exist
cat > "$TEST_CONFIG_FILE" <<'EOF'
{
  "secrets": {
    "provider": "env",
    "envFilePath": "/nonexistent/file.env"
  }
}
EOF

assert_failure "validate fails for nonexistent file" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_validate"

# Test 3: secrets_validate() succeeds when .env file exists
cat > "$TEST_ENV_FILE" <<'EOF'
API_KEY=test123
DATABASE_URL=postgres://localhost/test
EOF

cat > "$TEST_CONFIG_FILE" <<EOF
{
  "secrets": {
    "provider": "env",
    "envFilePath": "$TEST_ENV_FILE"
  }
}
EOF

assert_success "validate succeeds for existing file" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_validate"

# Test 4: secrets_inject() creates output file with exports
assert_success "inject creates output file" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && export SECRETS_OUTPUT_PATH='$TEST_OUTPUT_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_inject && test -f '$TEST_OUTPUT_FILE'"

# Test 5: secrets_inject() converts to export format
assert_output_contains "output contains export API_KEY" "export API_KEY=test123" \
    cat "$TEST_OUTPUT_FILE"

# Test 6: secrets_inject() skips comments
cat > "$TEST_ENV_FILE" <<'EOF'
# This is a comment
API_KEY=test123

# Another comment
DATABASE_URL=postgres://localhost/test
EOF

rm -f "$TEST_OUTPUT_FILE"
bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && export SECRETS_OUTPUT_PATH='$TEST_OUTPUT_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_inject" >/dev/null 2>&1

assert_success "output has no comment lines" \
    bash -c "! grep '^#' '$TEST_OUTPUT_FILE'"

# Test 7: secrets_inject() preserves existing exports
cat > "$TEST_ENV_FILE" <<'EOF'
export API_KEY=test123
DATABASE_URL=postgres://localhost/test
EOF

rm -f "$TEST_OUTPUT_FILE"
bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && export SECRETS_OUTPUT_PATH='$TEST_OUTPUT_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_inject" >/dev/null 2>&1

assert_success "preserves existing exports" \
    bash -c "grep '^export API_KEY=test123' '$TEST_OUTPUT_FILE'"

# Test 8: secrets_inject() handles quoted values
cat > "$TEST_ENV_FILE" <<'EOF'
QUOTED_VAR="value with spaces"
SINGLE_QUOTED='another value'
EOF

rm -f "$TEST_OUTPUT_FILE"
bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && export SECRETS_OUTPUT_PATH='$TEST_OUTPUT_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_inject" >/dev/null 2>&1

assert_success "handles quoted values" \
    bash -c "grep -q 'QUOTED_VAR=' '$TEST_OUTPUT_FILE' && grep -q 'SINGLE_QUOTED=' '$TEST_OUTPUT_FILE'"

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
