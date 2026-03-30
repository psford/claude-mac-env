#!/usr/bin/env bash
# bootstrap.sh — Layer 3 orchestrator
#
# postCreateCommand entry point. Chains Layer 1 tools and Layer 2 error
# handling into a 6-step guided flow. Each step is idempotent — if already
# done, prints ✓ and moves on. If killed and re-run, resumes from the
# first incomplete step.
#
# Usage:
#   bash config/bootstrap.sh                # Full bootstrap
#   bash config/bootstrap.sh --secrets-only # Re-run just secrets loading

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/tools.sh
source "${SCRIPT_DIR}/lib/tools.sh"
# shellcheck source=lib/errors.sh
source "${SCRIPT_DIR}/lib/errors.sh"

# ── UX helpers ───────────────────────────────────────────────────────────────

TOTAL_STEPS=6

step_header() {
    local n="$1"
    local message="$2"
    echo ""
    echo "Step ${n} of ${TOTAL_STEPS}: ${message}"
}

step_skip() {
    local message="$1"
    echo "  ✓ ${message}"
}

step_done() {
    local message="$1"
    echo "  ✓ ${message}"
}

step_error() {
    local message="$1"
    echo "  ✗ ${message}"
}

# Parse action:message from Layer 2 response
parse_action() {
    echo "${1%%:*}"
}

parse_message() {
    echo "${1#*:}"
}

# ── Step functions ───────────────────────────────────────────────────────────

step_check_tools() {
    step_header 1 "Checking tools"
    local required_tools=("git" "curl" "jq" "node" "python3" "claude")
    local all_ok=true

    for tool in "${required_tools[@]}"; do
        if check_tool "$tool" >/dev/null 2>&1; then
            echo "  ✓ ${tool}"
        else
            local result
            result=$(handle_error "missing_tool" "$tool" "step_check_tools")
            local action
            action=$(parse_action "$result")
            local message
            message=$(parse_message "$result")
            step_error "${tool}: ${message}"
            if [ "$action" = "abort" ]; then
                echo ""
                echo "Cannot continue — required tools are missing."
                exit 1
            fi
            all_ok=false
        fi
    done

    if [ "$all_ok" = true ]; then
        step_done "All tools present"
    fi
}

step_github_auth() {
    step_header 2 "Connecting to GitHub"

    if [[ "${BOOTSTRAP_MOCK_AUTH:-}" == "1" ]]; then
        step_skip "Auth skipped (mock mode)"
        return 0
    fi

    local auth_result
    auth_result=$(check_gh_auth 2>/dev/null) || {
        local err_result
        err_result=$(handle_error "gh_auth_error" "check failed" "step_github_auth")
        step_error "$(parse_message "$err_result")"
        return 1
    }

    if [[ "$auth_result" == authed:* ]]; then
        local username="${auth_result#authed:}"
        step_skip "Already connected to GitHub as ${username}"
    else
        echo "  To install skills and access your repos, we need to connect to GitHub."
        echo "  A browser window will open for you to log in."
        echo ""

        local success=false
        while true; do
            if run_gh_login 2>/dev/null; then
                success=true
                break
            fi
            local result
            result=$(handle_error "gh_login_failed" "" "step_github_auth")
            local action
            action=$(parse_action "$result")
            local message
            message=$(parse_message "$result")
            if [ "$action" = "abort" ]; then
                step_error "$message"
                exit 1
            fi
            echo "  ${message}"
        done

        if [ "$success" = true ]; then
            step_done "Connected to GitHub"
        fi
    fi

    # Configure credential helper silently
    if ! run_gh_setup_git >/dev/null 2>&1; then
        local result
        result=$(handle_error "gh_setup_git_failed" "" "step_github_auth")
        local action
        action=$(parse_action "$result")
        if [ "$action" = "retry" ]; then
            run_gh_setup_git >/dev/null 2>&1 || {
                result=$(handle_error "gh_setup_git_failed" "" "step_github_auth")
                # skip — non-critical
            }
        fi
    fi
}

