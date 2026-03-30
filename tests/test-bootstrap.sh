#!/usr/bin/env bash
# Test suite for config/bootstrap.sh — Layer 3 orchestrator tests
#
# Tests idempotency, error handling integration, auth routing, and flags.
# Mocks gh, az, git, and claude since we can't do real auth or clones here.
# Interactive auth flows and real clones are tested E2E in Phase 7.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMP_DIR=$(mktemp -d)
MOCK_BIN="$TEMP_DIR/mock_bin"
MOCK_HOME="$TEMP_DIR/home"
mkdir -p "$MOCK_BIN" "$MOCK_HOME/.claude/skills"

# shellcheck disable=SC2317
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================"
echo "Test Suite: bootstrap.sh"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

assert_output_contains() {
    local test_name="$1"
    local expected="$2"
    local output="$3"
    if echo "$output" | grep -q "$expected"; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected output containing '$expected')"
        ((TESTS_FAILED++)) || true
    fi
}

assert_output_not_contains() {
    local test_name="$1"
    local not_expected="$2"
    local output="$3"
    if ! echo "$output" | grep -q "$not_expected"; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (output should NOT contain '$not_expected')"
        ((TESTS_FAILED++)) || true
    fi
}

# Create mock commands that simulate authenticated state
create_mock() {
    local name="$1"
    local script="$2"
    cat > "$MOCK_BIN/$name" <<MOCK_EOF
#!/bin/bash
$script
MOCK_EOF
    chmod +x "$MOCK_BIN/$name"
}

# Mock gh: authenticated as testuser
create_mock "gh" '
case "$1" in
    auth)
        case "$2" in
            status) echo "Logged in to github.com as testuser"; exit 0 ;;
            setup-git) exit 0 ;;
            *) exit 0 ;;
        esac
        ;;
    *) exit 0 ;;
esac
'

# Mock az: authenticated
create_mock "az" '
case "$1" in
    account)
        echo "{\"name\": \"test-sub\", \"id\": \"abc-123\"}"
        exit 0
        ;;
    *) exit 0 ;;
esac
'

# Mock git: succeed for config, fail for clone (no real repos available)
create_mock "git_mock" '
case "$1" in
    config) echo "!/usr/bin/gh auth git-credential"; exit 0 ;;
    clone) exit 1 ;;  # No real repos to clone in test
    *) /usr/bin/git "$@" ;;
esac
'

# Mock claude
create_mock "claude" 'echo "claude-code 1.0.0"'

# Create a config file
create_config() {
    local github_user="$1"
    local secrets_provider="$2"
    local config_file="$TEMP_DIR/user-config.json"
    cat > "$config_file" <<CONFIG_EOF
{
    "githubUser": "$github_user",
    "secrets": {
        "provider": "$secrets_provider"
    }
}
CONFIG_EOF
    echo "$config_file"
}

# Run bootstrap.sh with mocked environment
# We source tools.sh and errors.sh ourselves to set up the function namespace,
# then source bootstrap.sh functions. But bootstrap.sh calls main() on source,
# so we need to run it as a subprocess.
run_bootstrap() {
    local config_file="$1"
    shift
    HOME="$MOCK_HOME" \
    USER_CONFIG="$config_file" \
    PATH="$MOCK_BIN:/usr/bin:/bin:/usr/local/bin" \
    bash "$REPO_DIR/config/bootstrap.sh" "$@" 2>&1
}

# ── Idempotency tests ───────────────────────────────────────────────────────

echo "--- Idempotency (AC8) ---"

# Pre-populate skills so step 4 skips
mkdir -p "$MOCK_HOME/.claude/skills/brainstorming"
echo "# Brainstorming" > "$MOCK_HOME/.claude/skills/brainstorming/SKILL.md"
mkdir -p "$MOCK_HOME/.claude/skills/coding"
echo "# Coding" > "$MOCK_HOME/.claude/skills/coding/SKILL.md"

# Pre-populate settings.json with hooks so step 5 skips
mkdir -p "$MOCK_HOME/.claude"
cat > "$MOCK_HOME/.claude/settings.json" <<'SETTINGS_EOF'
{
  "permissions": {"allow": ["Bash(*)"]},
  "hooks": {"PreToolUse": [{"matcher": "Bash"}]}
}
SETTINGS_EOF

