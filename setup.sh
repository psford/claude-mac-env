#!/usr/bin/env bash
set -euo pipefail

# Color output utilities
info() {
    echo "ℹ  $*"
}

warn() {
    echo "⚠  $*" >&2
}

error() {
    echo "✗ $*" >&2
}

success() {
    echo "✓ $*"
}

ask_yn() {
    local prompt="$1"
    local default="${2:-y}"
    local response

    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$prompt (Y/n) " -r response || response=""
            response="${response:-y}"
        else
            read -p "$prompt (y/N) " -r response || response=""
            response="${response:-n}"
        fi

        case "${response,,}" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                echo "Please answer y or n"
                ;;
        esac
    done
}

# Homebrew preflight check
check_homebrew() {
    info "Checking Homebrew..."

    # Check if brew command exists in PATH
    if command -v brew &>/dev/null; then
        local brew_version
        brew_version=$(brew --version | head -n1)
        success "Homebrew already installed: $brew_version"
        return 0
    fi

    # Check common locations for Apple Silicon
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        local brew_version
        brew_version=$(brew --version | head -n1)
        success "Homebrew found at /opt/homebrew: $brew_version"
        return 0
    fi

    # Check legacy location
    if [[ -x /usr/local/bin/brew ]]; then
        local brew_version
        brew_version=$(brew --version | head -n1)
        success "Homebrew found at /usr/local: $brew_version"
        return 0
    fi

    # Homebrew not found - ask for permission to install
    info "Homebrew is required for dependency management."
    if ask_yn "Install Homebrew?"; then
        info "Installing Homebrew (this may take a few minutes)..."
        if NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
            # Add to PATH for current session
            eval "$(/opt/homebrew/bin/brew shellenv)"

            # Verify installation
            if brew --version &>/dev/null; then
                success "Homebrew installed successfully"
                return 0
            else
                error "Homebrew installation completed but verification failed"
                return 1
            fi
        else
            error "Homebrew installation failed"
            error "Please install manually: https://brew.sh/"
            return 1
        fi
    else
        error "Homebrew is required to continue"
        error "Please install manually: https://brew.sh/"
        return 1
    fi
}

# Xcode CLT preflight check
check_xcode_clt() {
    info "Checking Xcode Command Line Tools..."

    if xcode-select -p &>/dev/null; then
        success "Xcode CLT already installed"
        if git --version &>/dev/null; then
            success "Git verified: $(git --version)"
            return 0
        fi
    fi

    # Not installed - trigger the installer
    info "Installing Xcode Command Line Tools..."
    info "A dialog has appeared to install Xcode Command Line Tools."
    info "Please click 'Install' and wait for completion, then press Enter to continue."

    xcode-select --install || true

    read -p "Press Enter after installation completes: " -r || true

    # Re-check installation
    if xcode-select -p &>/dev/null; then
        if git --version &>/dev/null; then
            success "Xcode CLT installed successfully"
            return 0
        fi
    fi

    error "Xcode Command Line Tools installation could not be verified"
    error "Please install manually: xcode-select --install"
    return 1
}