step_azure_auth() {
    local github_user="$1"
    local secrets_provider="${2:-}"

    if [[ "${BOOTSTRAP_MOCK_AUTH:-}" == "1" ]]; then
        return 0
    fi

    # Determine if Azure is needed
    local azure_needed=false
    local azure_reason=""

    if [ "$github_user" = "psford" ]; then
        azure_needed=true
        azure_reason="Your secrets are stored in Azure Key Vault"
    elif [ "$secrets_provider" = "azure" ]; then
        azure_needed=true
        azure_reason="Your secrets config uses Azure Key Vault"
    fi

    if [ "$azure_needed" = false ]; then
        return 0
    fi

    step_header 3 "Connecting to Azure"

    local auth_result
    auth_result=$(check_az_auth 2>/dev/null) || {
        local err_result
        err_result=$(handle_error "az_auth_error" "check failed" "step_azure_auth")
        step_error "$(parse_message "$err_result")"
        return 1
    }

    if [[ "$auth_result" == authed:* ]]; then
        local subscription="${auth_result#authed:}"
        step_skip "Already connected to Azure (${subscription})"
        return 0
    fi

    echo "  ${azure_reason}, so we need to connect to Azure."

    # For non-psford, offer skip option
    if [ "$github_user" != "psford" ] && [ -t 0 ]; then
        echo "  You can connect now, or skip and add Azure later."
        read -rp "  Connect to Azure now? [Y/n] " answer
        if [[ "$answer" =~ ^[Nn] ]]; then
            step_skip "Skipped Azure — you can add this later with: az login"
            return 0
        fi
    fi

    while true; do
        if run_az_login 2>/dev/null; then
            step_done "Connected to Azure"
            return 0
        fi
        local result
        result=$(handle_error "az_login_failed" "" "step_azure_auth")
        local action
        action=$(parse_action "$result")
        local message
        message=$(parse_message "$result")
        if [ "$action" = "abort" ]; then
            step_error "$message"
            return 1
        fi
        echo "  ${message}"
    done
}

step_install_skills() {
    local github_user="$1"
    step_header 4 "Installing skills"

    # Idempotency: check if skills are already installed
    local skills_dir="${HOME}/.claude/skills"
    mkdir -p "$skills_dir"

    local skill_count=0
    if [ -d "$skills_dir" ]; then
        skill_count=$(find "$skills_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l) || true
    fi

    if [ "$skill_count" -gt 0 ] && [ -d "$skills_dir/brainstorming" ]; then
        step_skip "Skills already installed (${skill_count} skills)"
        return 0
    fi

    # Clone and install ed3d-plugins
    local ed3d_url="https://github.com/ed3dai/ed3d-plugins.git"
    local ed3d_path=""
    while true; do
        ed3d_path=$(clone_skills_repo "$ed3d_url" "ed3d-plugins" 2>/dev/null) && break
        local result
        result=$(handle_error "clone_failed" "$ed3d_url" "step_install_skills")
        local action
        action=$(parse_action "$result")
        local message
        message=$(parse_message "$result")
        if [ "$action" != "retry" ]; then
            step_error "$message"
            return 1
        fi
        echo "  ${message}"
    done

    local ed3d_count
    ed3d_count=$(install_skills "$ed3d_path" "$skills_dir" 2>/dev/null) || {
        local result
        result=$(handle_error "no_skills_found" "ed3d-plugins" "step_install_skills")
        step_error "$(parse_message "$result")"
        rm -rf "$(dirname "$ed3d_path")"
        return 1
    }
    rm -rf "$(dirname "$ed3d_path")"
    echo "  Installed ${ed3d_count} ed3d skills"

    # Clone and install psford/claude-config
    local config_url="https://github.com/psford/claude-config.git"
    local config_path=""
    if config_path=$(clone_skills_repo "$config_url" "claude-config" 2>/dev/null); then
        local config_count
        config_count=$(install_skills "$config_path" "$skills_dir" 2>/dev/null) || true
        if [ -n "$config_count" ] && [ "$config_count" -gt 0 ]; then
            echo "  Installed ${config_count} psford skills"
        fi
        rm -rf "$(dirname "$config_path")"
    else
        echo "  Note: psford/claude-config not available — continuing with ed3d skills"
    fi

    local total
    total=$(find "$skills_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l) || true
    step_done "Installed ${total} skills total"
}

step_configure_claude() {
    step_header 5 "Configuring Claude Code"

    local settings_path="${HOME}/.claude/settings.json"
    mkdir -p "${HOME}/.claude"

    # Idempotency: check if hooks are already configured
    if [ -f "$settings_path" ] && jq -e '.hooks.PreToolUse' "$settings_path" >/dev/null 2>&1; then
        step_skip "Claude Code hooks already configured"
    else
        # Build hook config fragment
        local hook_fragment
        hook_fragment=$(cat <<'HOOKS_JSON'
{
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Write(*)", "Edit(*)", "Glob(*)", "Grep(*)", "Agent(*)"],
    "defaultMode": "bypassPermissions",
    "additionalDirectories": ["/home/claude/.claude"]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.command' | grep -qE 'git commit' && { staged=$(git diff --cached --stat 2>/dev/null | tail -1); files=$(echo \"$staged\" | grep -oE '[0-9]+ file' | grep -oE '[0-9]+'); if [ \"${files:-0}\" -gt 10 ]; then echo '{\"decision\":\"block\",\"reason\":\"Commit touches '\"$files\"' files. Break into smaller atomic commits.\"}'; else echo '{}'; fi; } || echo '{}'",
            "if": "Bash(git commit*)",
            "statusMessage": "Checking commit atomicity..."
          },
          {
            "type": "command",
            "command": "jq -r '.tool_input.command' | { read -r cmd; branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); if echo \"$cmd\" | grep -qE 'git push' && echo \"$branch\" | grep -qE '^(main|master)$'; then echo '{\"decision\":\"block\",\"reason\":\"Cannot push directly to '\"$branch\"'. Create a PR instead.\"}'; else echo '{}'; fi; }",
            "if": "Bash(git push*)",
            "statusMessage": "Checking branch protection..."
          },
          {
            "type": "command",
            "command": "jq -r '.tool_input.command' | { read -r cmd; if echo \"$cmd\" | grep -qE 'git push.*--force|git push.*-f'; then echo '{\"decision\":\"block\",\"reason\":\"Force push is blocked. Use --force-with-lease if absolutely necessary.\"}'; else echo '{}'; fi; }",
            "if": "Bash(git push*)",
            "statusMessage": "Checking for force push..."
          },
          {
            "type": "command",
            "command": "jq -r '.tool_input.command' | { read -r cmd; if echo \"$cmd\" | grep -qE 'rm -rf /|rm -rf ~|rm -rf \\$HOME'; then echo '{\"decision\":\"block\",\"reason\":\"Destructive rm -rf on critical path blocked.\"}'; else echo '{}'; fi; }",
            "if": "Bash(rm -rf*)",
            "statusMessage": "Checking destructive commands..."
          }
        ]
      }
    ]
  },
  "skipDangerousModePermissionPrompt": true
}
HOOKS_JSON
        )

        if merge_settings_json "$hook_fragment" "$settings_path" >/dev/null 2>&1; then
            step_done "Claude Code hooks configured"
        else
            local result
            result=$(handle_error "json_merge_failed" "" "step_configure_claude")
            step_error "$(parse_message "$result")"
            return 1
        fi
    fi

    # Fix gh symlink if needed
    local gh_path
    gh_path=$(command -v gh 2>/dev/null) || true
    if [ -n "$gh_path" ] && [ "$gh_path" != "/usr/local/bin/gh" ] && [ ! -e "/usr/local/bin/gh" ]; then
        if fix_symlink "$gh_path" "/usr/local/bin/gh" >/dev/null 2>&1; then
            echo "  ✓ gh symlink created"
        else
            # Non-critical — skip silently
            true
        fi
    fi
}