# Pre-populate secrets.env so step 6 skips
echo "SECRET_KEY=test123" > "$MOCK_HOME/.secrets.env"
touch -t "$(date -d '1 hour ago' +%Y%m%d%H%M.%S)" "$MOCK_HOME/.secrets.env" 2>/dev/null || \
touch "$MOCK_HOME/.secrets.env"  # fallback if date -d not available

config_file=$(create_config "testuser" "env")
output=$(run_bootstrap "$config_file")

assert_output_contains "Skills already installed → skip (AC4.6)" "already installed" "$output"
assert_output_contains "Hooks already configured → skip (AC5.5)" "already configured" "$output"
assert_output_contains "Secrets already loaded → skip (AC7.4)" "Secrets loaded" "$output"

# ── GitHub auth already done (AC2.1) ────────────────────────────────────────

echo ""
echo "--- GitHub auth (AC2.1) ---"

assert_output_contains "Already connected to GitHub as testuser" "Already connected to GitHub as testuser" "$output"

# ── Azure routing ────────────────────────────────────────────────────────────

echo ""
echo "--- Azure routing (AC2.5, AC2.7) ---"

# psford → Azure step runs
config_file=$(create_config "psford" "azure")
output=$(run_bootstrap "$config_file")
assert_output_contains "psford → Azure step runs (AC2.5)" "Connecting to Azure" "$output"

# non-psford + non-azure → Azure step skipped
config_file=$(create_config "otheruser" "env")
output=$(run_bootstrap "$config_file")
assert_output_not_contains "non-psford + env provider → no Azure (AC2.7)" "Connecting to Azure" "$output"

# ── Secrets skip (AC7.2) ────────────────────────────────────────────────────

echo ""
echo "--- Secrets skip (AC7.2) ---"

# Remove secrets.env so we can test skip provider
rm -f "$MOCK_HOME/.secrets.env"
config_file=$(create_config "testuser" "skip")
output=$(run_bootstrap "$config_file")
assert_output_contains "secrets.provider=skip → skips cleanly (AC7.2)" "No secrets provider configured" "$output"

# ── --secrets-only flag ──────────────────────────────────────────────────────

echo ""
echo "--- --secrets-only flag ---"

config_file=$(create_config "testuser" "skip")
output=$(run_bootstrap "$config_file" --secrets-only)
assert_output_not_contains "--secrets-only skips tool checks" "Checking tools" "$output"
assert_output_not_contains "--secrets-only skips GitHub auth" "Connecting to GitHub" "$output"
assert_output_contains "--secrets-only runs secrets step" "Loading secrets" "$output"

# ── Error handling integration ───────────────────────────────────────────────

echo ""
echo "--- Error handling integration ---"

# Test missing tool by using a PATH that has no claude at all
# We need mocks for everything EXCEPT claude, and a PATH that excludes real claude
RESTRICTED_BIN="$TEMP_DIR/restricted_bin"
mkdir -p "$RESTRICTED_BIN"
# Copy essential tools (not claude) into restricted bin
for tool in git curl jq node python3 bash cat grep find wc stat date readlink dirname basename mkdir cp rm ln chmod chown sed head tr read; do
    real_path=$(command -v "$tool" 2>/dev/null) || true
    if [ -n "$real_path" ]; then
        ln -sf "$real_path" "$RESTRICTED_BIN/$tool" 2>/dev/null || true
    fi
done
# Add our gh/az mocks
cp "$MOCK_BIN/gh" "$RESTRICTED_BIN/gh"
cp "$MOCK_BIN/az" "$RESTRICTED_BIN/az"
# NO claude in restricted bin
config_file=$(create_config "testuser" "skip")
output=$(HOME="$MOCK_HOME" USER_CONFIG="$config_file" PATH="$RESTRICTED_BIN" bash "$REPO_DIR/config/bootstrap.sh" 2>&1 || true)
assert_output_contains "Missing tool → Dockerfile message" "Dockerfile" "$output"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
