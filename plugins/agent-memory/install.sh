#!/usr/bin/env bash
# Installs or updates the agent-memory plugin
# (https://github.com/RashadAnsari/agent-memory). Run by the root install.sh.
set -euo pipefail
# shellcheck source=../../scripts/install-lib.sh
source "$MYAGENTS_DIR/scripts/install-lib.sh"

# The HTTPS URL keeps Claude Code from cloning over SSH, which needs GitHub keys.
REPO_URL="https://github.com/RashadAnsari/agent-memory.git"
CHECKOUT_DIR="$MYAGENTS_DIR/plugins/agent-memory/checkout"
CURSOR_PLUGIN_DIR="$HOME/.cursor/plugins/local/agent-memory"

has_claude_code && claude_marketplace_plugin "$REPO_URL" agent-memory agent-memory

# The README installs the Cursor plugin by copying its folder into Cursor's
# local plugins folder. Cursor skips symlinks that point outside that folder,
# so it is a copy, refreshed from a checkout on every run. The Cursor agent in
# other hosts, such as the JetBrains AI chat, does not load plugins, so the skills
# are also copied into ~/.cursor/skills and the MCP server is registered in
# ~/.cursor/mcp.json by key, which a rerun overwrites.
if has_cursor; then
  PLUGIN_DIR="$CHECKOUT_DIR/plugins/agent-memory"
  if quietly sync_checkout "$REPO_URL" "$CHECKOUT_DIR" \
    && rm -rf "$CURSOR_PLUGIN_DIR" \
    && mkdir -p "$(dirname "$CURSOR_PLUGIN_DIR")" \
    && cp -R "$PLUGIN_DIR" "$CURSOR_PLUGIN_DIR" \
    && quietly copy_skills "$HOME/.cursor/skills" "$PLUGIN_DIR"/skills/*/ \
    && quietly jq_set_file "$HOME/.cursor/mcp.json" '.mcpServers["agent-memory"] = {command: "bash", args: ["-c", ("exec \"" + $dir + "/scripts/run-with-uv.sh\" run --directory \"" + $dir + "/mcp-servers/agent-memory\" agent-memory")]}' --arg dir "$PLUGIN_DIR"; then
    ok "Cursor" "Installed. Run 'Developer: Reload Window' to load it."
  else
    fail "Cursor" "Could not copy agent-memory into ~/.cursor/plugins/local/."
  fi
fi

has_codex && codex_marketplace_plugin "$REPO_URL" agent-memory agent-memory

# Copilot CLI installs the plugin (skills, MCP server, hooks) from the repository's
# marketplace. The memory rule is also written into the instructions files, since
# the JetBrains plugin has no hooks to deliver it. The rule comes from the checkout.
has_copilot_cli && copilot_marketplace_plugin "$REPO_URL" agent-memory agent-memory
if has_copilot; then
  RULE="$CHECKOUT_DIR/plugins/agent-memory/rules/agent-memory.mdc"
  if quietly sync_checkout "$REPO_URL" "$CHECKOUT_DIR" && [ -f "$RULE" ]; then
    copilot_ok=true
    if has_copilot_cli && ! quietly instructions_block install "${COPILOT_HOME:-$HOME/.copilot}/copilot-instructions.md" agent-memory "$RULE"; then
      fail "Copilot" "Could not write the memory rule to ${COPILOT_HOME:-$HOME/.copilot}/copilot-instructions.md."
      copilot_ok=false
    fi
    if has_copilot_jetbrains && ! quietly instructions_block install "$(copilot_jetbrains_dir)/global-copilot-instructions.md" agent-memory "$RULE"; then
      fail "Copilot" "Could not write the memory rule to $(copilot_jetbrains_dir)."
      copilot_ok=false
    fi
    if [ "$copilot_ok" = true ]; then
      ok "Copilot" "Memory rule added. Start a new Copilot chat to load it."
    fi
  else
    fail "Copilot" "Could not download agent-memory to read its rule."
  fi
fi

finish
