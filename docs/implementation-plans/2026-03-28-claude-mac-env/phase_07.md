# Claude Mac Environment Implementation Plan — Phase 7

**Goal:** Establish the pluggable secrets provider interface and implement three providers (Azure Key Vault, .env file, macOS Keychain) with integration into setup.sh and container startup.

**Architecture:** Shell-based provider interface with source/validate/inject functions. Each provider is a standalone script implementing the interface. Selected during setup, invoked at container start via postCreateCommand. Provider selection persisted in user config.

**Tech Stack:** Bash, Azure CLI (az), macOS security CLI, Docker bind mounts for env injection

**Scope:** Phase 7 of 8 from original design

**Codebase verified:** 2026-03-29 — setup.sh exists from Phases 5-6 with preflight and interactive setup. .devcontainer/devcontainer.json.template exists from Phase 6. No config/ directory or secrets scripts exist yet.

---

## Acceptance Criteria Coverage

### claude-mac-env.AC7: Pluggable secrets
- **claude-mac-env.AC7.1 Success:** Azure Key Vault provider injects secrets into container
- **claude-mac-env.AC7.2 Success:** .env provider reads from user-specified path
- **claude-mac-env.AC7.3 Success:** macOS Keychain provider reads via security CLI
- **claude-mac-env.AC7.4 Success:** Skipping secrets during setup results in working container
- **claude-mac-env.AC7.5 Success:** Selected provider persists across container rebuilds

---

<!-- START_SUBCOMPONENT_A (tasks 1-2) -->
<!-- START_TASK_1 -->
### Task 1: Create secrets provider interface

**Files:**
- Create: `config/secrets-interface.sh`

**Implementation:**

Define the provider contract as a shell script that providers source. The interface defines three functions that each provider must implement:

- `secrets_validate()` — Check that the provider's prerequisites are met (e.g., az CLI authenticated, .env file exists). Return 0 if valid, 1 with error message if not.
- `secrets_inject()` — Write secrets as environment variables to a file at `$SECRETS_OUTPUT_PATH` (one `export VAR=value` per line). This file is sourced by the container entrypoint.
- `secrets_describe()` — Print a one-line description of this provider for the setup menu.

The interface script also provides:
- `SECRETS_OUTPUT_PATH` default (`/home/claude/.secrets.env`)
- A `secrets_load()` function that sources the output file if it exists (called from postCreateCommand)
- Error handling wrapper that catches provider failures gracefully

**Verification:**

Run: `bash -n config/secrets-interface.sh` (syntax check)
Expected: No errors

**Commit:** `feat: add secrets provider interface`
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create bootstrap-secrets.sh entrypoint script

**Files:**
- Create: `config/bootstrap-secrets.sh`

**Implementation:**

This script runs inside the container via postCreateCommand. It:
1. Reads the selected provider from `.user-config.json` (mounted from host)
2. Sources `config/secrets-interface.sh`
3. Sources the selected provider script (e.g., `config/secrets-env.sh`)
4. Calls `secrets_validate()` — if fails, prints warning but doesn't block container startup
5. Calls `secrets_inject()` — writes secrets to `$SECRETS_OUTPUT_PATH`
6. Sources the output file to make secrets available in current shell
7. If no provider selected (user skipped during setup): prints "No secrets provider configured. Use setup.sh to configure one." and exits 0

**Verification:**

Run: `bash -n config/bootstrap-secrets.sh`
Expected: No syntax errors

**Commit:** `feat: add bootstrap-secrets.sh for container startup`
<!-- END_TASK_2 -->
<!-- END_SUBCOMPONENT_A -->

<!-- START_SUBCOMPONENT_B (tasks 3-5) -->
<!-- START_TASK_3 -->
### Task 3: Implement .env file provider

**Verifies:** claude-mac-env.AC7.2

**Files:**
- Create: `config/secrets-env.sh`

**Implementation:**

Provider that reads from a `.env` file on the Mac host, mounted into the container.

- `secrets_describe()`: "Read secrets from a .env file on the Mac"
- `secrets_validate()`: Check if the configured .env file path exists and is readable. The path is stored in `.user-config.json` as `secrets.envFilePath`.
- `secrets_inject()`: Copy the .env file contents to `$SECRETS_OUTPUT_PATH`, converting any non-export lines to export format. Skip comments and empty lines.