# Docker Desktop preflight check
check_docker() {
    info "Checking Docker Desktop..."

    # Check if docker command exists and daemon is running
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        local docker_version
        docker_version=$(docker --version)
        success "Docker already running: $docker_version"
        return 0
    fi

    # Docker command exists but daemon not running
    if command -v docker &>/dev/null; then
        warn "Docker command found but daemon not running"
        info "Starting Docker Desktop..."
        open -a Docker

        # Wait for daemon with retries
        local retry_count=0
        local max_retries=30
        while [[ $retry_count -lt $max_retries ]]; do
            if docker info &>/dev/null; then
                success "Docker daemon is running"
                return 0
            fi
            sleep 2
            retry_count=$((retry_count + 1))
        done

        warn "Docker daemon did not start within 60 seconds"
        warn "You may need to authorize Docker Desktop in the system prompt"
        info "Waiting for manual authorization..."
        info "Press Enter when Docker Desktop has started and authorized:"
        read -p "" -r || true

        if docker info &>/dev/null; then
            success "Docker daemon is now running"
            return 0
        else
            error "Docker daemon still not responding"
            return 1
        fi
    fi

    # Docker not installed
    info "Docker Desktop is required for the development container."
    if ask_yn "Install Docker Desktop?"; then
        info "Installing Docker Desktop via Homebrew (this may take a few minutes)..."
        if brew install --cask docker --no-quarantine; then
            info "Docker installed, verifying binary..."
        else
            error "Docker Desktop installation failed"
            return 1
        fi

        # Verify binary exists and try to link it
        if ! command -v docker &>/dev/null; then
            info "Attempting to link Docker binary..."

            # Primary fallback: Docker Desktop binary location
            local docker_path="/Applications/Docker.app/Contents/Resources/bin/docker"

            if [[ ! -x "$docker_path" ]]; then
                # Fallback: Find the docker binary in Homebrew's Cellar
                docker_path=$(find /opt/homebrew/Caskroom/docker -name docker -type f 2>/dev/null | head -1)
            fi

            if [[ -n "$docker_path" && -x "$docker_path" ]]; then
                if brew link docker 2>/dev/null; then
                    success "Docker linked via brew"
                else
                    # Manual symlink as fallback per friction log
                    warn "Brew link failed, symlinking manually..."
                    info "Creating symlink requires elevated permissions..."
                    if sudo mkdir -p /usr/local/bin && sudo ln -sf "$docker_path" /usr/local/bin/docker; then
                        success "Docker manually symlinked to /usr/local/bin/docker"
                    else
                        error "Failed to symlink Docker binary"
                        return 1
                    fi
                fi
            fi
        fi

        # Verify docker command works
        if docker --version &>/dev/null; then
            success "Docker binary verified"
        else
            error "Docker binary could not be verified"
            return 1
        fi

        # Start Docker Desktop
        info "Starting Docker Desktop..."
        open -a Docker

        # Wait for daemon with retries
        local retry_count=0
        local max_retries=30
        while [[ $retry_count -lt $max_retries ]]; do
            if docker info &>/dev/null; then
                success "Docker daemon is running"
                return 0
            fi
            sleep 2
            retry_count=$((retry_count + 1))
        done

        warn "Docker daemon did not start within 60 seconds"
        warn "You may need to authorize Docker Desktop in the system prompt"
        info "Press Enter when Docker Desktop has started and authorized:"
        read -p "" -r || true

        if docker info &>/dev/null; then
            success "Docker daemon is now running"
            return 0
        else
            error "Docker daemon not responding after installation"
            return 1
        fi
    else
        error "Docker Desktop is required to continue"
        return 1
    fi
}

# VS Code preflight check (non-blocking)
VSCODE_INSTALLED=false

check_vscode() {
    info "Checking VS Code..."

    # Check if code command exists in PATH
    if command -v code &>/dev/null; then
        local vscode_version
        vscode_version=$(code --version | head -n1)
        success "VS Code already installed: $vscode_version"
        VSCODE_INSTALLED=true
        return 0
    fi

    # Check common VS Code locations
    if [[ -x /usr/local/bin/code ]]; then
        local vscode_version
        vscode_version=$(/usr/local/bin/code --version | head -n1)
        success "VS Code found at /usr/local/bin"
        VSCODE_INSTALLED=true
        return 0
    fi

    if [[ -x /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code ]]; then
        local vscode_version
        vscode_version=$(/Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code --version | head -n1)
        success "VS Code found at /Applications"
        VSCODE_INSTALLED=true
        return 0
    fi

    # VS Code not found - ask for permission (non-blocking)
    info "VS Code is recommended but optional for the best development experience."
    if ask_yn "Install VS Code?"; then
        info "Installing VS Code via Homebrew (this may take a few minutes)..."
        if brew install --cask visual-studio-code --no-quarantine; then
            info "VS Code installed, verifying..."
        else
            warn "VS Code installation failed, continuing without it"
            return 0
        fi

        # Verify binary exists and try to link it
        if ! command -v code &>/dev/null; then
            info "Attempting to link VS Code binary..."

            # Find VS Code in common locations
            local vscode_path="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
            if [[ -x "$vscode_path" ]]; then
                if brew link visual-studio-code 2>/dev/null; then
                    success "VS Code linked via brew"
                else
                    # Manual symlink as fallback
                    warn "Brew link failed, symlinking manually..."
                    if sudo mkdir -p /usr/local/bin && sudo ln -sf "$vscode_path" /usr/local/bin/code; then
                        success "VS Code manually symlinked to /usr/local/bin/code"
                    else
                        warn "Failed to symlink VS Code binary, continuing anyway"
                        return 0
                    fi
                fi
            fi
        fi

        if command -v code &>/dev/null; then
            success "VS Code installation verified"
            VSCODE_INSTALLED=true
        else
            warn "VS Code binary could not be found, continuing without it"
        fi
        return 0
    else
        info "Skipping VS Code. You can install later and use 'Reopen in Container' to connect."
        return 0
    fi
}

