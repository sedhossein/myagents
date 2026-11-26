#!/usr/bin/env bash
# Removes the agent-memory plugin. Run by the root uninstall.sh. The memory
# database in ~/.agent-memory belongs to the user and is kept.
set -euo pipefail
# shellcheck source=../../scripts/install-lib.sh
source "$MYAGENTS_DIR/scripts/install-lib.sh"

CHECKOUT_DIR="$MYAGENTS_DIR/plugins/agent-memory/checkout"
CURSOR_PLUGIN_DIR="$HOME/.cursor/plugins/local/agent-memory"

has_claude_code && claude_marketplace_plugin_remove agent-memory agent-memory

if has_cursor; then
  memory_skills=()
  for dir in "$CHECKOUT_DIR"/plugins/agent-memory/skills/*/; do
    [ -d "$dir" ] && memory_skills+=("$(basename "$dir")")
  done
  cursor_extras=false
  for name in ${memory_skills[@]+"${memory_skills[@]}"}; do
    [ -f "$HOME/.cursor/skills/$name/.myagents" ] && cursor_extras=true
  done
  jq -e '.mcpServers["agent-memory"]' "$HOME/.cursor/mcp.json" &>/dev/null && cursor_extras=true
  if [ -d "$CURSOR_PLUGIN_DIR" ] || [ "$cursor_extras" = true ]; then
    rm -rf "$CURSOR_PLUGIN_DIR"
    remove_copied_skills "$HOME/.cursor/skills" ${memory_skills[@]+"${memory_skills[@]}"}
    [ -f "$HOME/.cursor/mcp.json" ] && quietly jq_set_file "$HOME/.cursor/mcp.json" 'del(.mcpServers["agent-memory"])'
    ok "Cursor" "Removed. Run 'Developer: Reload Window' to unload it."
  else
    ok "Cursor" "Already removed."
  fi
fi

has_codex && codex_marketplace_plugin_remove agent-memory agent-memory

has_copilot_cli && copilot_marketplace_plugin_remove agent-memory agent-memory
if has_copilot; then
  rule_removed=false
  rule_failed=false
  for file in "${COPILOT_HOME:-$HOME/.copilot}/copilot-instructions.md" "$(copilot_jetbrains_dir)/global-copilot-instructions.md"; do
    if ! quietly instructions_block uninstall "$file" agent-memory; then
      fail "Copilot" "Could not remove the memory rule from $file."
      rule_failed=true
    elif [ "$quiet_output" = "changed" ]; then
      rule_removed=true
    fi
  done
  if [ "$rule_failed" = true ]; then
    :
  elif [ "$rule_removed" = true ]; then
    ok "Copilot" "Memory rule removed. Start a new Copilot chat to unload it."
  else
    ok "Copilot" "Memory rule already removed."
  fi
fi

rm -rf "$CHECKOUT_DIR"

finish
