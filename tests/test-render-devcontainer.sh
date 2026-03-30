#!/usr/bin/env bash
# Test suite for render_devcontainer_json() — Layer 1 tool
# Verifies AC9.1 (jq only), AC9.2 (valid JSON output), AC9.3 (no bash JSON sub)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_SH="$REPO_DIR/config/lib/tools.sh"
TEMPLATE="$REPO_DIR/.devcontainer/devcontainer.json.template"

TEMP_DIR=$(mktemp -d)

# shellcheck disable=SC2317
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================"
echo "Test Suite: render_devcontainer_json"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

assert_success() {
    local test_name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name"
        ((TESTS_FAILED++)) || true
    fi
}

assert_failure() {
    local test_name="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected failure but succeeded)"
        ((TESTS_FAILED++)) || true
    fi
}

assert_json_value() {
    local test_name="$1"
    local expected="$2"
    local jq_filter="$3"
    local file="$4"
    local actual
    actual=$(jq -r "$jq_filter" "$file" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected '$expected', got '$actual')"
        ((TESTS_FAILED++)) || true
    fi
}

assert_json_contains() {
    local test_name="$1"
    local expected="$2"
    local jq_filter="$3"
    local file="$4"
    local actual
    actual=$(jq -r "$jq_filter" "$file" 2>/dev/null)
    if echo "$actual" | grep -q "$expected"; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected to contain '$expected', got '$actual')"
        ((TESTS_FAILED++)) || true
    fi
}

# Source tools
# shellcheck source=../config/lib/tools.sh
source "$TOOLS_SH"

# ── AC9.1: jq only — basic render ───────────────────────────────────────────

echo "--- AC9.1: jq-only render ---"

# Create test config
cat > "$TEMP_DIR/config.json" <<'CONFIG_EOF'
{
    "baseImage": "ubuntu:24.04",
    "githubUser": "testuser",
    "projectDirs": ["/Users/testuser/projects/myapp", "/Users/testuser/projects/lib"],
    "features": {
        "claude-skills": {},
        "universal-hooks": {}
    },
    "secrets": {
        "provider": "none"
    }
}
CONFIG_EOF

OUTPUT="$TEMP_DIR/devcontainer.json"
assert_success "render basic config" render_devcontainer_json "$TEMP_DIR/config.json" "$TEMPLATE" "$OUTPUT" "$REPO_DIR"

# Valid JSON (AC9.2)
assert_success "output is valid JSON (AC9.2)" jq . "$OUTPUT"

# Base image set correctly
assert_json_value "base image set" "ubuntu:24.04" '.build.args.BASE_IMAGE' "$OUTPUT"

# Features contain GHCR URLs
assert_json_contains "features have GHCR URLs" "ghcr.io/psford/claude-mac-env/" '.features | keys[]' "$OUTPUT"

# Project mounts present
assert_json_contains "project mounts: myapp" "myapp" '[.mounts[] | select(contains("myapp"))] | .[0]' "$OUTPUT"
assert_json_contains "project mounts: lib" "/workspaces/lib" '[.mounts[] | select(contains("/workspaces/lib"))] | .[0]' "$OUTPUT"

# localEnv mounts preserved literally
assert_json_contains "localEnv:HOME gitconfig preserved" 'localEnv:HOME' '[.mounts[] | select(contains("gitconfig"))] | .[0]' "$OUTPUT"
assert_json_contains "localEnv:HOME ssh preserved" 'localEnv:HOME' '[.mounts[] | select(contains(".ssh"))] | .[0]' "$OUTPUT"

# postCreateCommand
assert_json_contains "postCreateCommand is bootstrap.sh" "bootstrap.sh" '.postCreateCommand' "$OUTPUT"

# ── AC9.2: various configs produce valid JSON ───────────────────────────────

echo ""
echo "--- AC9.2: valid JSON for various configs ---"

# Empty features
cat > "$TEMP_DIR/config-empty.json" <<'EOF'
{
    "baseImage": "ubuntu:24.04",
    "githubUser": "testuser",
    "projectDirs": [],
    "features": {},
    "secrets": {"provider": "none"}
}
EOF
OUTPUT2="$TEMP_DIR/devcontainer-empty.json"
assert_success "empty features renders" render_devcontainer_json "$TEMP_DIR/config-empty.json" "$TEMPLATE" "$OUTPUT2" "$REPO_DIR"
assert_success "empty features is valid JSON" jq . "$OUTPUT2"

# With csharp-tools (adds extension)
cat > "$TEMP_DIR/config-csharp.json" <<'EOF'
{
    "baseImage": "ubuntu:24.04",
    "githubUser": "testuser",
    "projectDirs": [],
    "features": {"csharp-tools": {"dotnetVersion": "8.0"}},
    "secrets": {"provider": "none"}
}
EOF
OUTPUT3="$TEMP_DIR/devcontainer-csharp.json"
assert_success "csharp config renders" render_devcontainer_json "$TEMP_DIR/config-csharp.json" "$TEMPLATE" "$OUTPUT3" "$REPO_DIR"
assert_success "csharp config is valid JSON" jq . "$OUTPUT3"
assert_json_contains "csharp extension added" "ms-dotnettools.csharp" '.customizations.vscode.extensions[]' "$OUTPUT3"

# With env secrets provider (adds .env mount)
cat > "$TEMP_DIR/config-env.json" <<'EOF'
{
    "baseImage": "ubuntu:24.04",
    "githubUser": "testuser",
    "projectDirs": [],
    "features": {},
    "secrets": {"provider": "env", "envFilePath": "/Users/testuser/.env"}
}
EOF
OUTPUT4="$TEMP_DIR/devcontainer-env.json"
assert_success "env secrets config renders" render_devcontainer_json "$TEMP_DIR/config-env.json" "$TEMPLATE" "$OUTPUT4" "$REPO_DIR"
assert_success "env secrets config is valid JSON" jq . "$OUTPUT4"
assert_json_contains "env file mount present" ".env" '[.mounts[] | select(contains(".env"))] | .[0]' "$OUTPUT4"

# ── AC9.3: no bash JSON substitution in setup.sh ────────────────────────────

echo ""
echo "--- AC9.3: no bash JSON substitution in render function ---"

# Check that the render_devcontainer function in setup.sh has no {{placeholders}}
# or bash parameter expansion on JSON content
render_func=$(sed -n '/^render_devcontainer()/,/^}/p' "$REPO_DIR/setup.sh")

if ! echo "$render_func" | grep -q '{{'; then
    echo "✓ No {{placeholder}} tokens in render_devcontainer()"
    ((TESTS_PASSED++)) || true
else
    echo "✗ Found {{placeholder}} tokens in render_devcontainer()"
    ((TESTS_FAILED++)) || true
fi

if ! echo "$render_func" | grep -q 'rendered=.*{rendered//'; then
    echo "✓ No bash parameter expansion on JSON in render_devcontainer()"
    ((TESTS_PASSED++)) || true
else
    echo "✗ Found bash parameter expansion on JSON in render_devcontainer()"
    ((TESTS_FAILED++)) || true
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