# Dev Containers extension check
check_devcontainers_extension() {
    # Only run if VS Code is installed
    if [[ "$VSCODE_INSTALLED" != "true" ]]; then
        info "VS Code not installed, skipping Dev Containers extension"
        return 0
    fi

    info "Checking Dev Containers extension..."

    # Check if extension is installed
    if code --list-extensions 2>/dev/null | grep -qi "ms-vscode-remote.remote-containers"; then
        success "Dev Containers extension already installed"
        return 0
    fi

    # Install the extension
    info "Installing Dev Containers extension..."
    if code --install-extension ms-vscode-remote.remote-containers; then
        success "Dev Containers extension installed"
        return 0
    else
        warn "Dev Containers extension installation failed"
        return 0
    fi
}

# gh CLI preflight check
check_gh_cli() {
    info "Checking GitHub CLI..."

    # Check if gh command exists
    if ! command -v gh &>/dev/null; then
        # gh not installed - ask for permission
        info "GitHub CLI (gh) is required for Git authentication."
        if ask_yn "Install GitHub CLI?"; then
            info "Installing gh via Homebrew..."
            if brew install gh; then
                info "gh installed, verifying binary..."
            else
                error "GitHub CLI installation failed"
                return 1
            fi

            # Verify binary exists and try to link it
            if ! command -v gh &>/dev/null; then
                info "Attempting to link gh binary..."

                # Find the gh binary in Homebrew
                local gh_path
                gh_path=$(find /opt/homebrew/Cellar/gh -name gh -type f 2>/dev/null | head -1)

                if [[ -n "$gh_path" && -x "$gh_path" ]]; then
                    if brew link gh 2>/dev/null; then
                        success "gh linked via brew"
                    else
                        # Manual symlink as fallback per friction log
                        warn "Brew link failed, symlinking manually..."
                        if sudo mkdir -p /usr/local/bin && sudo ln -sf "$gh_path" /usr/local/bin/gh; then
                            success "gh manually symlinked to /usr/local/bin/gh"
                        else
                            error "Failed to symlink gh binary"
                            return 1
                        fi
                    fi
                fi
            fi

            if gh --version &>/dev/null; then
                success "GitHub CLI verified"
            else
                error "GitHub CLI could not be verified"
                return 1
            fi
        else
            error "GitHub CLI is required to continue"
            return 1
        fi
    else
        success "GitHub CLI already installed: $(gh --version | head -n1)"
    fi

    # Check authentication status
    info "Checking GitHub authentication..."
    if gh auth status &>/dev/null; then
        success "GitHub account authenticated"
    else
        info "GitHub authentication required. A browser window will open for you to authorize."
        if ask_yn "Authenticate with GitHub?"; then
            info "Opening GitHub authentication flow..."
            if gh auth login --web --git-protocol https; then
                success "GitHub authentication successful"
            else
                error "GitHub authentication failed"
                return 1
            fi
        else
            error "GitHub authentication is required to continue"
            return 1
        fi
    fi

    # Configure git to use gh as credential helper
    info "Configuring Git to use GitHub CLI..."
    if gh auth setup-git; then
        success "Git credential helper configured"
    else
        warn "Could not configure git credential helper automatically"
    fi

    # Check git identity
    info "Checking Git identity..."
    local git_name
    local git_email
    git_name=$(git config --global user.name || echo "")
    git_email=$(git config --global user.email || echo "")

    if [[ -n "$git_name" && -n "$git_email" ]]; then
        success "Git identity configured: $git_name <$git_email>"
        return 0
    fi

    # Git identity not configured - try to pull from GitHub or prompt manually
    info "Git identity not configured globally."

    # Try to get name and email from GitHub profile
    if gh auth status &>/dev/null; then
        info "Attempting to use GitHub profile information..."
        local github_name
        github_name=$(gh api user --jq '.name // .login' 2>/dev/null || echo "")

        if [[ -n "$github_name" ]]; then
            git_name="$github_name"
            info "Using GitHub name: $git_name"
        fi

        # GitHub API doesn't expose private email via simple query, prompt for it
        if [[ -z "$git_email" ]]; then
            echo "Your GitHub username suggests your name is: $git_name"
            read -p "Enter your Git email address: " -r git_email || git_email=""
        fi
    fi

    # If still not set, prompt manually
    if [[ -z "$git_name" ]]; then
        read -p "Enter your Git name: " -r git_name || git_name=""
    fi

    if [[ -z "$git_email" ]]; then
        read -p "Enter your Git email: " -r git_email || git_email=""
    fi

    # Validate and configure
    if [[ -n "$git_name" && -n "$git_email" ]]; then
        git config --global user.name "$git_name"
        git config --global user.email "$git_email"
        success "Git identity configured: $git_name <$git_email>"
    else
        error "Git identity could not be configured"
        return 1
    fi
}

