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

# ── Plugin/marketplace tools ─────────────────────────────────────────────────

# Clone a repo to a target directory (for marketplace installation)
# Stdout: path to cloned directory
clone_repo() {
    local url="$1"
    local target="$2"
    require_command git
    if [ -z "$url" ]; then
        echo "clone_failed:url is empty" >&2
        return 1
    fi
    # If target already exists and is a git repo, pull instead of clone
    if [ -d "$target/.git" ]; then
        if git -C "$target" pull --ff-only >/dev/null 2>&1; then
            echo "$target"
            return 0
        fi
    fi
    mkdir -p "$(dirname "$target")"
    if ! git clone --depth 1 "$url" "$target" 2>&1; then
        echo "clone_failed:git clone failed for $url" >&2
        return 1
    fi
    echo "$target"
}

# Install a marketplace by cloning it into ~/.claude/plugins/marketplaces/
# Stdout: path to installed marketplace
install_marketplace() {
    local url="$1"
    local name="$2"
    local marketplaces_dir="${HOME}/.claude/plugins/marketplaces"
    mkdir -p "$marketplaces_dir"
    clone_repo "$url" "$marketplaces_dir/$name"
}

# Register a marketplace in settings.json so Claude Code discovers it
# Adds to extraKnownMarketplaces with the correct container path
register_marketplace() {
    local name="$1"
    local settings_path="${HOME}/.claude/settings.json"
    local marketplace_path="${HOME}/.claude/plugins/marketplaces/${name}"

    require_dir "$marketplace_path"
    require_command jq

    if [ ! -f "$settings_path" ]; then
        echo '{}' > "$settings_path"
    fi

    local updated
    updated=$(jq --arg name "$name" --arg path "$marketplace_path" '
        .extraKnownMarketplaces[$name] = {
            "source": {
                "source": "directory",
                "path": $path
            }
        }
    ' "$settings_path") || {
        echo "json_merge_failed:failed to register marketplace $name" >&2
        return 1
    }
    echo "$updated" > "$settings_path"
    ensure_valid_json "$settings_path"
}

# Enable plugins from a marketplace in settings.json
# Takes a marketplace name and a list of plugin names
enable_plugins() {
    local marketplace="$1"
    shift
    local settings_path="${HOME}/.claude/settings.json"

    require_command jq

    if [ ! -f "$settings_path" ]; then
        echo '{}' > "$settings_path"
    fi

    local updated
    updated="$(cat "$settings_path")"
    for plugin in "$@"; do
        updated=$(echo "$updated" | jq --arg key "${plugin}@${marketplace}" '
            .enabledPlugins[$key] = true
        ') || {
            echo "json_merge_failed:failed to enable plugin $plugin" >&2
            return 1
        }
    done
    echo "$updated" > "$settings_path"
    ensure_valid_json "$settings_path"
}

# List plugins available in a marketplace
# Stdout: newline-separated plugin names
list_marketplace_plugins() {
    local marketplace_path="$1"
    require_dir "$marketplace_path"

    local manifest="$marketplace_path/.claude-plugin/marketplace.json"
    if [ -f "$manifest" ]; then
        jq -r '.plugins[].name' "$manifest" 2>/dev/null
    else
        # Fallback: look for plugin.json in subdirectories
        for plugin_dir in "$marketplace_path"/plugins/*/; do
            if [ -f "$plugin_dir/.claude-plugin/plugin.json" ]; then
                jq -r '.name' "$plugin_dir/.claude-plugin/plugin.json" 2>/dev/null
            fi
        done
    fi
}

# Legacy: Clone a skills repo to a temp directory (kept for backward compat)
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

# Legacy: Install skills from a source directory to a target directory
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

# Render devcontainer.json from template using jq
# All JSON manipulation via jq — zero bash string concatenation for JSON content.
render_devcontainer_json() {
    local config_path="$1"
    local template_path="$2"
    local output_path="$3"
    local repo_dir="${4:-$(pwd)}"

    require_file "$config_path"
    require_file "$template_path"
    require_command jq

    # Read config values
    local base_image
    base_image=$(jq -r '.baseImage // "ubuntu:24.04"' "$config_path")

    # Build features object: map feature names to GHCR URLs
    local features_json
    features_json=$(jq '
        .features // {} | to_entries |
        map({("ghcr.io/psford/claude-mac-env/\(.key):latest"): .value}) |
        if length > 0 then add else {} end
    ' "$config_path")

    # Build project mounts array
    local project_mounts
    project_mounts=$(jq -r '
        [.projectDirs // [] | .[] |
         "source=\(.),target=/workspaces/\(split("/") | last),type=bind"]
    ' "$config_path")

    # Build secrets-related mounts
    local config_abs_path
    config_abs_path=$(cd "$(dirname "$config_path")" && pwd)/$(basename "$config_path")
    local config_dir_abs
    config_dir_abs="$repo_dir/config"

    local secrets_mounts
    secrets_mounts=$(jq -n \
        --arg config_dir "$config_dir_abs" \
        --arg config_file "$config_abs_path" \
        '[
            "source=\($config_dir),target=/workspaces/.claude-mac-env/config,type=bind,readonly",
            "source=\($config_file),target=/workspaces/.claude-mac-env/.user-config.json,type=bind,readonly"
        ]')

    # Conditionally add .env file mount
    local provider
    provider=$(jq -r '.secrets.provider // ""' "$config_path")
    if [ "$provider" = "env" ]; then
        local env_file_path
        env_file_path=$(jq -r '.secrets.envFilePath // ""' "$config_path")
        if [ -n "$env_file_path" ]; then
            secrets_mounts=$(echo "$secrets_mounts" | jq --arg path "$env_file_path" \
                '. + ["source=\($path),target=/home/claude/.env,type=bind,readonly"]')
        fi
    fi

    # Build extensions array
    local extra_extensions
    extra_extensions=$(jq '
        if .features["csharp-tools"] then
            ["anthropics.claude-code", "ms-dotnettools.csharp"]
        else
            ["anthropics.claude-code"]
        end
    ' "$config_path")

    # Assemble the final JSON using the template as base
    local output_dir
    output_dir=$(dirname "$output_path")
    mkdir -p "$output_dir"

    jq \
        --arg base_image "$base_image" \
        --argjson features "$features_json" \
        --argjson project_mounts "$project_mounts" \
        --argjson secrets_mounts "$secrets_mounts" \
        --argjson extensions "$extra_extensions" \
        '
        .build.args.BASE_IMAGE = $base_image |
        .features = $features |
        .mounts = ($project_mounts + $secrets_mounts + [.mounts[] | select(contains("localEnv"))]) |
        .customizations.vscode.extensions = $extensions
        ' "$template_path" > "$output_path"

    # Postconditions
    ensure_file_exists "$output_path"
    ensure_valid_json "$output_path"
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
