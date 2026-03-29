#!/bin/bash
set -e

# universal-hooks Feature: Install git and Claude hooks

HOOKS_INSTALL_DIR="/usr/local/share/claude-hooks"
HOOKS_SOURCE_DIR="$(dirname "${BASH_SOURCE[0]}")/hooks"

echo "Installing Universal Git & Claude Hooks..."

# Step 1: Create the hooks directory
mkdir -p "${HOOKS_INSTALL_DIR}"
echo "Created hooks directory: ${HOOKS_INSTALL_DIR}"

# Step 2: Copy hook scripts from bundled hooks/ directory
if [ ! -d "$HOOKS_SOURCE_DIR" ]; then
    echo "Error: Hooks source directory not found at ${HOOKS_SOURCE_DIR}"
    exit 1
fi

HOOK_COUNT=0
for hook_script in "${HOOKS_SOURCE_DIR}"/*.sh; do
    if [ -f "$hook_script" ]; then
        hook_name=$(basename "$hook_script")
        cp "$hook_script" "${HOOKS_INSTALL_DIR}/${hook_name}"
        chmod +x "${HOOKS_INSTALL_DIR}/${hook_name}"
        echo "Installed hook: ${hook_name}"
        ((HOOK_COUNT++))
    fi
done

if [ $HOOK_COUNT -eq 0 ]; then
    echo "Error: No hook scripts found in ${HOOKS_SOURCE_DIR}"
    exit 1
fi

echo "Installed $HOOK_COUNT hook(s)"

# Step 3: Configure git to use global hooks directory
# This approach installs hooks system-wide using git's templatedir
# However, the most portable method is to configure core.hooksPath

# Create a git template directory for hooks
GIT_TEMPLATE_DIR="/usr/local/share/git-templates/hooks"
mkdir -p "$GIT_TEMPLATE_DIR"

# Copy hooks to git template directory
for hook_script in "${HOOKS_SOURCE_DIR}"/*.sh; do
    if [ -f "$hook_script" ]; then
        hook_name=$(basename "$hook_script" .sh)
        cp "$hook_script" "${GIT_TEMPLATE_DIR}/${hook_name}"
        chmod +x "${GIT_TEMPLATE_DIR}/${hook_name}"
    fi
done

# Configure git system-wide to use the hooks directory
git config --system core.hooksPath "${HOOKS_INSTALL_DIR}"
echo "Configured git system-wide: core.hooksPath=${HOOKS_INSTALL_DIR}"

# Also set the template directory for new repositories
git config --system init.templateDir /usr/local/share/git-templates
echo "Configured git system-wide: init.templateDir=/usr/local/share/git-templates"

echo ""
echo "Universal Git & Claude Hooks installed successfully!"
echo ""
echo "Hooks installed:"
ls -1 "${HOOKS_INSTALL_DIR}" | sed 's/^/  - /'
echo ""
echo "These hooks will be used by git for new repositories and when explicitly configured."
echo "To bypass any hook, use: git <command> --no-verify"
