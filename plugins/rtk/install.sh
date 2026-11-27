#!/usr/bin/env bash
# Installs or updates the third-party rtk hooks (https://github.com/rtk-ai/rtk) with its
# documented `rtk init` command for each detected tool. rtk filters command output
# before it reaches the model. Run by the root install.sh.
set -euo pipefail
# shellcheck source=../../scripts/install-lib.sh
source "$MYAGENTS_DIR/scripts/install-lib.sh"

need rtk

# --auto-patch applies the changes without prompting, and a rerun leaves the same result.
rtk_init() {
  local label="$1" hint="$2"
  shift 2
  if quietly rtk init -g --auto-patch "$@" </dev/null; then
    ok "$label" "Installed. $hint to load it."
  else
    fail "$label" "Could not install rtk."
  fi
}

has_claude_code && rtk_init "Claude Code" "Restart open sessions"
has_cursor && rtk_init "Cursor" "Start a new chat" --agent cursor
has_codex && rtk_init "Codex" "Restart Codex" --codex
has_copilot_cli && rtk_init "Copilot" "Start a new Copilot chat" --copilot

finish
