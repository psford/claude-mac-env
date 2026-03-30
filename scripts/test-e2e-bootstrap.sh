#!/usr/bin/env bash
# test-e2e-bootstrap.sh — E2E postcondition verifier for bootstrap.sh
#
# Runs inside the container after bootstrap.sh completes.
# Verifies every bootstrap postcondition.

set -uo pipefail

echo "========================================"
echo "E2E Bootstrap Postcondition Verification"
echo "========================================"
echo ""

CHECKS_PASSED=0
CHECKS_FAILED=0

check_pass() {
    local name="$1"
    echo "✓ $name"
    ((CHECKS_PASSED++)) || true
}

check_fail() {
    local name="$1"
    local detail="${2:-}"
    echo "✗ $name"
    [ -n "$detail" ] && echo "  $detail"
    ((CHECKS_FAILED++)) || true
}

# 1. Skills installed: $HOME/.claude/skills/ has > 0 directories
skill_count=$(find "$HOME/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l) || true
if [ "$skill_count" -gt 0 ]; then
    check_pass "Skills installed ($skill_count skills)"
else
    check_fail "Skills installed" "$HOME/.claude/skills/ has no subdirectories"
fi

# 2. Known skill present
if [ -f "$HOME/.claude/skills/brainstorming/SKILL.md" ]; then
    check_pass "Known skill present (brainstorming)"
else
    check_fail "Known skill present (brainstorming)" "$HOME/.claude/skills/brainstorming/SKILL.md not found"
fi

# 3. settings.json valid
if [ -f "$HOME/.claude/settings.json" ] && jq . "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    check_pass "settings.json is valid JSON"
else
    check_fail "settings.json is valid JSON" "File missing or invalid"
fi

# 4. Hooks in settings.json
if jq -e '.hooks.PreToolUse' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    check_pass "PreToolUse hooks present in settings.json"
else
    check_fail "PreToolUse hooks present in settings.json"
fi

# 5. Credential helper configured
cred_helper=$(git config credential.helper 2>/dev/null) || true
if [ -n "$cred_helper" ]; then
    check_pass "Git credential helper configured ($cred_helper)"
else
    # Non-critical in mock mode — gh auth wasn't run
    if [ "${BOOTSTRAP_MOCK_AUTH:-}" = "1" ]; then
        check_pass "Git credential helper (skipped in mock mode)"
    else
        check_fail "Git credential helper configured" "git config credential.helper is empty"
    fi
fi

# 6. gh available
if command -v gh >/dev/null 2>&1; then
    check_pass "gh CLI available ($(command -v gh))"
else
    check_fail "gh CLI available"
fi

# 7. Bootstrap idempotent — re-running produces no errors
if [ -f "/workspaces/.claude-mac-env/config/bootstrap.sh" ]; then
    rerun_output=$(BOOTSTRAP_MOCK_AUTH=1 USER_CONFIG="${USER_CONFIG:-/workspaces/.claude-mac-env/.user-config.json}" bash /workspaces/.claude-mac-env/config/bootstrap.sh 2>&1) || true
    if echo "$rerun_output" | grep -q "Environment ready"; then
        check_pass "Bootstrap idempotent (re-run succeeds)"
    else
        check_fail "Bootstrap idempotent" "Re-run did not complete successfully"
    fi
else
    check_pass "Bootstrap idempotent (script not mounted, skipping)"
fi

# Summary
echo ""
echo "========================================"
echo "Results: $CHECKS_PASSED passed, $CHECKS_FAILED failed"
echo "========================================"

if [ "$CHECKS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