# Run all preflight checks in sequence
run_preflight() {
    # Welcome banner
    echo "=========================================="
    echo "Claude Mac Environment Setup v0.1.0"
    echo "=========================================="
    echo ""

    info "Running preflight checks..."
    echo ""

    # Architecture check (hard stop if Intel)
    ARCH=$(uname -m)
    if [[ "$ARCH" != "arm64" ]]; then
        error "This setup requires Apple Silicon (arm64)."
        error "Detected architecture: $ARCH"
        error "Claude Mac Environment is designed for Apple Silicon Macs."
        error "For Intel Macs, please refer to the manual setup guide."
        return 1
    fi
    success "Apple Silicon detected (arm64)"
    echo ""

    # Homebrew check (hard stop if fails)
    check_homebrew || return 1
    echo ""

    # Xcode CLT check (hard stop if fails)
    check_xcode_clt || return 1
    echo ""

    # Docker check (hard stop if fails)
    check_docker || return 1
    echo ""

    # VS Code check (non-blocking)
    check_vscode
    echo ""

    # Dev Containers extension check (only if VS Code installed)
    check_devcontainers_extension
    echo ""

    # gh CLI check (hard stop if fails)
    check_gh_cli || return 1
    echo ""

    # Print summary
    print_summary
}

# Print summary of installed tools
print_summary() {
    echo "=========================================="
    success "Preflight complete. All dependencies installed:"
    echo ""

    # Get versions
    local homebrew_version
    homebrew_version=$(brew --version | head -n1)

    local docker_version
    docker_version=$(docker --version 2>/dev/null || echo "not installed")

    local vscode_version
    if [[ "$VSCODE_INSTALLED" == "true" ]]; then
        vscode_version=$(code --version 2>/dev/null | head -n1 || echo "installed")
    else
        vscode_version="skipped"
    fi

    local devcontainers_status
    if [[ "$VSCODE_INSTALLED" == "true" && $(code --list-extensions 2>/dev/null | grep -c "ms-vscode-remote.remote-containers" || echo 0) -gt 0 ]]; then
        devcontainers_status="installed"
    elif [[ "$VSCODE_INSTALLED" != "true" ]]; then
        devcontainers_status="skipped"
    else
        devcontainers_status="not installed"
    fi

    local gh_version
    gh_version=$(gh --version 2>/dev/null | head -n1 || echo "not installed")

    local git_identity
    local git_name
    local git_email
    git_name=$(git config --global user.name || echo "")
    git_email=$(git config --global user.email || echo "")
    if [[ -n "$git_name" && -n "$git_email" ]]; then
        git_identity="$git_name <$git_email>"
    else
        git_identity="not configured"
    fi

    echo "  • Homebrew: $homebrew_version"
    echo "  • Docker Desktop: $docker_version"
    echo "  • VS Code: $vscode_version"
    echo "  • Dev Containers extension: $devcontainers_status"
    echo "  • GitHub CLI: $gh_version"
    echo "  • Git identity: $git_identity"
    echo ""
    echo "=========================================="
}

# Main entry point
main() {
    # Check for --preflight-only flag
    if [[ "${1:-}" == "--preflight-only" ]]; then
        run_preflight
        exit $?
    fi

    # Run full preflight
    run_preflight
}

# Run main function
main "$@"
