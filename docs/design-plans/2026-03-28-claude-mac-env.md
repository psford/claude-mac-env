# Claude Mac Environment Design

## Summary

This project builds a containerized Claude Code development environment for Apple Silicon Macs, replacing direct host-machine setup with a Docker container managed by VS Code's Dev Containers extension. The environment runs Claude Code and all associated tooling inside an isolated Ubuntu container, with only explicitly selected project directories and credential files (`.gitconfig`, `.ssh`) surfaced through controlled mounts — keeping the Mac host filesystem otherwise invisible to the container.

The delivery mechanism is a single `setup.sh` bootstrap script that installs all prerequisites through Homebrew (no manual website downloads), prompts the user for their GitHub identity and project locations, and generates a `devcontainer.json` configuration file tailored to their selections. Tooling beyond the base runtime is packaged as Dev Container Features — independently versioned, OCI-published modules hosted on GHCR — so each tier of tooling (universal hooks, language-specific SDKs, personal utilities) can be installed selectively based on who is running the setup. A `tooling-manifest.json` catalog in the companion `claude-env` repo drives that selection, and a commit-hook classification agent keeps the manifest current as new tools are added. The design is intentionally runtime-agnostic: because the base image and Features use standard OCI formats, the environment can migrate off Docker Desktop to Apple's native container runtime when that matures, with no changes to images or Feature packages.

## Definition of Done

1. A new `claude-mac-env` repo exists on GitHub with:
   - `setup.sh` bootstrap script
   - Base Dockerfile (multi-distro support)
   - Dev Container Features published to GHCR
   - `tooling-manifest.json` schema and documentation

2. `setup.sh` on a fresh Apple Silicon Mac:
   - Detects and installs dependencies via Homebrew (CLI-first, no website visits)
   - Prompts for GitHub username and project directories
   - Routes `psford` to full install, others to tiered selection via manifest
   - Generates a working `.devcontainer/devcontainer.json`
   - Results in a working Dev Container in VS Code

3. The running container:
   - Mounts project directories read-write
   - Mounts `.gitconfig` and `.ssh` read-only
   - Has no other Mac filesystem visibility
   - Runs Claude Code successfully
   - Reconnects seamlessly on VS Code reopen (no rebuild needed day-to-day)

4. Dev Container Features install correctly:
   - `claude-skills` (always installed)
   - `universal-hooks` (offered to non-psford users)
   - `csharp-tools` (offered by language relevance)
   - `psford-personal` (psford only)

5. Nuke and pave: destroying the container and re-running `setup.sh` restores the full environment from GitHub sources.

6. `tooling-manifest.json` in `claude-env` has a commit hook that classifies new tools automatically.

## Acceptance Criteria

### claude-mac-env.AC1: Bootstrap installs dependencies CLI-first
- **claude-mac-env.AC1.1 Success:** Homebrew installed non-interactively when missing
- **claude-mac-env.AC1.2 Success:** Docker Desktop installed via brew cask when missing (with user permission)
- **claude-mac-env.AC1.3 Success:** VS Code installed via brew cask when missing (with user permission)
- **claude-mac-env.AC1.4 Success:** Dev Containers extension auto-installed via code CLI
- **claude-mac-env.AC1.5 Success:** All preflight checks pass silently on fully-equipped Mac
- **claude-mac-env.AC1.6 Failure:** Script exits with clear message on Intel Mac
- **claude-mac-env.AC1.7 Edge:** User declines VS Code install — script continues (non-blocking)

### claude-mac-env.AC2: Identity routing and tiered selection
- **claude-mac-env.AC2.1 Success:** GitHub username `psford` enables all Features without prompts
- **claude-mac-env.AC2.2 Success:** Other usernames see tiered selection from manifest
- **claude-mac-env.AC2.3 Success:** Universal tools presented with descriptions and y/n prompt
- **claude-mac-env.AC2.4 Success:** Language tools grouped by language with y/n per group
- **claude-mac-env.AC2.5 Success:** Personal tier never shown to non-psford users
- **claude-mac-env.AC2.6 Edge:** Empty manifest gracefully installs only claude-skills

