#!/usr/bin/env bash
# Removes the rtk hooks with the same `rtk init` command install.sh used, which deletes
# only what it wrote. Run by the root uninstall.sh.
set -euo pipefail
# shellcheck source=../../scripts/install-lib.sh
source "$MYAGENTS_DIR/scripts/install-lib.sh"

need rtk

# $3 is a command that succeeds while rtk's files for that tool are still there.
rtk_remove() {
  local label="$1" hint="$2" present="$3"
  shift 3
  if ! eval "$present" &>/dev/null; then
    ok "$label" "Already removed."
  elif quietly rtk init -g --uninstall "$@" </dev/null; then
    ok "$label" "Removed. $hint to unload it."
  else
    fail "$label" "Could not remove rtk."
  fi
}

# The Claude Code removal is the broad one and also clears other tools' hooks, so it runs last
# and the specific tools report their own removal.
has_cursor && rtk_remove "Cursor" "Start a new chat" 'grep -q "rtk hook cursor" "$HOME/.cursor/hooks.json"' --agent cursor
has_codex && rtk_remove "Codex" "Restart Codex" '[ -f "${CODEX_HOME:-$HOME/.codex}/RTK.md" ]' --codex
has_copilot_cli && rtk_remove "Copilot" "Start a new Copilot chat" '[ -f "${COPILOT_HOME:-$HOME/.copilot}/hooks/rtk-rewrite.json" ]' --copilot
has_claude_code && rtk_remove "Claude Code" "Restart open sessions" '[ -f "$HOME/.claude/RTK.md" ]'

finish
