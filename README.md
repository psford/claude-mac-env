# Claude Mac Environment

Containerized Claude Code development environment for Apple Silicon Macs.

## What this does

This repository provides a single-command setup that runs Claude Code inside a Dev Container on your Mac. Your project files stay in a read-write bind mount, your home directory dotfiles (git, ssh, etc.) are read-only, and everything else is sandboxed. Once set up, VS Code connects automatically every time you open the project.

## Prerequisites

- Apple Silicon Mac (M1, M2, M3, M4, or later)
- 4+ GB RAM (8+ GB recommended)
- 10 GB free disk space

That's it. The setup script handles everything else.

## Quickstart

1. Clone this repository:
   ```bash
   git clone https://github.com/psford/claude-mac-env.git
   cd claude-mac-env
   ```

2. Run the setup script:
   ```bash
   ./setup.sh
   ```

3. Open the project in VS Code:
   ```bash
   code .
   ```

VS Code will recognize the Dev Container configuration and ask to reopen the project inside the container. Click "Reopen in Container" — you're done. Claude Code is now available in the terminal.

## What gets installed

Setup installs the following on your Mac. Each installation step asks for your permission:

| Component | Purpose | Scope |
|-----------|---------|-------|
| Homebrew | Package manager | Mac only |
| Docker | Container runtime | Mac only |
| Docker Buildx | Multi-arch builds | Mac only |
| VS Code | Editor | Mac only |
| VS Code Dev Containers extension | Container integration | Mac only |
| Git identity | Commit author info | Mac + Container |
| GitHub authentication (gh CLI) | GitHub access | Mac + Container |

Inside the container, the Dockerfile installs:
- Node.js LTS
- Python 3
- Git, curl, build tools, and other essentials
- Claude Code CLI
- Dev Container Features (based on your selections)

## Day-to-day usage

**Opening the project:**
1. Open the project folder in VS Code (via File → Open Folder or `code .`)
2. VS Code detects the Dev Container configuration and prompts "Reopen in Container"
3. Click "Reopen" — the container starts (or reconnects to an existing one)
4. Look for the green indicator in the bottom left corner: "Dev Container: claude-mac-env" means you're inside

**Using Claude Code:**
- Open a terminal in VS Code (Ctrl+` or View → Terminal)
- Run `claude` commands directly
- Your project files are available at `/workspaces/claude-mac-env`

**Container lifecycle:**
- The container persists after you close VS Code — reconnecting is instant
- You can manually stop it via Docker Desktop
- The "Rebuild Container" button in VS Code reinstalls Features if needed

## Filesystem access

Your files are mounted into the container with different permissions:

| Mount Point | Mac Path | Container Path | Access | Notes |
|-------------|----------|-----------------|--------|-------|
| Project | `./` | `/workspaces/claude-mac-env` | Read-Write | Your working directory |
| Git config | `~/.gitconfig` | `~/.gitconfig` | Read-Only | Identity and auth config |
| SSH keys | `~/.ssh` | `~/.ssh` | Read-Only | GitHub and other SSH keys |
| Everything else | Mac filesystem | Not mounted | None | Sandboxed — container can't access |

## Customizing tooling

The setup script offers tiered tool selection:

1. **Universal tools:** Hooks and utilities for all projects (git guards, etc.)
2. **Language tools:** SDKs and helpers for specific languages (Node.js, Python, C#, etc.)
3. **Personal tools:** Project-specific or user-specific utilities

To change your selections after initial setup, re-run `./setup.sh`. The script detects what's already installed and offers to add or skip items.

## Nuke and pave

To completely reset:

1. Delete the Docker image and container:
   ```bash
   docker rm claude-mac-env 2>/dev/null || true
   docker rmi claude-mac-env:latest 2>/dev/null || true
   ```

2. Rebuild from scratch:
   ```bash
   ./setup.sh
   ```

## Sharing

To share this environment with a teammate:

1. They clone the repository:
   ```bash
   git clone https://github.com/psford/claude-mac-env.git
   cd claude-mac-env
   ```

2. They run the setup script:
   ```bash
   ./setup.sh
   ```

3. When asked for their GitHub username, they enter their own
4. They open the project in VS Code and reconnect to the container

Each person's setup is independent — changes to their tooling or secrets don't affect yours.

## Secrets management

Claude Code may need access to secrets (API keys, tokens, etc.). The setup script offers three ways to provide them:

1. **Environment file:** Secrets stored in `~/.env` on your Mac, mounted read-only into the container
2. **macOS Keychain:** Secrets stored securely in your Keychain, fetched at container startup
3. **Azure Key Vault:** Secrets stored in Azure, fetched at container startup (requires Azure CLI authentication)

Choose the method that fits your workflow. See [CONTRIBUTING.md](CONTRIBUTING.md) for technical details on how secrets are managed.

## Troubleshooting

**"Reopen in Container" doesn't appear in VS Code**

The Dev Containers extension may not be installed. Install it from the VS Code Marketplace (or run `code --install-extension ms-vscode-remote.remote-containers`).

**Container won't start — "docker: command not found"**

Docker may not have started automatically. Open Docker Desktop and wait for the "Docker is running" message.

**"gh: command not found" in setup.sh**

The GitHub CLI didn't link properly. This is documented in [install-notes.md](docs/install-notes.md). The setup script tries to handle it, but if it fails, try:
```bash
brew uninstall gh
brew install gh
```

**Git push fails with "Device not configured"**

Git's credential helper isn't configured. Run:
```bash
gh auth setup-git
```

**Changes in the container don't persist after rebuild**

Only files in `/workspaces/` are persisted (they're in your Mac filesystem). Everything else in the container is ephemeral. Install tools and configuration inside a Dev Container Feature if they need to survive rebuilds.

**Port bindings don't work**

Ports must be explicitly forwarded in `.devcontainer/devcontainer.json`. Edit that file and add a `"forwardPorts"` array if needed.

**Slow file I/O in the container**

This is a known limitation of Docker on Mac. Most operations are fast enough for development, but large recursive operations (like `npm install` on big projects) can be slow. Store `node_modules` inside the container using a named volume if performance becomes an issue.

## More information

- [CONTRIBUTING.md](CONTRIBUTING.md) — For developers adding Features or tooling
- [docs/install-notes.md](docs/install-notes.md) — Detailed friction log and solutions
- [docs/manifest-schema.md](docs/manifest-schema.md) — Tooling manifest reference
