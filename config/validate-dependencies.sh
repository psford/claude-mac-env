#!/usr/bin/env bash
# validate-dependencies.sh — Validates that every dependency in the bootstrap
# chain is present and functional BEFORE any step that needs it runs.
#
# This exists because we shipped a container where az, gh, skills, and hooks
# were all missing — every link in the chain was broken because nobody checked.
#
# RULE: Every script in this repo that depends on an external tool MUST either:
#   1. Call validate_dependency() for each tool it needs, OR
#   2. Source this file and call validate_chain() for a named chain
#
# If you add a new dependency anywhere, add it here. If you don't, the
# validate_all function will not cover it and the next person will get burned
# the same way we did.

set -uo pipefail
# NOTE: set -e is intentionally NOT used here. Validation functions return
# non-zero to indicate failures but must not abort the script — we need to
# collect ALL failures, not just the first one.

VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# ── Single dependency check ──────────────────────────────────────────────────

validate_dependency() {
    local cmd="$1"
    local reason="$2"
    local required="${3:-true}"  # "true" = hard fail, "false" = warn only

    if command -v "$cmd" &>/dev/null; then
        echo "  ✓ $cmd ($(command -v "$cmd"))"
        return 0
    else
        if [[ "$required" == "true" ]]; then
            echo "  ✗ $cmd — MISSING — needed for: $reason"
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
            return 1
        else
            echo "  ⚠ $cmd — missing (optional) — needed for: $reason"
            VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
            return 0
        fi
    fi
}

# ── Connectivity / auth checks ───────────────────────────────────────────────

validate_github_auth() {
    echo ""
    echo "GitHub authentication:"
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        echo "  ✓ gh authenticated"
        return 0
    else
        echo "  ✗ gh not authenticated — needed for: cloning private repos (skills, claude-config)"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
}

validate_azure_auth() {
    echo ""
    echo "Azure authentication:"
    if ! command -v az &>/dev/null; then
        echo "  ✗ az not installed — cannot check auth"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
    if timeout 5 az account show &>/dev/null 2>&1; then
        echo "  ✓ az authenticated"
        return 0
    else
        echo "  ✗ az not authenticated — needed for: Key Vault secrets (which provides GitHub token)"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
}

validate_ssh_github() {
    echo ""
    echo "SSH to GitHub:"
    # Try with a writable known_hosts location if the mounted one is read-only
    if timeout 5 ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 -T git@github.com 2>&1 | grep -qi "successfully authenticated"; then
        echo "  ✓ SSH to github.com works"
        return 0
    else
        echo "  ⚠ SSH to github.com failed — HTTPS via gh will be used instead"
        VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
        return 0
    fi
}

# ── File / directory checks ──────────────────────────────────────────────────

validate_path() {
    local path="$1"
    local reason="$2"
    local required="${3:-true}"

    if [[ -e "$path" ]]; then
        echo "  ✓ $path"
        return 0
    else
        if [[ "$required" == "true" ]]; then
            echo "  ✗ $path — MISSING — needed for: $reason"
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
            return 1
        else
            echo "  ⚠ $path — missing (optional) — needed for: $reason"
            VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
            return 0
        fi
    fi
}

# ── Named dependency chains ──────────────────────────────────────────────────
# Each chain represents a feature that requires multiple dependencies.
# If you add a feature, add a chain. If your feature needs something,
# put it in the chain so the next person doesn't have to debug it.

validate_chain_core() {
    echo ""
    echo "=== Core container dependencies ==="
    validate_dependency "git"     "version control"
    validate_dependency "curl"    "downloading packages"
    validate_dependency "jq"      "JSON processing (config, devcontainer rendering)"
    validate_dependency "node"    "Claude Code runtime"
    validate_dependency "npm"     "Claude Code installation"
    validate_dependency "python3" "hook scripts"
    validate_dependency "claude"  "Claude Code CLI"
}

validate_chain_github() {
    echo ""
    echo "=== GitHub toolchain ==="
    echo "(needed for: cloning private repos, skills install, PR workflows)"
    validate_dependency "gh"  "GitHub API, git credential helper, cloning private repos"
    validate_dependency "git" "version control"
    validate_github_auth
}

validate_chain_secrets() {
    echo ""
    echo "=== Secrets bootstrap chain ==="
    echo "(chain: az login → Key Vault → GitHub token → gh auth → clone repos → install skills)"
    validate_dependency "az"  "Azure Key Vault access (provides GitHub token + API keys)"
    validate_dependency "gh"  "GitHub auth (receives token from Key Vault)"
    validate_dependency "jq"  "parsing secrets config from .user-config.json"
    validate_azure_auth
    validate_github_auth
}

validate_chain_skills() {
    echo ""
    echo "=== Skills installation ==="
    echo "(needs: GitHub auth to clone psford/claude-env, psford/ed3d-plugins, psford/claude-config)"
    validate_dependency "gh"    "cloning private skill repos"
    validate_dependency "git"   "cloning repos"
    validate_dependency "claude" "skills target directory"
    validate_github_auth
    validate_path "$HOME/.claude/skills" "skills directory" "false"
}

validate_chain_hooks() {
    echo ""
    echo "=== Git hooks ==="
    validate_dependency "git"    "hook execution"
    validate_dependency "python3" "Python-based guard scripts"
    # Check that hooks are actually installed somewhere
    local hooks_found=0
    for repo_dir in /workspaces/*/; do
        if [[ -d "${repo_dir}.git/hooks" ]] && [[ -f "${repo_dir}.git/hooks/pre-commit" ]]; then
            echo "  ✓ hooks installed in ${repo_dir}"
            hooks_found=1
        fi
    done
    if [[ $hooks_found -eq 0 ]]; then
        echo "  ⚠ no git hooks installed in any /workspaces repo"
        VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
    fi
}

# ── Full validation ──────────────────────────────────────────────────────────

validate_all() {
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Dependency Validation                                  ║"
    echo "╚══════════════════════════════════════════════════════════╝"

    VALIDATION_ERRORS=0
    VALIDATION_WARNINGS=0

    validate_chain_core
    validate_chain_github
    validate_chain_secrets
    validate_chain_skills
    validate_chain_hooks

    echo ""
    echo "══════════════════════════════════════════════════════════"
    if [[ $VALIDATION_ERRORS -gt 0 ]]; then
        echo "FAILED: $VALIDATION_ERRORS error(s), $VALIDATION_WARNINGS warning(s)"
        echo ""
        echo "The bootstrap chain is broken. Fix the errors above before proceeding."
        echo "Common fix sequence: az login → bootstrap-secrets.sh → gh auth login"
        return 1
    elif [[ $VALIDATION_WARNINGS -gt 0 ]]; then
        echo "PASSED with $VALIDATION_WARNINGS warning(s)"
        return 0
    else
        echo "PASSED: all dependencies present and authenticated"
        return 0
    fi
}

# ── Entrypoint ───────────────────────────────────────────────────────────────

# When sourced, functions are available for selective use.
# When executed directly, run full validation.
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    validate_all
    exit $?
fi
