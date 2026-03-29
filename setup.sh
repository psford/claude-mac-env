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