### claude-mac-env.AC3: Container filesystem isolation
- **claude-mac-env.AC3.1 Success:** Project dirs writable from inside container
- **claude-mac-env.AC3.2 Success:** .gitconfig readable but not writable from container
- **claude-mac-env.AC3.3 Success:** .ssh readable but not writable from container
- **claude-mac-env.AC3.4 Success:** No other Mac paths visible inside container
- **claude-mac-env.AC3.5 Failure:** Write attempt to read-only mount fails with permission error

### claude-mac-env.AC4: Dev Container Features
- **claude-mac-env.AC4.1 Success:** claude-skills Feature installs and skills are usable
- **claude-mac-env.AC4.2 Success:** universal-hooks Feature installs and hooks trigger on git ops
- **claude-mac-env.AC4.3 Success:** csharp-tools Feature installs .NET SDK at configured version
- **claude-mac-env.AC4.4 Success:** psford-personal Feature installs all personal tooling
- **claude-mac-env.AC4.5 Success:** Features publish to GHCR via GitHub Actions
- **claude-mac-env.AC4.6 Edge:** Feature install on non-Ubuntu distro uses correct package manager

### claude-mac-env.AC5: Day-to-day and rebuild workflow
- **claude-mac-env.AC5.1 Success:** VS Code reconnects to existing container without rebuild
- **claude-mac-env.AC5.2 Success:** Claude Code runs and can edit files in /workspaces
- **claude-mac-env.AC5.3 Success:** Container survives Mac sleep/wake cycle
- **claude-mac-env.AC5.4 Success:** 'Rebuild Container' reinstalls Features from GHCR
- **claude-mac-env.AC5.5 Success:** Destroying container + re-running setup.sh restores full env

### claude-mac-env.AC6: Manifest classification hook
- **claude-mac-env.AC6.1 Success:** New file in claude-env triggers classification agent
- **claude-mac-env.AC6.2 Success:** Agent assigns tier, language, and Feature to new tool
- **claude-mac-env.AC6.3 Success:** Manifest diff shown for author review before push
- **claude-mac-env.AC6.4 Edge:** Already-cataloged file changes don't duplicate manifest entries

### claude-mac-env.AC7: Pluggable secrets
- **claude-mac-env.AC7.1 Success:** Azure Key Vault provider injects secrets into container
- **claude-mac-env.AC7.2 Success:** .env provider reads from user-specified path
- **claude-mac-env.AC7.3 Success:** macOS Keychain provider reads via security CLI
- **claude-mac-env.AC7.4 Success:** Skipping secrets during setup results in working container
- **claude-mac-env.AC7.5 Success:** Selected provider persists across container rebuilds

## Glossary

- **Dev Container / Dev Containers extension**: A VS Code feature (and open specification) that defines a development environment inside a Docker container via a `devcontainer.json` config file. VS Code connects to the container and operates as if it were the local machine.

- **Dev Container Features**: Modular, self-contained tooling packages that layer on top of a base Dev Container image. Each Feature is an independent `install.sh` plus metadata, published as an OCI artifact and referenced by name in `devcontainer.json`.

- **GHCR (GitHub Container Registry)**: GitHub's built-in registry for storing and distributing OCI container images and artifacts. Used here to host published Dev Container Features.

- **OCI artifact**: Any package conforming to the Open Container Initiative image specification — includes container images but also arbitrary blobs (such as Dev Container Features). OCI compatibility is what allows images and Features to be consumed by runtimes other than Docker.

- **`devcontainer.json`**: The configuration file read by the Dev Containers extension. Specifies the base image, which Features to install, filesystem mounts, VS Code extensions, and lifecycle commands (e.g., `postCreateCommand`).

