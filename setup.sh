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

# Welcome banner
echo "=========================================="
echo "Claude Mac Environment Setup v0.1.0"
echo "=========================================="
echo ""

# Check for Apple Silicon
info "Checking system architecture..."
ARCH=$(uname -m)

if [[ "$ARCH" != "arm64" ]]; then
    error "This setup requires Apple Silicon (arm64)."
    error "Detected architecture: $ARCH"
    error "Claude Mac Environment is designed for Apple Silicon Macs."
    error "For Intel Macs, please refer to the manual setup guide."
    exit 1
fi

success "Apple Silicon detected (arm64)"
echo ""

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

    xcode-select --install

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

# Call Homebrew check from main flow
check_homebrew
echo ""

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

            # Find the docker binary in Homebrew's Cellar
            local docker_path
            docker_path=$(find /opt/homebrew/Caskroom/docker -name docker -type f 2>/dev/null | head -1)

            if [[ -n "$docker_path" && -x "$docker_path" ]]; then
                if brew link docker 2>/dev/null; then
                    success "Docker linked via brew"
                else
                    # Manual symlink as fallback per friction log
                    warn "Brew link failed, symlinking manually..."
                    mkdir -p /usr/local/bin
                    if ln -sf "$docker_path" /usr/local/bin/docker; then
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

# Call Xcode CLT check
check_xcode_clt
echo ""

# Call Docker check
check_docker
echo ""
