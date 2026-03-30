#!/bin/bash
set -e

# claude-skills Feature: Prepare skills directory structure
#
# This Feature runs at Docker image build time where NO auth, NO user session,
# and NO mounted volumes are available. It ONLY creates the directory structure
# and sets ownership. Actual skill installation happens in config/bootstrap.sh
# at container start time (postCreateCommand) where auth is available.

# Use the remote user's home directory for skills installation
SKILLS_DIR="${_REMOTE_USER_HOME}/.claude/skills"

echo "Preparing Claude Code Skills directory..."

# Create skills directory structure
mkdir -p "${SKILLS_DIR}"
echo "Created skills directory: ${SKILLS_DIR}"

# Set proper ownership of the skills directory for the remote user
if [ -n "${_REMOTE_USER}" ]; then
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${_REMOTE_USER_HOME}/.claude"
    echo "Set ownership of .claude directory to ${_REMOTE_USER}"
fi

echo "Claude Code Skills directory prepared. Skills will be installed during bootstrap."