- **Homebrew / brew cask**: The dominant CLI package manager for macOS. `brew cask` installs macOS GUI applications (`.app` bundles) from the command line, as opposed to formulae which install CLI tools.

- **Apple Silicon / Apple Containers**: "Apple Silicon" refers to Apple's ARM-based M-series chips (M1 and later). "Apple Containers" refers to Apple's native container runtime (distinct from Docker Desktop), which this design is written to be compatible with.

- **`tooling-manifest.json`**: A catalog file in the `claude-env` repo that records every hook and helper script with its tier, language affinity, target Feature, and description. Consumed by `setup.sh` to drive tiered selection for non-owner users.

- **Tier (universal / language / personal)**: A classification in `tooling-manifest.json` describing intended audience: `universal` tools are broadly useful, `language` tools target specific stacks, `personal` tools are owner-specific and never offered to others.

- **WSL2**: Windows Subsystem for Linux v2 — a compatibility layer that runs a Linux kernel inside Windows. The `claude-env` repo implements this environment for WSL2; this design is its macOS equivalent.

- **`postCreateCommand`**: A `devcontainer.json` lifecycle hook that runs a shell command once after the container is created. Used here to invoke the selected secrets provider.

- **`installsAfter`**: A Dev Container Features metadata field that declares ordering dependencies between Features, ensuring one installs before another.

- **EF (Entity Framework)**: Microsoft's ORM for .NET. Referenced as the subject of migration hooks in `csharp-tools`.

- **Classification agent**: An AI agent invoked by a git commit hook in `claude-env` that automatically assigns tier, language, and Feature metadata to new or changed tool files, then updates `tooling-manifest.json` for author review.

- **Nuke and pave**: Fully destroying an environment (deleting the container and all generated config) and rebuilding from source. A design goal is that re-running `setup.sh` after a nuke-and-pave fully restores the environment.

## Architecture

Containerized Claude Code development environment for Apple Silicon Macs, built on Docker Desktop and VS Code Dev Containers with modular tooling delivered via Dev Container Features.

### System Overview

```
Mac Host                              Docker Container
┌─────────────────────┐              ┌──────────────────────────┐
│                     │              │  Ubuntu (or user-chosen)  │
│  VS Code            │◄── Dev ────►│                          │
│  + Dev Containers   │  Containers │  Claude Code CLI          │
│    extension        │  extension  │  Node.js LTS              │
│                     │              │  Python 3.x               │
│  ~/Projects ────────┼── RW ──────►│  /workspaces              │
│  ~/.gitconfig ──────┼── RO ──────►│  /home/claude/.gitconfig  │
│  ~/.ssh ────────────┼── RO ──────►│  /home/claude/.ssh        │
│                     │              │                          │
│  (everything else   │              │  Dev Container Features:  │
│   invisible)        │              │  ├── claude-skills        │
│                     │              │  ├── universal-hooks      │
└─────────────────────┘              │  ├── csharp-tools (opt)   │
                                     │  └── psford-personal (opt)│
                                     └──────────────────────────┘
```

### Key Components

**`setup.sh`** — Single entry point for bootstrapping. Handles dependency detection/installation via Homebrew, interactive user prompts (GitHub username, project dirs, distro choice), identity-based routing for tooling tiers, and generation of `.devcontainer/devcontainer.json` from a template.

**Base Dockerfile** — Minimal image containing only runtime prerequisites: Ubuntu 24.04 (default, user-selectable), git, curl, jq, build-essential, Node.js LTS, Python 3.x, Claude Code CLI, and a non-root `claude` user (UID 1000). Language SDKs (e.g., .NET) are intentionally excluded — they arrive via Features.

**Dev Container Features** — Modular, independently versioned tooling packages published to GHCR as OCI artifacts. Each Feature has its own `install.sh` with distro detection for package manager compatibility. Four Features defined at launch:

