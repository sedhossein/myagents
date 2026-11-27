#!/usr/bin/env bash
# Installs or updates the third-party ponytail plugin
# (https://github.com/DietrichGebert/ponytail). Run by the root install.sh.
set -euo pipefail
# shellcheck source=../../scripts/install-lib.sh
source "$MYAGENTS_DIR/scripts/install-lib.sh"

# The HTTPS URL keeps Claude Code from cloning over SSH, which needs GitHub keys.
REPO_URL="https://github.com/DietrichGebert/ponytail.git"
CHECKOUT_DIR="$MYAGENTS_DIR/plugins/ponytail/checkout"

if ! command -v node &>/dev/null; then
  note "Requirements" "node is not installed, so ponytail's hooks will not run. Install it with: brew install node"
fi

has_claude_code && claude_marketplace_plugin "$REPO_URL" ponytail ponytail
has_codex && codex_marketplace_plugin "$REPO_URL" ponytail ponytail
has_copilot_cli && copilot_marketplace_plugin "$REPO_URL" ponytail ponytail

# Cursor has no ponytail plugin. Its hook installer adds two hooks to
# ~/.cursor/hooks.json that run node scripts from a checkout, and replaces its
# own entries on a rerun.
if has_cursor; then
  if quietly sync_checkout "$REPO_URL" "$CHECKOUT_DIR" \
    && command -v node &>/dev/null \
    && quietly node "$CHECKOUT_DIR/scripts/cursor-hooks.js" install; then
    ok "Cursor" "Installed. Start a new chat to load it."
  else
    fail "Cursor" "Could not add ponytail's hooks to ~/.cursor/hooks.json."
  fi
fi

# OpenCode: ponytail's skills are linked from the checkout. Its hooks have no
# OpenCode form, so the skill's own description triggers it.
if has_opencode; then
  if quietly sync_checkout "$REPO_URL" "$CHECKOUT_DIR" \
    && quietly link_skills "$(opencode_dir)/skills" "$CHECKOUT_DIR"/skills/*/; then
    ok "OpenCode" "Installed. Start a new session to load it."
  else
    fail "OpenCode" "Could not link ponytail's skills into $(opencode_dir)/skills."
  fi
fi

finish
