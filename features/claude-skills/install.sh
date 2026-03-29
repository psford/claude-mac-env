#!/bin/bash
set -e

# claude-skills Feature: Install ed3d plugin skills and psford custom skills

# Use the remote user's home directory for skills installation
SKILLS_DIR="${_REMOTE_USER_HOME}/.claude/skills"
ED3D_REPO="https://github.com/psford/ed3d-plugins.git"
CLAUDE_ENV_REPO="https://github.com/psford/claude-env.git"

echo "Installing Claude Code Skills..."

# Step 1: Verify claude CLI is available
if ! command -v claude &> /dev/null; then
    echo "Error: claude CLI not found. Ensure Claude Code is installed in the base image."
    exit 1
fi

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
    # ed3d-plugins expected structure: each skill is a directory with SKILL.md
    if [ -d "${ED3D_TEMP_DIR}/skills" ]; then
        for skill_dir in "${ED3D_TEMP_DIR}"/skills/*/; do
            if [ -f "${skill_dir}/SKILL.md" ]; then
                skill_name=$(basename "${skill_dir}")
                cp -r "${skill_dir}" "${SKILLS_DIR}/${skill_name}"
                echo "Installed skill: ${skill_name}"
            fi
        done
    else
        echo "Warning: ed3d-plugins structure not found. Skipping ed3d skills."
    fi
else
    echo "Warning: Failed to clone ed3d-plugins. Continuing with other skill sources."
fi

# Step 5: Clone psford custom skills from claude-env repository
echo "Cloning psford custom skills from ${CLAUDE_ENV_REPO}..."
if git clone --depth 1 "${CLAUDE_ENV_REPO}" "${CLAUDE_ENV_TEMP_DIR}" 2>/dev/null; then
    # psford custom skills expected structure: ~/.claude/skills/
    if [ -d "${CLAUDE_ENV_TEMP_DIR}/.claude/skills" ]; then
        for skill_dir in "${CLAUDE_ENV_TEMP_DIR}"/.claude/skills/*/; do
            if [ -f "${skill_dir}/SKILL.md" ]; then
                skill_name=$(basename "${skill_dir}")
                cp -r "${skill_dir}" "${SKILLS_DIR}/${skill_name}"
                echo "Installed skill: ${skill_name}"
            fi
        done
    else
        echo "Warning: psford custom skills structure not found. Continuing."
    fi
else
    echo "Warning: Failed to clone claude-env repository. Continuing."
fi

# Step 6: Set proper ownership of the skills directory for the remote user
if [ -n "${_REMOTE_USER}" ]; then
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${_REMOTE_USER_HOME}/.claude"
    echo "Set ownership of .claude directory to ${_REMOTE_USER}"
fi

# Step 7: Verify skills are installed
echo "Verifying installed skills..."
if [ "$(ls -A ${SKILLS_DIR})" ]; then
    echo "Successfully installed $(ls -1 ${SKILLS_DIR} | wc -l) skill(s):"
    ls -1 "${SKILLS_DIR}" | sed 's/^/  - /'
else
    echo "Warning: No skills were installed. Check repository structure."
fi

echo "Claude Code Skills feature installed successfully."