| Feature | Tier | Install Behavior |
|---------|------|-----------------|
| `claude-skills` | Always | Installs ed3d plugin skills + psford custom skills. No prompt. |
| `universal-hooks` | Broadly applicable | Git branch protection, log sanitization, commit atomicity, doc hooks, commit permission hooks. Offered to non-psford users with descriptions. |
| `csharp-tools` | Language-specific | .NET SDK (version configurable), EF migration hooks, WPF rebuild reminders, C# test helpers. Offered based on language relevance. |
| `psford-personal` | Personal | Project-specific helpers, Slack integration, Stream Deck assets, Azure tooling. Installed only when GitHub username = `psford`. |

**`tooling-manifest.json`** — Lives in the `claude-env` repo. Master catalog that tags every hook/helper with tier (`universal`, `language`, `personal`), language affinity, target Feature, and description. Used by `setup.sh` to present tiered selection to non-psford users. Kept current by a commit hook that runs a classification agent on new/changed files.

**`.devcontainer/devcontainer.json.template`** — Template with placeholders for distro, Features, mounts, and VS Code extensions. `setup.sh` renders the final `devcontainer.json` from this template based on user selections.

**Pluggable secrets providers** — `config/secrets-azure.sh`, `config/secrets-env.sh`, `config/secrets-keychain.sh`. Each implements a common interface for injecting secrets into the container. Selected during setup, executed at container start. Designed but not fully specified here — separate design effort.

### Data Flow

1. User clones `claude-mac-env`, runs `./setup.sh`
2. Script checks/installs: Homebrew → Xcode CLT → Docker Desktop → VS Code → Dev Containers extension
3. Script prompts for GitHub username, project directories, distro preference
4. If `psford`: all Features enabled. Otherwise: manifest-driven tiered selection.
5. Script generates `.devcontainer/devcontainer.json` with selected Features and mounts
6. Script builds base Docker image (`docker build`)
7. User opens project in VS Code → Dev Containers extension detects config → builds container with Features → environment ready
8. Day-to-day: VS Code reconnects to running container automatically (green indicator, no rebuild)

## Existing Patterns

### Patterns from `claude-env`

The `claude-env` repo already implements the WSL2 version of this environment:
- `infrastructure/wsl/wsl-setup.sh` — Ubuntu provisioning script (model for `setup.sh`)
- `infrastructure/wsl/verify-setup.sh` — Component validation (model for preflight checks)
- `infrastructure/wsl/pull-secrets.sh` — Azure Key Vault integration (model for pluggable secrets)
- `.claude/hooks/` — Git hooks for branch protection, log sanitization, commit atomicity (content for `universal-hooks` Feature)
- `helpers/` — Testing utilities, security scanners, doc tools (content split across Features by tier)

This design follows the same organizational philosophy: centralized environment config, hook-based enforcement, helper scripts for common tasks. The key divergence is delivery mechanism — WSL2 scripts install directly, while this design packages tooling as Dev Container Features for modularity and shareability.

### Patterns from `bsky-feed-filter`

Docker security practices from `bsky-feed-filter` inform the container configuration:
- Non-root user in Dockerfile
- Minimal base image
- Read-only filesystem where possible
- Dropped capabilities

### New Patterns Introduced

- **Dev Container Features as tooling delivery mechanism** — new to this ecosystem, chosen for standards alignment and shareability
- **Manifest-driven tool classification** — `tooling-manifest.json` is new; enables identity-based install routing without hardcoding
- **Commit-hook classification agent** — AI-assisted manifest maintenance is new; keeps catalog current as tools are added

## Implementation Phases

<!-- START_PHASE_1 -->
### Phase 1: Repository Scaffolding and Base Dockerfile

**Goal:** Create the `claude-mac-env` repo with a working base Docker image that runs Claude Code.

**Components:**
- GitHub repo `claude-mac-env` with MIT license, README
- `Dockerfile` — multi-distro base image (Ubuntu default, build arg for distro selection), non-root `claude` user, Node.js LTS, Python 3.x, git, Claude Code CLI
- `.devcontainer/devcontainer.json` — minimal hardcoded config (no template yet) with basic mounts
- `.gitignore` for generated files

