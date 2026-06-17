# Base image — Ubuntu by default, overridable via build arg
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

# Prevent interactive prompts during package install
ENV DEBIAN_FRONTEND=noninteractive

# Core system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    jq \
    build-essential \
    ca-certificates \
    gnupg \
    sudo \
    python3 \
    python3-pip \
    python3-venv \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Azure CLI (needed for Key Vault secrets provider and Azure deployments)
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Node.js LTS via nodesource
ARG NODE_MAJOR=24
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user with sudo access
# Ubuntu 24.04 ships with a 'ubuntu' user at UID/GID 1000 — remove it first
ARG USERNAME=claude
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupdel ubuntu 2>/dev/null || true \
    && groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Create workspaces directory for project mounts
RUN mkdir -p /workspaces && chown ${USERNAME}:${USERNAME} /workspaces

# Shared utility for distro detection (used by Features later)
COPY detect-package-manager.sh /usr/local/bin/detect-package-manager.sh
RUN chmod +x /usr/local/bin/detect-package-manager.sh

# Switch to non-root user
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Bake the PUBLIC ed3d plugin marketplace into the image, as the claude user.
# Plugins are loaded by the native binary only at process startup, so installing
# them during postCreateCommand never surfaces in the already-running session.
# Baking them here means installed_plugins.json + cache exist before the first
# `claude` process starts — fresh regions get the skills with no manual reload.
# (Auth-gated private plugins still install in config/bootstrap.sh.)
COPY --chown=${USERNAME}:${USERNAME} config/install-ed3d-plugins.sh /tmp/install-ed3d-plugins.sh
RUN bash /tmp/install-ed3d-plugins.sh && rm -f /tmp/install-ed3d-plugins.sh

# Verify installations
RUN node --version && npm --version && python3 --version && git --version && claude --version