Setup.sh integration (in Phase 6's config generation): if this provider is selected, prompt for the .env file path and add a read-only bind mount for it in devcontainer.json.

**Testing:**

Create a test .env file:
```
API_KEY=test123
DATABASE_URL=postgres://localhost/test
```

Run the provider, verify `$SECRETS_OUTPUT_PATH` contains the exported vars.

**Commit:** `feat: add .env file secrets provider`
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Implement Azure Key Vault provider

**Verifies:** claude-mac-env.AC7.1

**Files:**
- Create: `config/secrets-azure.sh`

**Implementation:**

Provider that pulls secrets from Azure Key Vault using the az CLI.

- `secrets_describe()`: "Pull secrets from Azure Key Vault"
- `secrets_validate()`: Check `az` CLI is installed and authenticated (`az account show`). Check vault name is configured in `.user-config.json` as `secrets.azureVaultName`.
- `secrets_inject()`: Run `az keyvault secret list --vault-name $VAULT_NAME --query "[].name" -o tsv` to get secret names. For each secret, run `az keyvault secret show --vault-name $VAULT_NAME --name $SECRET_NAME --query "value" -o tsv`. Write as `export SECRET_NAME=value` to `$SECRETS_OUTPUT_PATH`. Convert kebab-case names to UPPER_SNAKE_CASE.

Setup.sh integration: if selected, prompt for vault name. Verify `az` CLI is installed (offer to install via `brew install azure-cli` if missing).

**Testing:**

Requires an actual Azure Key Vault — document as a manual verification step. For automated testing, mock the az CLI output.

**Commit:** `feat: add Azure Key Vault secrets provider`
<!-- END_TASK_4 -->

<!-- START_TASK_5 -->
### Task 5: Implement macOS Keychain provider

**Verifies:** claude-mac-env.AC7.3

**Files:**
- Create: `config/secrets-keychain.sh`

**Implementation:**

Provider that reads secrets from macOS Keychain using the `security` CLI. This provider runs on the Mac HOST (before container start), not inside the container — macOS Keychain is not accessible from inside Docker.

- `secrets_describe()`: "Read secrets from macOS Keychain"
- `secrets_validate()`: Check that `security` command exists (always present on macOS). Check that the configured keychain service name exists in `.user-config.json` as `secrets.keychainService`.
- `secrets_inject()`: Use `security find-generic-password -s $SERVICE_NAME -w` to read passwords. Service name acts as a namespace — all secrets for this env are stored under one service with different account names. List accounts with `security dump-keychain` filtered by service, then read each. Write as `export ACCOUNT_NAME=value` to `$SECRETS_OUTPUT_PATH`.

**Host/container execution split:** This provider has two phases:
1. **Host-side (during `setup.sh` or pre-start):** A host-side script reads from macOS Keychain using `security` CLI and writes the output to a file at a known path on the Mac (e.g., `~/.claude-secrets.env`).
2. **Container-side (during postCreateCommand):** The output file is bind-mounted read-only into the container. `bootstrap-secrets.sh` inside the container simply sources it.

The setup.sh template rendering (Phase 6 Task 3) must add an additional read-only mount for this secrets file when the Keychain provider is selected.

Setup.sh integration: if selected, prompt for keychain service name. Run the host-side keychain read immediately during setup to validate access. Explain how to add secrets: `security add-generic-password -s "claude-env" -a "API_KEY" -w "value"`.

**Testing:**

Manual verification: add a test secret to Keychain, run provider, verify output.

**Commit:** `feat: add macOS Keychain secrets provider`
<!-- END_TASK_5 -->
<!-- END_SUBCOMPONENT_B -->

<!-- START_TASK_6 -->
### Task 6: Integrate secrets selection into setup.sh and devcontainer.json

**Verifies:** claude-mac-env.AC7.4, claude-mac-env.AC7.5

**Files:**
- Modify: `setup.sh` (add secrets selection to interactive flow)
- Modify: `.devcontainer/devcontainer.json.template` (add postCreateCommand for bootstrap-secrets.sh)

**Implementation:**

Add `select_secrets_provider()` function to setup.sh that:
1. Presents menu: "How should secrets be managed?"
   - 1) .env file (simple, secrets on disk)
   - 2) Azure Key Vault (requires az CLI)
   - 3) macOS Keychain (native, no file on disk)
   - 4) Skip (no secrets management)
2. If .env: prompt for file path, validate it exists
3. If Azure: check az CLI (install if missing), prompt for vault name
4. If Keychain: prompt for service name
5. If Skip: set `secrets.provider=none` in config
6. Store selection in `.user-config.json`

Update devcontainer.json.template to include:
- postCreateCommand that runs `config/bootstrap-secrets.sh`
- Conditional mount for .env file (if that provider is selected)
- Mount for config/ directory (read-only, so provider scripts are available in container)

Provider selection persists in `.user-config.json` which survives container rebuilds (it's on the Mac host).

**Verification:**

Run setup.sh, select "Skip" → container starts without secrets, no errors
Run setup.sh, select ".env" → .env file mounted and sourced in container
Re-run setup.sh → previous selection shown as default

**Commit:** `feat: integrate secrets selection into setup.sh`
<!-- END_TASK_6 -->