**Dependencies:** None (first phase)

**Done when:** `docker build` succeeds, container starts, Claude Code runs inside it, VS Code attaches via Dev Containers extension with project dir mounted read-write and dotfiles read-only.
<!-- END_PHASE_1 -->

<!-- START_PHASE_2 -->
### Phase 2: Dev Container Features — `claude-skills` and `universal-hooks`

**Goal:** Package the two always/broadly-applicable tooling tiers as Dev Container Features and publish to GHCR.

**Components:**
- `features/claude-skills/` — `devcontainer-feature.json` + `install.sh` that pulls and installs ed3d plugin skills and psford custom skills
- `features/universal-hooks/` — `devcontainer-feature.json` + `install.sh` that installs git branch protection, log sanitization, commit atomicity, doc hooks, and commit permission hooks. Distro-agnostic (pure git/shell).
- GitHub Actions workflow for building and publishing Features to GHCR as OCI artifacts
- Updated `.devcontainer/devcontainer.json` referencing the published Features

**Dependencies:** Phase 1 (base image exists)

**Done when:** Features publish to GHCR via CI. Container built with both Features has working skills and git hooks. Hooks trigger correctly on git operations inside the container.
<!-- END_PHASE_2 -->

<!-- START_PHASE_3 -->
### Phase 3: Dev Container Features — `csharp-tools` and `psford-personal`

**Goal:** Package the language-specific and personal tooling tiers as Features.

**Components:**
- `features/csharp-tools/` — `devcontainer-feature.json` (with `dotnetVersion` option) + `install.sh` that installs .NET SDK, EF migration hooks, WPF rebuild reminders, C# test helpers. Distro-aware (apt vs dnf for SDK install).
- `features/psford-personal/` — `devcontainer-feature.json` + `install.sh` that installs project-specific helpers, Slack integration, Stream Deck asset tools, Azure CLI tooling
- Feature dependency declarations (`installsAfter` for ordering)

**Dependencies:** Phase 2 (Feature publishing workflow exists)

**Done when:** Both Features publish to GHCR. Container with all four Features has working .NET SDK, C# hooks, and personal tooling. Feature options (e.g., .NET version) work correctly.
<!-- END_PHASE_3 -->

<!-- START_PHASE_4 -->
### Phase 4: `tooling-manifest.json` and Classification Hook

**Goal:** Create the manifest schema and the commit-hook classification agent in `claude-env`.

**Components:**
- `tooling-manifest.json` schema definition and initial populated manifest in `claude-env` repo — every existing hook/helper tagged with tier, language, Feature assignment, description
- Commit hook in `claude-env` that detects new/changed files not in the manifest, runs a classification agent, updates the manifest, and presents the diff for author review
- Documentation for manifest schema and classification categories

**Dependencies:** Phase 3 (all Features defined, so manifest can reference them)

**Done when:** Manifest accurately catalogs all existing `claude-env` tools. Adding a new hook/helper to `claude-env` triggers the classification agent and the manifest updates automatically. Author can review and adjust before pushing.
<!-- END_PHASE_4 -->

<!-- START_PHASE_5 -->
### Phase 5: `setup.sh` — Dependency Preflight

**Goal:** Build the dependency detection and CLI-first installation portion of the bootstrap script.

**Components:**
- `setup.sh` preflight section — checks for Homebrew, Xcode CLT, Docker Desktop, VS Code, Dev Containers extension, Apple Silicon
- Homebrew auto-install (`NONINTERACTIVE=1`) with user permission
- Cask installs for Docker Desktop and VS Code (`--no-quarantine`) with user permission
- Extension auto-install via `code --install-extension`
- Clear error messages and graceful handling for each missing dependency
- Apple Silicon gate (exit with message on Intel)

**Dependencies:** Phase 1 (repo exists to put the script in)