step_load_secrets() {
    local secrets_provider="$1"
    local config_path="$2"

    step_header 6 "Loading secrets"

    # Skip if no provider configured
    if [ -z "$secrets_provider" ] || [ "$secrets_provider" = "none" ] || [ "$secrets_provider" = "skip" ]; then
        step_skip "No secrets provider configured — skipping"
        return 0
    fi

    # Idempotency: check if secrets are already loaded and recent
    local secrets_file="${HOME}/.secrets.env"
    if [ -f "$secrets_file" ] && [ -s "$secrets_file" ]; then
        local age_seconds
        age_seconds=$(( $(date +%s) - $(stat -c %Y "$secrets_file" 2>/dev/null || echo 0) ))
        if [ "$age_seconds" -lt 86400 ]; then
            step_skip "Secrets loaded (less than 24h old)"
            return 0
        fi
    fi

    if load_secrets "$secrets_provider" "$config_path" >/dev/null 2>&1; then
        step_done "Secrets loaded from ${secrets_provider} provider"
    else
        local result
        result=$(handle_error "secrets_failed" "$secrets_provider" "step_load_secrets")
        local message
        message=$(parse_message "$result")
        echo "  ${message}"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    local secrets_only=false

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --secrets-only) secrets_only=true; shift ;;
            *) shift ;;
        esac
    done

    # Read config
    local config_path="${USER_CONFIG:-/workspaces/.claude-mac-env/.user-config.json}"
    local github_user=""
    local secrets_provider=""

    if [ -f "$config_path" ]; then
        github_user=$(jq -r '.githubUser // ""' "$config_path" 2>/dev/null) || true
        secrets_provider=$(jq -r '.secrets.provider // ""' "$config_path" 2>/dev/null) || true
    fi

    echo ""
    echo "══════════════════════════════════════════"
    echo "  Bootstrap v2 — Setting up your environment"
    echo "══════════════════════════════════════════"

    if [ "$secrets_only" = true ]; then
        step_load_secrets "$secrets_provider" "$config_path"
    else
        step_check_tools
        step_github_auth
        step_azure_auth "$github_user" "$secrets_provider"
        step_install_skills "$github_user"
        step_configure_claude
        step_load_secrets "$secrets_provider" "$config_path"
    fi

    echo ""
    echo "══════════════════════════════════════════"
    echo "  ✓ Environment ready!"
    echo "══════════════════════════════════════════"
    echo ""
}

main "$@"
