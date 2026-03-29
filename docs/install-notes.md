# Install Friction Log

Track every pain point, error, and workaround encountered during manual setup. Each entry informs how `setup.sh` should handle it automatically.

## Format

Each entry: what happened, what we tried, what worked, **why** it worked, and what `setup.sh` should do.

---

## 2026-03-28: gh CLI install via Homebrew

### What happened
`brew install gh` completed but failed at the `brew link` step. Two separate link failures:

1. **pkgconf conflict:** `brew link` couldn't symlink `bin/pkg-config` because an older `pkg-config` formula already owned that path. Brew suggested `brew unlink pkg-config` then `brew link --overwrite pkgconf`.

2. **Fish completions permission denied:** `brew link gh` failed because `/usr/local/share/fish/vendor_completions.d` was not writable. The gh binary was installed to `/usr/local/Cellar/gh/2.89.0/bin/gh` but never symlinked to `/usr/local/bin/gh`.

### What we tried (in order)
1. `brew link gh` — failed, same fish completions permission error
2. `sudo mkdir -p ... && sudo chmod 775 ...` — failed, no terminal for sudo password in this context (Claude Code running inside VS Code extension, no interactive terminal for sudo)
3. `ln -sf /usr/local/Cellar/gh/2.89.0/bin/gh /usr/local/bin/gh` — **worked**

### Why #3 worked
The fish completions failure was a red herring. The actual binary linking to `/usr/local/bin/` didn't require elevated permissions — `/usr/local/bin/` was writable by the user. `brew link` was failing on the *completions* symlink and stopping before it got to the binary symlink. Manually symlinking just the binary bypassed the irrelevant fish completions issue.

### Root cause analysis
- **pkgconf conflict:** Pre-existing Homebrew state. A fresh Mac wouldn't have this. But a Mac with any dev history likely will have stale formulae. `setup.sh` should run `brew update` and handle formula conflicts.
- **Fish completions:** This Mac has a `/usr/local/share/fish/` directory with restrictive permissions, probably from a prior fish shell install. Most users won't have this. But the pattern — `brew link` failing on non-essential completions and blocking the entire link — is a general Homebrew gotcha.

### What `setup.sh` should do
1. After any `brew install`, check if the binary is actually in PATH (`which <tool>`).
2. If not, attempt `brew link <tool>`.
3. If `brew link` fails, fall back to manual symlink: `ln -sf $(brew --prefix <tool>)/bin/<tool> /usr/local/bin/<tool>`.
4. Verify the binary works (`<tool> --version`) regardless of link status.
5. Don't fail the entire setup over completions/man pages — only the binary matters.

### Takeaway for users
Non-issue on a fresh Mac. On a Mac with existing Homebrew history, `brew link` failures are common and almost always fixable by symlinking the binary directly. The setup script should handle this transparently.

---

## 2026-03-28: gh CLI not authenticated

### What happened
`gh auth status` returns "You are not logged into any GitHub hosts." This requires `gh auth login` which launches a browser-based OAuth flow.

### Friction
This is an **unavoidable interactive step** — GitHub OAuth requires browser interaction. There's no way to fully automate this for a first-time user.

### What `setup.sh` should do
1. Check `gh auth status` first.
2. If not authenticated, explain what's about to happen: "GitHub authentication required. A browser window will open for you to authorize the gh CLI."
3. Run `gh auth login --web --git-protocol https`.
4. Wait for completion, verify with `gh auth status`.
5. If auth fails or user cancels, exit gracefully with instructions to run `gh auth login` manually and re-run setup.

### Takeaway for users
One-time interactive step. Can't be avoided, but can be explained clearly so it's not surprising.

---

## 2026-03-29: Git identity not configured

### What happened
First `git commit` in the new repo triggered a warning: "Your name and email address were configured automatically based on your username and hostname." Commit used `patrickford@Patricks-MacBook-Air.local` instead of the user's actual email.

### Friction
Not a hard stop — commit still succeeded — but the identity is wrong. On a fresh Mac, `~/.gitconfig` may not exist or may not have `user.name` / `user.email` set.

### What `setup.sh` should do
1. Check if `git config --global user.name` and `git config --global user.email` are set.
2. If not, this is a preflight item: prompt the user for their name and email, or offer to pull from their GitHub profile (`gh api user` returns name and email).
3. Run `git config --global user.name "..."` and `git config --global user.email "..."`.
4. This also affects the `.gitconfig` read-only mount into the container — if it's empty/missing, the container inherits the same problem.

### Why this matters for the container
The container mounts `~/.gitconfig` read-only. If git identity isn't configured on the Mac before the container starts, Claude Code inside the container will have the same unconfigured identity. This must be caught in preflight, not after the container is running.

### Takeaway for users
Solvable automatically. `setup.sh` should detect and configure git identity early in the preflight phase, ideally pulling from the GitHub profile since we already have `gh` authenticated.

---

## 2026-03-29: gh auth doesn't configure git credential helper

### What happened
After `gh auth login` succeeded, `git push` failed with `fatal: could not read Username for 'https://github.com': Device not configured`. The gh CLI was authenticated but git didn't know to use gh as its credential helper.

### What fixed it
`gh auth setup-git` — configures git to use gh as the credential helper. After this, `git push` worked immediately.

### Root cause
`gh auth login` authenticates the gh CLI tool. `gh auth setup-git` separately configures git's credential.helper to use gh for HTTPS auth. These are two distinct steps and the first doesn't automatically do the second.

### What `setup.sh` should do
After `gh auth login` succeeds, always run `gh auth setup-git` immediately. These should be treated as a single atomic operation in the setup flow. Never assume that gh auth implies git auth.

### Takeaway for users
Invisible if setup.sh handles it. But if a user is troubleshooting manually, "gh is authenticated but git push fails" is confusing. The error message gives no hint that `gh auth setup-git` is the fix.