**Done when:** Running `setup.sh` on an Apple Silicon Mac with nothing installed detects all missing dependencies, offers to install each via CLI, and results in all prerequisites present. Running on a fully-equipped Mac skips all installs gracefully.
<!-- END_PHASE_5 -->

<!-- START_PHASE_6 -->
### Phase 6: `setup.sh` — Interactive Setup and Config Generation

**Goal:** Build the interactive prompts, identity routing, and `devcontainer.json` generation.

**Components:**
- Interactive prompts: GitHub username, project directories (multi-path), distro selection (default Ubuntu)
- Identity routing: if `psford` → all Features. Otherwise → read `tooling-manifest.json` from `claude-env` repo, present tiered selection (universal with descriptions → y/n, language-specific grouped by language → y/n, personal → skip)
- `.devcontainer/devcontainer.json.template` with placeholders for image, Features, mounts, extensions
- Template rendering logic in `setup.sh` that produces final `devcontainer.json`
- `docker build` invocation for base image
- User config persistence (so re-running setup remembers previous choices)

**Dependencies:** Phase 4 (manifest exists for tiered selection), Phase 5 (preflight complete)

**Done when:** Full `setup.sh` flow works end-to-end: preflight → prompts → identity routing → tier selection → config generation → image build. Generated `devcontainer.json` references correct Features and mounts. VS Code opens and builds the container successfully.
<!-- END_PHASE_6 -->

<!-- START_PHASE_7 -->
### Phase 7: Pluggable Secrets Framework

**Goal:** Establish the secrets provider interface and implement the three initial providers.

**Components:**
- `config/secrets-interface.sh` — common interface definition (source, validate, inject functions)
- `config/secrets-azure.sh` — Azure Key Vault provider (requires `az` CLI auth)
- `config/secrets-env.sh` — `.env` file provider (reads from user-specified path on Mac)
- `config/secrets-keychain.sh` — macOS Keychain provider (reads via `security` CLI)
- Integration with `setup.sh` — secrets method selection during setup (or skip)
- Integration with container startup — selected provider runs at container start via `postCreateCommand`

**Dependencies:** Phase 6 (setup flow exists to integrate with)

**Done when:** Each secrets provider can be selected during setup and injects secrets into the running container. Skipping secrets works cleanly. Provider selection persists across rebuilds.
<!-- END_PHASE_7 -->

<!-- START_PHASE_8 -->
### Phase 8: Documentation, Testing, and Release

**Goal:** Documentation for users and contributors, end-to-end validation, and first release.

**Components:**
- `README.md` — quickstart guide, prerequisites, setup walkthrough, day-to-day usage, nuke-and-pave instructions, sharing guide
- `CONTRIBUTING.md` — how to add new Features, manifest schema, classification hook usage
- End-to-end test script that validates the full flow on a clean system (or as close as possible in CI)
- GitHub Actions CI for base image build, Feature publishing, and setup script linting
- Tagged v1.0 release

**Dependencies:** All previous phases

**Done when:** A new user can follow the README to go from zero to working environment. CI passes. Release tagged and published.
<!-- END_PHASE_8 -->

## Additional Considerations

**Apple Containers migration path:** The base Dockerfile produces an OCI-compatible image and all Features use OCI artifacts on GHCR. When Apple's native container solution matures (full networking, better volume support, Compose-equivalent tooling), migration should require only changing the runtime — not rebuilding images or Features. No design changes needed now, but avoid Docker-Desktop-specific features that wouldn't exist in Apple Containers.

**Distro support in Feature install scripts:** Each Feature's `install.sh` must detect the container OS and use the appropriate package manager. A shared utility function (`detect-package-manager.sh`) should be included in the base image to avoid duplicating this logic across Features.

**Implementation scoping:** This design has exactly 8 phases, fitting within the implementation plan limit. Phase 7 (secrets) and Phase 8 (docs/release) could be deferred to a second implementation round if velocity favors shipping the core experience first.
