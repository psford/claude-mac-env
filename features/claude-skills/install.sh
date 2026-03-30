#!/bin/bash
set -e

# claude-skills Feature: Install ed3d plugin skills and psford custom skills

# Step 0: Validate ALL dependencies before doing anything
# This exists because we once shipped a container with no gh, no az, and no
# skills — the entire tooling layer was missing because nobody checked.
REQUIRED_CMDS=("git" "claude" "gh")
MISSING=()
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING+=("$cmd")
    fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "ERROR: Missing required dependencies: ${MISSING[*]}"
    echo "These must be installed in the Dockerfile BEFORE this Feature runs."
    echo "Cannot install skills without: ${MISSING[*]}"
    exit 1
fi

# Verify GitHub auth (needed for private repos)
if ! gh auth status &>/dev/null 2>&1; then
    echo "ERROR: gh is not authenticated. Cannot clone private skill repos."
    echo "Run 'gh auth login' or ensure GITHUB_TOKEN is set before this Feature runs."
    exit 1
fi

# Use the remote user's home directory for skills installation
SKILLS_DIR="${_REMOTE_USER_HOME}/.claude/skills"
ED3D_REPO="https://github.com/ed3dai/ed3d-plugins.git"

echo "Installing Claude Code Skills..."

echo "Claude CLI version: $(claude --version)"

# Step 2: Create skills directory structure
mkdir -p "${SKILLS_DIR}"
echo "Created skills directory: ${SKILLS_DIR}"

# Step 3: Create temporary directories with cleanup function
ED3D_TEMP_DIR=$(mktemp -d)
CLAUDE_ENV_TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$ED3D_TEMP_DIR" "$CLAUDE_ENV_TEMP_DIR"
}
trap cleanup EXIT

# Step 4: Clone ed3d plugin skills repository
echo "Cloning ed3d plugin skills from ${ED3D_REPO}..."
if git clone --depth 1 "${ED3D_REPO}" "${ED3D_TEMP_DIR}" 2>/dev/null; then
    # ed3d-plugins structure: plugins/*/skills/*/SKILL.md
    FOUND_SKILLS=0
    for skill_dir in "${ED3D_TEMP_DIR}"/plugins/*/skills/*/; do
        if [ -f "${skill_dir}/SKILL.md" ]; then
            skill_name=$(basename "${skill_dir}")
            cp -r "${skill_dir}" "${SKILLS_DIR}/${skill_name}"
            echo "Installed skill: ${skill_name}"
            FOUND_SKILLS=$((FOUND_SKILLS + 1))
        fi
    done
    if [ "$FOUND_SKILLS" -eq 0 ]; then
        echo "ERROR: ed3d-plugins cloned but no skills found at plugins/*/skills/*/SKILL.md"
        echo "Repository structure may have changed. Check ${ED3D_REPO}"
        exit 1
    fi
    echo "Installed ${FOUND_SKILLS} ed3d skills"
else
    echo "Warning: Failed to clone ed3d-plugins. Continuing with other skill sources."
fi

# Step 5: Clone psford custom skills from claude-config repository
CLAUDE_CONFIG_REPO="https://github.com/psford/claude-config.git"
echo "Cloning psford custom skills from ${CLAUDE_CONFIG_REPO}..."
if git clone --depth 1 "${CLAUDE_CONFIG_REPO}" "${CLAUDE_ENV_TEMP_DIR}" 2>/dev/null; then
    # claude-config structure: plugins/patricks-workflow/skills/*/SKILL.md
    FOUND_CONFIG_SKILLS=0
    for skill_dir in "${CLAUDE_ENV_TEMP_DIR}"/plugins/*/skills/*/; do
        if [ -f "${skill_dir}/SKILL.md" ]; then
            skill_name=$(basename "${skill_dir}")
            cp -r "${skill_dir}" "${SKILLS_DIR}/${skill_name}"
            echo "Installed skill: ${skill_name}"
            FOUND_CONFIG_SKILLS=$((FOUND_CONFIG_SKILLS + 1))
        fi
    done
    if [ "$FOUND_CONFIG_SKILLS" -eq 0 ]; then
        echo "WARNING: claude-config cloned but no skills found at plugins/*/skills/*/SKILL.md"
    else
        echo "Installed ${FOUND_CONFIG_SKILLS} psford skills"
    fi
else
    echo "WARNING: Failed to clone claude-config. Continuing without psford skills."
fi

# Step 6: Set proper ownership of the skills directory for the remote user
if [ -n "${_REMOTE_USER}" ]; then
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${_REMOTE_USER_HOME}/.claude"
    echo "Set ownership of .claude directory to ${_REMOTE_USER}"
fi

# Step 7: Verify skills are installed
echo "Verifying installed skills..."
if [ "$(ls -A "${SKILLS_DIR}")" ]; then
    echo "Successfully installed $(find "${SKILLS_DIR}" -mindepth 1 -maxdepth 1 -type d | wc -l) skill(s):"
    find "${SKILLS_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '  - %f\n' | sort
else
    echo "Warning: No skills were installed. Check repository structure."
fi

echo "Claude Code Skills feature installed successfully."
