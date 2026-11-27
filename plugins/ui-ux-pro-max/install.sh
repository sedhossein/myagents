#!/usr/bin/env bash
# Installs or updates the third-party UI UX Pro Max skills
# (https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) the way its README
# documents: the Claude Code marketplace, and the uipro CLI for Cursor and Codex.
# Run by the root install.sh.
set -euo pipefail
# shellcheck source=../../scripts/install-lib.sh
source "$MYAGENTS_DIR/scripts/install-lib.sh"

REPO_URL="https://github.com/nextlevelbuilder/ui-ux-pro-max-skill.git"

# The README installs the CLI with `npm install -g ui-ux-pro-max-cli`; npx runs
# the same latest release without leaving a global package behind.
uipro() { npx -y ui-ux-pro-max-cli@latest "$@"; }

UIPRO_SKILLS=(ui-ux-pro-max design design-system ui-styling brand banner-design slides)

# --force overwrites the files from an earlier install, so a rerun updates them.
uipro_install() {
  local label="$1" ai="$2" hint="$3"
  if ! command -v npx &>/dev/null; then
    fail "$label" "node is not installed, so ui-ux-pro-max was skipped. Install it with: brew install node"
  elif quietly uipro init --ai "$ai" --global --force; then
    ok "$label" "Installed. $hint to load it."
  else
    fail "$label" "Could not install ui-ux-pro-max."
  fi
}

has_claude_code && claude_marketplace_plugin "$REPO_URL" ui-ux-pro-max-skill ui-ux-pro-max
has_cursor && uipro_install "Cursor" cursor "Start a new chat"
has_codex && uipro_install "Codex" codex "Restart Codex"

# Copilot does not read ~/.cursor/skills, so its skills are linked into the folder
# it does read. They link to the copy another tool already installed (Cursor's, or
# Codex's in ~/.agents/skills); only when there is none does the universal target
# install one, so there is never a second copy of the same skills.
if has_copilot; then
  skills_from="$HOME/.cursor/skills"
  if ! has_cursor; then
    skills_from="$HOME/.agents/skills"
    has_codex || uipro_install "Copilot" universal "Start a new Copilot chat"
  fi
  if quietly link_skills "$(copilot_skills_dir)" "${UIPRO_SKILLS[@]/#/$skills_from/}"; then
    ok "Copilot" "Installed. Start a new Copilot chat to load it."
  else
    fail "Copilot" "Could not link the skills into $(copilot_skills_dir)."
  fi
fi

finish
