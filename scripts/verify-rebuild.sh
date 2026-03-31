#!/bin/bash
# verify-rebuild.sh — Run inside the container after rebuild to verify everything works
#
# Checks: plugins, hooks, settings, workspace repos, tools

set -uo pipefail

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Post-Rebuild Verification"
echo "══════════════════════════════════════════════════════"
echo ""

PASSED=0
FAILED=0

check() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "✓  $name"
        ((PASSED++)) || true
    else
        echo "✗  $name"
        ((FAILED++)) || true
    fi
}

check_contains() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if echo "$actual" | grep -q "$expected"; then
        echo "✓  $name"
        ((PASSED++)) || true
    else
        echo "✗  $name (expected '$expected')"
        ((FAILED++)) || true
    fi
}

# ── Tools ────────────────────────────────────────────────────────────────────
echo "--- Tools ---"
check "git available" command -v git
check "jq available" command -v jq
check "node available" command -v node
check "claude available" command -v claude
check "gh available" command -v gh

# ── Plugins ──────────────────────────────────────────────────────────────────
echo ""
echo "--- Plugins ---"
check "ed3d marketplace cloned" test -d "$HOME/.claude/plugins/marketplaces/ed3d-plugins/.claude-plugin"
check "marketplace.json exists" test -f "$HOME/.claude/plugins/marketplaces/ed3d-plugins/.claude-plugin/marketplace.json"

enabled=$(jq -r '.enabledPlugins // {} | keys[]' "$HOME/.claude/settings.json" 2>/dev/null)
check_contains "ed3d-plan-and-execute enabled" "ed3d-plan-and-execute@ed3d-plugins" "$enabled"
check_contains "ed3d-basic-agents enabled" "ed3d-basic-agents@ed3d-plugins" "$enabled"

marketplace_reg=$(jq -r '.extraKnownMarketplaces // {} | keys[]' "$HOME/.claude/settings.json" 2>/dev/null)
check_contains "ed3d-plugins marketplace registered" "ed3d-plugins" "$marketplace_reg"

# ── Settings ─────────────────────────────────────────────────────────────────
echo ""
echo "--- Settings ---"
check "settings.json valid JSON" jq . "$HOME/.claude/settings.json"
check "PreToolUse hooks present" jq -e '.hooks.PreToolUse' "$HOME/.claude/settings.json"
check "permissions configured" jq -e '.permissions.allow' "$HOME/.claude/settings.json"

# ── Workspace repos ──────────────────────────────────────────────────────────
echo ""
echo "--- Workspace repos ---"
for repo in claude-mac-env stock-analyzer road-trip T-Tracker claude-env; do
    check "$repo cloned" test -d "/workspaces/$repo/.git"
done

# ── Idempotency ──────────────────────────────────────────────────────────────
echo ""
echo "--- Idempotency ---"
rerun=$(BOOTSTRAP_MOCK_AUTH=1 bash /workspaces/claude-mac-env/config/bootstrap.sh 2>&1 || true)
check_contains "re-run completes" "Environment ready" "$rerun"
check_contains "plugins skip on re-run" "already installed" "$rerun"
check_contains "hooks skip on re-run" "already configured" "$rerun"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo "  Results: $PASSED passed, $FAILED failed"
echo "══════════════════════════════════════════════════════"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo "Some checks failed. If this is bad, restore from your Mac terminal:"
    echo "  bash scripts/restore-from-backup.sh ~/.claude-mac-env-backup-*"
    echo "  Then rebuild the container."
    exit 1
else
    echo "Everything looks good! Your environment is ready."
fi
