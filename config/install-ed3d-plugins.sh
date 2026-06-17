#!/usr/bin/env bash
# install-ed3d-plugins.sh — bake the PUBLIC ed3d plugin marketplace into the image
#
# Runs at Docker BUILD time, as the unprivileged `claude` user, AFTER the
# Claude Code CLI is installed (see Dockerfile). The ed3d marketplace is a
# public git repo, so no auth is required — which is exactly why this can run
# at build time rather than during bootstrap.
#
# WHY THIS EXISTS:
#   The Claude Code native binary loads plugins ONCE, at process startup, from
#   ~/.claude/plugins/installed_plugins.json + the ~/.claude/plugins/cache/
#   copies. Installing plugins during postCreateCommand (bootstrap) writes those
#   files into a session that has ALREADY read its plugin list, so the skills do
#   not appear until a full window/process restart. `/reload-skills` does not
#   reload plugins. Baking the plugins into the image means installed_plugins.json
#   + cache exist BEFORE the first `claude` process ever starts, so a fresh region
#   has the ed3d skills with zero manual reload.
#
# Auth-gated private plugins (psford/claude-config) cannot be baked here — they
# still install in config/bootstrap.sh where GitHub auth is available.

set -euo pipefail

ED3D_URL="https://github.com/ed3dai/ed3d-plugins.git"
ED3D_NAME="ed3d-plugins"
PLUGINS_DIR="${HOME}/.claude/plugins"
MARKETPLACE_DIR="${PLUGINS_DIR}/marketplaces/${ED3D_NAME}"
MANIFEST="${MARKETPLACE_DIR}/.claude-plugin/marketplace.json"
INSTALLED_JSON="${PLUGINS_DIR}/installed_plugins.json"

echo "Baking ${ED3D_NAME} into the image (build-time, public marketplace)..."

command -v claude >/dev/null 2>&1 || {
    echo "FATAL: claude CLI not on PATH — this must run after the CLI is installed." >&2
    exit 1
}
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq not found." >&2; exit 1; }

# ── Clone + register the marketplace ─────────────────────────────────────────
mkdir -p "$(dirname "$MARKETPLACE_DIR")"
if [ -d "${MARKETPLACE_DIR}/.git" ]; then
    git -C "$MARKETPLACE_DIR" pull --ff-only >/dev/null 2>&1 || true
else
    git clone --depth 1 "$ED3D_URL" "$MARKETPLACE_DIR" >/dev/null 2>&1 || {
        echo "FATAL: failed to clone ${ED3D_URL}" >&2
        exit 1
    }
fi

# `claude plugin marketplace add` writes ~/.claude/plugins/known_marketplaces.json,
# the file the running CLI actually reads. Idempotent — ignore "already added".
claude plugin marketplace add "$MARKETPLACE_DIR" >/dev/null 2>&1 || true

# ── Install every plugin the marketplace advertises ──────────────────────────
if [ ! -f "$MANIFEST" ]; then
    echo "FATAL: marketplace manifest not found at ${MANIFEST}" >&2
    exit 1
fi

mapfile -t PLUGINS < <(jq -r '.plugins[].name' "$MANIFEST")
if [ "${#PLUGINS[@]}" -eq 0 ]; then
    echo "FATAL: no plugins listed in ${MANIFEST}" >&2
    exit 1
fi

for plugin in "${PLUGINS[@]}"; do
    claude plugin install "${plugin}@${ED3D_NAME}" >/dev/null 2>&1 || true
done

# ── Make skills user-invocable (upstream ships user-invocable: false) ─────────
# Patch BOTH the marketplace source and the installed cache copies — the CLI
# loads the cache copy, so patching only the source leaves live skills stuck.
patched=0
for root in "$MARKETPLACE_DIR" "${PLUGINS_DIR}/cache/${ED3D_NAME}"; do
    [ -d "$root" ] || continue
    while IFS= read -r -d '' skill_file; do
        if grep -q 'user-invocable: false' "$skill_file" 2>/dev/null; then
            sed -i 's/user-invocable: false/user-invocable: true/' "$skill_file"
            patched=$((patched + 1))
        fi
    done < <(find "$root" -name "SKILL.md" -print0)
done
echo "Patched ${patched} skills to be user-invocable."

# ── Verify the bake actually took — fail the BUILD if not ─────────────────────
# This is the guardrail against silently shipping an image with no skills.
[ -f "$INSTALLED_JSON" ] || { echo "FATAL: ${INSTALLED_JSON} was never written." >&2; exit 1; }

missing=0
for plugin in "${PLUGINS[@]}"; do
    if ! jq -e --arg k "${plugin}@${ED3D_NAME}" '.plugins[$k]' "$INSTALLED_JSON" >/dev/null 2>&1; then
        echo "  ✗ ${plugin} did not install" >&2
        missing=$((missing + 1))
    fi
done

if [ "$missing" -gt 0 ]; then
    echo "FATAL: ${missing}/${#PLUGINS[@]} ed3d plugins failed to install at build time." >&2
    exit 1
fi

echo "✓ Baked ${#PLUGINS[@]} ed3d plugins into the image."
