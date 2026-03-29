#!/bin/bash
set -euo pipefail

# psford-personal Feature: Install project-specific guards, helpers, and Azure tooling

echo "Installing psford Personal Development Tools..."

# Step 1: Detect package manager
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
DETECT_SCRIPT="$(cd "${SCRIPT_DIR}/../.." && pwd)/detect-package-manager.sh"

if [ ! -f "$DETECT_SCRIPT" ]; then
    echo "Error: detect-package-manager.sh not found at ${DETECT_SCRIPT}"
    exit 1
fi

PKG_MANAGER=$("$DETECT_SCRIPT") || {
    echo "Error: Failed to detect package manager"
    exit 1
}

echo "Detected package manager: ${PKG_MANAGER}"

# Step 2: Install Azure CLI if option enabled
if [ "${INSTALLAZURECLI}" = "true" ]; then
    echo "Installing Azure CLI..."
    case "${PKG_MANAGER}" in
        apt)
            apt-get update
            apt-get install -y azure-cli || {
                echo "Warning: Failed to install azure-cli via apt"
            }
            ;;
        dnf)
            dnf install -y azure-cli || {
                echo "Warning: Failed to install azure-cli via dnf"
            }
            ;;
        apk)
            apk add --no-cache azure-cli || {
                echo "Warning: Failed to install azure-cli via apk"
            }
            ;;
        *)
            echo "Warning: Unsupported package manager for Azure CLI: ${PKG_MANAGER}"
            ;;
    esac

    # Verify Azure CLI installation
    if command -v az &>/dev/null; then
        echo "Verifying Azure CLI installation..."
        az --version
    else
        echo "Warning: Azure CLI not found after installation attempt"
    fi
else
    echo "Skipping Azure CLI installation (installAzureCli=false)"
fi

# Step 3: Install Python dependencies
echo "Installing Python dependencies for helpers..."
pip3 install --upgrade pip || true
pip3 install slack-bolt slack-sdk requests anthropic || {
    echo "Warning: Some Python dependencies may not have installed successfully"
}

# Step 4: Create hooks and helpers directories
HOOKS_DIR="${_REMOTE_USER_HOME}/.claude/hooks"
HELPERS_DIR="${_REMOTE_USER_HOME}/.claude/helpers"

mkdir -p "${HOOKS_DIR}"
mkdir -p "${HELPERS_DIR}"

echo "Copying project-specific guard scripts to ${HOOKS_DIR}..."

# Step 5: Copy project-specific guard scripts
HOOKS_SOURCE_DIR="${SCRIPT_DIR}/hooks"

if [ ! -d "${HOOKS_SOURCE_DIR}" ]; then
    echo "Warning: Hooks source directory not found at ${HOOKS_SOURCE_DIR}"
else
    for hook_file in "${HOOKS_SOURCE_DIR}"/*.py; do
        if [ -f "$hook_file" ]; then
            hook_name=$(basename "$hook_file")
            cp "$hook_file" "${HOOKS_DIR}/${hook_name}"
            chmod +x "${HOOKS_DIR}/${hook_name}"
            echo "Installed guard: ${hook_name}"
        fi
    done
fi

# Step 6: Copy psford-specific helper scripts
HELPERS_SOURCE_DIR="${SCRIPT_DIR}/helpers"

echo "Copying psford-specific helper scripts to ${HELPERS_DIR}..."

if [ ! -d "${HELPERS_SOURCE_DIR}" ]; then
    echo "Warning: Helpers source directory not found at ${HELPERS_SOURCE_DIR}"
else
    for helper_file in "${HELPERS_SOURCE_DIR}"/*; do
        if [ -f "$helper_file" ]; then
            helper_name=$(basename "$helper_file")
            cp "$helper_file" "${HELPERS_DIR}/${helper_name}"
            chmod +x "${HELPERS_DIR}/${helper_name}" || true
            echo "Installed helper: ${helper_name}"
        fi
    done
fi

# Step 7: Fix ownership
if [ -n "${_REMOTE_USER}" ]; then
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${HOOKS_DIR}" "${HELPERS_DIR}"
    echo "Fixed ownership of hooks and helpers directories for ${_REMOTE_USER}"
fi

echo ""
echo "psford Personal Development Tools installed successfully!"
echo ""
