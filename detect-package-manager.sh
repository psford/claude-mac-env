#!/usr/bin/env bash
# Detect the package manager for the current Linux distro.
# Used by Dev Container Feature install.sh scripts.
# Returns: apt, dnf, apk, or pacman. Exits 1 if unknown.

set -euo pipefail

if command -v apt-get &>/dev/null; then
    echo "apt"
elif command -v dnf &>/dev/null; then
    echo "dnf"
elif command -v apk &>/dev/null; then
    echo "apk"
elif command -v pacman &>/dev/null; then
    echo "pacman"
else
    echo "unknown" >&2
    exit 1
fi
