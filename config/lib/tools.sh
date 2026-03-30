#!/usr/bin/env bash
# tools.sh — Layer 1 design-by-contract tool functions
#
# Each function:
#   - Validates preconditions via contracts.sh
#   - Does one job
#   - Validates postconditions
#   - Returns exit 0 + stdout (success) or exit 1 + stderr (failure)
#   - No UX, no retries, no friendly messages
#
# Error format on stderr: error_type:detail_message

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=contracts.sh
source "${TOOLS_DIR}/contracts.sh"

# ── Auth tools ───────────────────────────────────────────────────────────────

# Check if a CLI tool is available and responds to --version
check_tool() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        echo "missing_tool:command '$cmd' not found on PATH" >&2
        return 1
    fi
    local version
    version=$("$cmd" --version 2>&1 | head -1) || true
    echo "$version"
}

# Check GitHub auth status
# Stdout: "authed:<username>" or "not_authed"
# Exit 0 for both states. Exit 1 only for unexpected errors.
check_gh_auth() {
    require_command gh
    local output
    if output=$(gh auth status 2>&1); then
        local username
        username=$(echo "$output" | grep -oP 'Logged in to [^ ]+ as \K[^ ]+' | head -1) || true
        if [ -z "$username" ]; then
            username=$(echo "$output" | grep -oP 'account \K[^ ]+' | head -1) || true
        fi
        echo "authed:${username:-unknown}"
    else
        if echo "$output" | grep -qi "not logged in\|no oauth token\|authentication\|not authenticated"; then
            echo "not_authed"
        else
            echo "gh_auth_error:unexpected error from gh auth status: $output" >&2
            return 1
        fi
    fi
}

# Check Azure auth status
# Stdout: "authed:<subscription>" or "not_authed"
# Exit 0 for both states. Exit 1 only for unexpected errors.
check_az_auth() {
    require_command az
    local output
    if output=$(az account show 2>&1); then
        local subscription
        subscription=$(echo "$output" | jq -r '.name // .id // "unknown"' 2>/dev/null) || true
        echo "authed:${subscription:-unknown}"
    else
        if echo "$output" | grep -qi "az login\|not logged in\|no subscription\|please run"; then
            echo "not_authed"
        else
            echo "az_auth_error:unexpected error from az account show: $output" >&2
            return 1
        fi
    fi
}

# Run gh auth login interactively
run_gh_login() {
    require_command gh
    require_tty
    if ! gh auth login --web --git-protocol https 2>&1; then
        echo "gh_login_failed:gh auth login did not complete successfully" >&2
        return 1
    fi
}

# Configure git credential helper via gh
run_gh_setup_git() {
    require_command gh
    if ! gh auth setup-git 2>&1; then
        echo "gh_setup_git_failed:gh auth setup-git failed" >&2
        return 1
    fi
    # Postcondition: credential helper is configured
    local helper
    helper=$(git config credential.helper 2>/dev/null) || true
    if ! echo "$helper" | grep -q "gh"; then
        echo "gh_setup_git_failed:credential.helper does not contain 'gh' after setup" >&2
        return 1
    fi
}

# Run az login interactively
run_az_login() {
    require_command az
    require_tty
    if ! az login 2>&1; then
        echo "az_login_failed:az login did not complete successfully" >&2
        return 1
    fi
}

# ── Skills tools ─────────────────────────────────────────────────────────────

# Clone a skills repo to a temp directory
# Stdout: path to cloned directory
# Caller is responsible for cleaning up the returned temp directory.
clone_skills_repo() {
    local url="$1"
    local name="$2"
    require_command git
    if [ -z "$url" ]; then
        echo "clone_failed:url is empty" >&2
        return 1
    fi
    local temp_dir
    temp_dir=$(mktemp -d)
    if ! git clone --depth 1 "$url" "$temp_dir/$name" 2>&1; then
        rm -rf "$temp_dir"
        echo "clone_failed:git clone failed for $url" >&2
        return 1
    fi
    echo "$temp_dir/$name"
}

# Install skills from a source directory to a target directory
# Finds plugins/*/skills/*/SKILL.md in source_dir, copies each skill dir to target_dir
# Stdout: count of skills installed
install_skills() {
    local source_dir="$1"
    local target_dir="$2"
    require_dir "$source_dir"
    require_dir "$target_dir"

    local count=0
    for skill_dir in "$source_dir"/plugins/*/skills/*/; do
        if [ -f "${skill_dir}/SKILL.md" ]; then
            local skill_name
            skill_name=$(basename "$skill_dir")
            cp -r "$skill_dir" "$target_dir/$skill_name"
            ((count++)) || true
        fi
    done

    if [ "$count" -eq 0 ]; then
        echo "no_skills_found:no skills found at plugins/*/skills/*/SKILL.md in $source_dir" >&2
        return 1
    fi
    echo "$count"
}

# ── Config tools ─────────────────────────────────────────────────────────────

# Merge a JSON config fragment into a target settings file
# If target exists, deep-merges. If not, creates new file from fragment.
merge_settings_json() {
    local config_fragment="$1"
    local target_path="$2"
    require_command jq

    # Validate fragment is valid JSON
    if ! echo "$config_fragment" | jq . >/dev/null 2>&1; then
        echo "json_merge_failed:config_fragment is not valid JSON" >&2
        return 1
    fi

    local target_dir
    target_dir=$(dirname "$target_path")
    require_dir "$target_dir"

    if [ -f "$target_path" ]; then
        # Deep merge: existing * fragment (fragment wins on conflict)
        local merged
        merged=$(jq -s '.[0] * .[1]' "$target_path" <(echo "$config_fragment")) || {
            echo "json_merge_failed:jq merge failed" >&2
            return 1
        }
        echo "$merged" > "$target_path"
    else
        echo "$config_fragment" | jq . > "$target_path"
    fi

    # Postcondition
    ensure_valid_json "$target_path"
}

# Create a symlink if needed
fix_symlink() {
    local source="$1"
    local target="$2"
    require_file "$source"

    # Already correct?
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
        return 0
    fi

    # If target exists but points elsewhere, remove it
    if [ -e "$target" ] || [ -L "$target" ]; then
        rm -f "$target"
    fi

    ln -s "$source" "$target" || {
        echo "symlink_failed:could not create symlink $target -> $source" >&2
        return 1
    }

    # Postcondition: target resolves
    ensure_exit_zero "symlink target responds" "$target" --version
}

# Load secrets using the existing provider architecture
load_secrets() {
    local provider="$1"
    local config_path="$2"
    require_file "$config_path"

    local config_dir
    config_dir=$(dirname "$config_path")

    local interface_path="$config_dir/secrets-interface.sh"
    local provider_path="$config_dir/secrets-${provider}.sh"

    require_file "$interface_path"
    require_file "$provider_path"

    # Source the provider (it defines secrets_validate and secrets_inject)
    # shellcheck source=/dev/null
    USER_CONFIG="$config_path" source "$provider_path"

    if ! secrets_validate; then
        echo "secrets_failed:secrets_validate failed for provider '$provider'" >&2
        return 1
    fi

    if ! secrets_inject; then
        echo "secrets_failed:secrets_inject failed for provider '$provider'" >&2
        return 1
    fi
}
