#!/usr/bin/env bash
# Installs or updates Upstash's third-party Context7 (https://github.com/upstash/context7)
# with its documented `ctx7 setup` command. Run by the root install.sh.
set -euo pipefail
# shellcheck source=../../scripts/install-lib.sh
source "$MYAGENTS_DIR/scripts/install-lib.sh"

# --mcp --oauth --yes is ctx7's documented unattended form: it registers the MCP
# server plus Context7's rule and skill, and the app runs the sign-in on first
# use, so no API key is written to disk. A rerun reconfigures in place.
ctx7() { CTX7_TELEMETRY_DISABLED=1 npx -y ctx7@latest "$@" </dev/null; }

ctx7_install() {
  local label="$1" agent="$2" next="$3"
  if ! command -v npx &>/dev/null; then
    fail "$label" "node is not installed, so Context7 was skipped. Install it with: brew install node"
  elif quietly ctx7 setup --mcp --oauth --yes "--$agent"; then
    ok "$label" "Installed. $next"
  else
    fail "$label" "Could not install Context7."
  fi
}

has_claude_code && ctx7_install "Claude Code" claude "Restart open sessions, then run /mcp once to sign in to Context7."
has_cursor && ctx7_install "Cursor" cursor "Sign in to Context7 when Cursor asks, or from Cursor Settings > MCP."
has_codex && ctx7_install "Codex" codex "Run 'codex mcp login context7' once to sign in."
has_copilot_cli && ctx7_install "Copilot CLI" copilot "Restart Copilot, then sign in to Context7 when it asks."

# The JetBrains plugin has no ctx7 target. Its MCP servers live in one mcp.json,
# so the Context7 entry is written there by key and a rerun overwrites it.
CONTEXT7_URL="https://mcp.context7.com/mcp"
if has_copilot_jetbrains; then
  mcp_json="$(copilot_jetbrains_dir)/mcp.json"
  if quietly jq_set_file "$mcp_json" '.servers.context7 = {type: "http", url: $url}' --arg url "$CONTEXT7_URL"; then
    ok "JetBrains" "Installed. Restart the IDE to load it."
  else
    fail "JetBrains" "Could not add Context7 to $mcp_json."
  fi
fi

finish
