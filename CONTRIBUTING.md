# Contributing to Claude Mac Environment

This guide covers how to extend and maintain the claude-mac-env project.

## Adding a new Dev Container Feature

Dev Container Features are modular, published packages that extend the container environment. They install tools, configure shells, or add hooks and utilities.

### Feature file structure

Each Feature lives in `features/<feature-name>/`:

```
features/universal-hooks/
├── devcontainer-feature.json
├── install.sh
└── README.md
```

### devcontainer-feature.json schema

Every Feature must include a `devcontainer-feature.json` manifest:

```json
{
  "id": "universal-hooks",
  "version": "1.0.0",
  "name": "Universal Git Hooks",
  "description": "Pre-commit guards and branch protection hooks",
  "documentationURL": "https://github.com/psford/claude-mac-env",
  "options": {
    "hook_set": {
      "type": "string",
      "description": "Which hook set to install",
      "default": "essential"
    }
  }
}
```

**Required fields:**
- `id`: Machine-readable identifier (lowercase, hyphens)
- `version`: SemVer version string
- `name`: Human-readable name
- `description`: One-line description

**Optional fields:**
- `documentationURL`: Link to Feature docs
- `options`: Configuration options passed to `install.sh` via environment variables

### install.sh requirements

The `install.sh` script runs inside the container as the non-root `claude` user:

```bash
#!/bin/bash
set -euo pipefail

# Parse Feature options (passed as env vars, e.g., VARIANT=1.20)
VARIANT="${VARIANT:-default}"

# Detect package manager for this distro
DISTRO=$(detect-package-manager.sh)

case "${DISTRO}" in
  apt) apt-get update && apt-get install -y tool-name ;;
  apk) apk add tool-name ;;
  *) echo "Unsupported distro: ${DISTRO}"; exit 1 ;;
esac

# Verify installation
tool-name --version
```

**Guidelines:**
- Always use `set -euo pipefail` for safety
- Call `detect-package-manager.sh` to determine the distro
- Clean up package manager caches after install (e.g., `rm -rf /var/lib/apt/lists/*`)
- Verify the installation at the end
- Use environment variables for configuration options

### Testing a Feature locally

1. Build the image with the Feature:
   ```bash
   devcontainer build --workspace-folder .
   ```

2. Test inside the running container:
   ```bash
   docker run --rm claude-mac-env:latest tool-name --version
   ```

3. Or use VS Code's "Dev Containers: Rebuild Container" command to test interactively.

### Publishing a Feature

Features are published to GitHub Container Registry (GHCR) automatically when you push a tag:

1. The CI workflow detects the tag
2. Builds the Docker image with all Features
3. Publishes to `ghcr.io/psford/claude-mac-env:v1.0.0`

Users then reference the Feature in their `.devcontainer/devcontainer.json`:

```json
{
  "features": {
    "ghcr.io/psford/claude-mac-env/universal-hooks:1.0.0": {
      "hook_set": "essential"
    }
  }
}
```

## Tooling manifest

The `tooling-manifest.json` catalogs all hooks, scripts, and utilities that users can install.

### Manifest schema

See `docs/manifest-schema.md` for the complete schema. Quick example:

```json
{
  "version": "1.0",
  "features": [
    {
      "id": "universal-hooks",
      "description": "Git hooks for validation",
      "tier": "universal"
    }
  ],
  "tools": [
    {
      "name": "git-commit-guard",
      "source": ".claude/hooks/git_commit_guard.py",
      "tier": "universal",
      "language": null,
      "feature": "universal-hooks",
      "description": "Validates commit messages before pushing"
    }
  ]
}
```

### How the classification hook works

The commit hook `manifest_classification_guard.py` automatically proposes manifest entries for new tool files:

1. You create a new file like `.claude/hooks/my_tool.py`
2. `git add` stages it
3. The pre-commit hook detects the new file
4. It analyzes the file path and content
5. It proposes a manifest entry for your review
6. You accept or edit the proposal before committing

See the hook itself at `.claude/hooks/manifest_classification_guard.py` for implementation details.

## Modifying setup.sh

The `setup.sh` script orchestrates the entire setup flow: preflight checks, system dependency installation, Docker image building, and Feature selection.

### Function structure

Key functions in `setup.sh`:

- `check_<dependency>()` — Preflight checks (returns 0 if present, 1 if missing)
- `install_<tool>()` — Installation logic (assumes check failed, installs and verifies)
- `menu_<section>()` — User prompts (offers choices, sets variables)
- `main()` — Entry point that orchestrates the flow

