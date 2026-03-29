#!/bin/bash
set -euo pipefail

# csharp-tools Feature: Install .NET SDK and C# development tools

echo "Installing C# / .NET Development Tools..."

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

# Step 2: Install .NET SDK based on package manager
case "${PKG_MANAGER}" in
    apt)
        echo "Installing .NET SDK ${DOTNETVERSION} via apt..."
        apt-get update
        apt-get install -y wget ca-certificates

        # Add Microsoft package repository for Ubuntu/Debian
        wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
        chmod +x /tmp/dotnet-install.sh
        /tmp/dotnet-install.sh --version "${DOTNETVERSION}" --install-dir /usr/local/bin

        # Create symlink for convenience
        ln -sf /usr/local/bin/dotnet /usr/bin/dotnet || true
        rm /tmp/dotnet-install.sh
        ;;
    dnf)
        echo "Installing .NET SDK ${DOTNETVERSION} via dnf..."
        # Add Microsoft repo for Fedora/RHEL
        dnf install -y "dotnet-sdk-${DOTNETVERSION}" || {
            echo "Failed to install dotnet-sdk-${DOTNETVERSION}, attempting fallback..."
            dnf install -y dotnet-sdk || exit 1
        }
        ;;
    apk)
        echo "Installing .NET SDK ${DOTNETVERSION} via apk..."
        apk add --no-cache wget ca-certificates

        # Install via dotnet-install script
        wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
        chmod +x /tmp/dotnet-install.sh
        /tmp/dotnet-install.sh --version "${DOTNETVERSION}" --install-dir /usr/local/bin

        # Create symlink for convenience
        ln -sf /usr/local/bin/dotnet /usr/bin/dotnet || true
        rm /tmp/dotnet-install.sh
        ;;
    *)
        echo "Error: Unsupported package manager: ${PKG_MANAGER}"
        exit 1
        ;;
esac

# Step 3: Verify .NET SDK installation
echo "Verifying .NET SDK installation..."
dotnet --version

# Step 4: Install Entity Framework tools globally
echo "Installing Entity Framework tools..."
dotnet tool install --global dotnet-ef || {
    echo "Warning: Failed to install dotnet-ef (may already be installed)"
}
dotnet ef --version

# Step 5: Copy hook scripts to Claude Code hooks directory
HOOKS_DIR="${_REMOTE_USER_HOME}/.claude/hooks"
HOOKS_SOURCE_DIR="${SCRIPT_DIR}/hooks"

mkdir -p "${HOOKS_DIR}"
echo "Copying C# hook scripts to ${HOOKS_DIR}..."

if [ ! -d "${HOOKS_SOURCE_DIR}" ]; then
    echo "Warning: Hooks source directory not found at ${HOOKS_SOURCE_DIR}"
else
    for hook_file in "${HOOKS_SOURCE_DIR}"/*.py; do
        if [ -f "$hook_file" ]; then
            hook_name=$(basename "$hook_file")
            cp "$hook_file" "${HOOKS_DIR}/${hook_name}"
            chmod +x "${HOOKS_DIR}/${hook_name}"
            echo "Installed hook: ${hook_name}"
        fi
    done
fi

# Step 6: Fix ownership
if [ -n "${_REMOTE_USER}" ]; then
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${HOOKS_DIR}"
    echo "Fixed ownership of hooks directory for ${_REMOTE_USER}"
fi

echo ""
echo "C# / .NET Development Tools installed successfully!"
echo ""