### Adding a preflight check

To add a new dependency check:

1. Create a `check_mytool()` function:
   ```bash
   check_mytool() {
     command -v mytool >/dev/null 2>&1
   }
   ```

2. Call it early in `main()`:
   ```bash
   if ! check_mytool; then
     echo "mytool not found. Installing..."
     install_mytool
   fi
   ```

3. Create an `install_mytool()` function that installs and verifies:
   ```bash
   install_mytool() {
     brew install mytool
     mytool --version
   }
   ```

### Error handling in setup.sh

- Use `set -euo pipefail` at the top (already present)
- All `brew install` calls are wrapped in fallback logic (documented in install-notes.md)
- Git identity and credentials are checked early (required for Feature installation)

## Adding a secrets provider

Secrets providers supply environment variables to the container at startup. Three are built-in: `env`, `keychain`, and `azure`.

### Secrets provider interface

Each provider implements these functions in `config/secrets-<name>.sh`:

```bash
# Check if the provider is available on this system
secrets_<name>_available() {
  # Return 0 if available, 1 if not
  command -v some_tool >/dev/null 2>&1
}

# Load secrets and export them as environment variables
secrets_<name>_load() {
  # Query secrets from the provider
  # Export each as: export SECRET_NAME="value"
  export API_KEY="$(retrieve_secret ...)"
}

# Prompt the user to set up this provider
secrets_<name>_setup() {
  echo "Configuring provider..."
  # Interactive setup steps, validation, etc.
}
```

### Registering a provider

Edit `setup.sh` to add the provider to the menu:

```bash
menu_secrets() {
  echo "Choose a secrets provider:"
  echo "1) Environment file (~/.env)"
  echo "2) macOS Keychain"
  echo "3) Azure Key Vault"
  echo "4) My Custom Provider"  # <-- Add here
  read -p "Choice: " choice

  case "${choice}" in
    4) SECRETS_PROVIDER="custom" ;;
    # ... existing cases ...
  esac
}
```

Then, in the container startup logic, source and call your provider:

```bash
if [[ -n "${SECRETS_PROVIDER}" ]]; then
  source "config/secrets-${SECRETS_PROVIDER}.sh"
  secrets_${SECRETS_PROVIDER}_load
fi
```

## Testing

### Running the e2e validation script

The `scripts/validate.sh` script checks that the full environment works:

```bash
bash scripts/validate.sh
```

It verifies:
- Docker image builds
- Container starts and runs basic commands
- Claude Code is installed
- Node.js and Python are available
- Non-root user is configured correctly
- Bind mounts work (read-write and read-only)
- Feature artifacts are installed

See `scripts/validate.sh` for the full checklist.

### Running unit tests

If adding Python or Node.js tooling, include unit tests:

```bash
npm test        # For Node.js
pytest tests/   # For Python
```

CI runs these automatically via the GitHub Actions workflow.

### Manual testing in VS Code

1. Open the project in VS Code
2. Run "Dev Containers: Rebuild Container" (Ctrl+Shift+P)
3. Wait for the build to complete
4. Open a terminal and verify tools are available
5. Test Claude Code: run `claude --help`

## Release process

Releases are tagged in Git and published to GitHub:

### Creating a release tag

1. Ensure all tests pass locally and in CI
2. Create an annotated tag:
   ```bash
   git tag -a v1.0.0 -m "Initial release"
   ```

3. Push the tag:
   ```bash
   git push origin v1.0.0
   ```

4. CI detects the tag and:
   - Builds the Docker image
   - Publishes to GHCR
   - Creates a GitHub Release with notes

### What CI does on tag push

The `publish-features.yml` workflow:

1. Builds the Docker image (with all Features)
2. Tags it as `ghcr.io/psford/claude-mac-env:v1.0.0`
3. Pushes to GHCR (requires GHCR authentication)
4. Each Feature inside is also publishable as a separate OCI artifact

Users then reference specific versions in `.devcontainer/devcontainer.json`.

## Code style

- **Shell:** Follow Google Shell Style Guide. Use `shellcheck` (run via CI)
- **JSON:** Use 2-space indent
- **Markdown:** 80-character line wrap where possible
- **Python:** PEP 8, use type hints

## Getting help

- Check `docs/install-notes.md` for known issues and solutions
- Review existing Features in `features/` as examples
- Open an issue to discuss larger changes before implementing
