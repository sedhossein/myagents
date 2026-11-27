#!/usr/bin/env bash
# Installs or updates the third-party graphify skill (https://github.com/Graphify-Labs/graphify)
# with its documented `graphify install` command for each detected tool, and adds a short
# rule on when to use it. The graph itself is built per project, on demand, with
# /graphify in that project. Run by the root install.sh.
set -euo pipefail
# shellcheck source=../../scripts/install-lib.sh
source "$MYAGENTS_DIR/scripts/install-lib.sh"

need uv

RULE="$MYAGENTS_DIR/plugins/graphify/rule.md"

# The PyPI package is graphifyy (two y). A graphify the user installed another way is kept.
if ! command -v graphify &>/dev/null; then
  if ! quietly uv tool install graphifyy; then
    fail "graphify" "Could not install the graphify command with uv."
    finish
  fi
  PATH="$(uv tool dir --bin):$PATH"
  note "graphify" "Installed the command. If a new shell cannot find it, run: uv tool update-shell"
fi

# graphify keeps its own section in ~/.claude/CLAUDE.md and rewrites it on every run, so
# Claude Code gets the rule as its own file in ~/.claude/rules. The other tools get a marked
# block in their instructions file. Never overwrites a file the user wrote.
write_rule() {
  local file="$1"
  case "$file" in
    */.claude/rules/*)
      if [ -e "$file" ] && ! grep -qF "<!-- $MANAGED_MARK -->" "$file"; then return 0; fi
      mkdir -p "$(dirname "$file")"
      { cat "$RULE"; printf '\n<!-- %s -->\n' "$MANAGED_MARK"; } >"$file" ;;
    *) instructions_block install "$file" graphify "$RULE" ;;
  esac
}

# Installs the skill with graphify's own command, then writes the rule into the tool's
# global instructions file(s), if it has one that is read in every project.
graphify_host() {
  local label="$1" hint="$2" platform="$3"
  shift 3
  if ! quietly graphify install --platform "$platform"; then
    fail "$label" "Could not install the graphify skill."
    return 0
  fi
  local file
  for file in "$@"; do
    if ! quietly write_rule "$file"; then
      fail "$label" "Installed the skill, but could not write the graphify rule to $file."
      return 0
    fi
  done
  ok "$label" "Installed. $hint to load it."
}

has_claude_code && graphify_host "Claude Code" "Restart open sessions" claude "$HOME/.claude/rules/graphify.md"
# The Cursor agent, including the one in JetBrains AI chat, reads ~/.agents/skills but has
# no global rules file, so it relies on the skill's own description to pick it up.
has_cursor && graphify_host "Cursor" "Start a new chat" agents
has_codex && graphify_host "Codex" "Restart Codex" codex "${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
if has_copilot; then
  files=()
  has_copilot_cli && files+=("${COPILOT_HOME:-$HOME/.copilot}/copilot-instructions.md")
  has_copilot_jetbrains && files+=("$(copilot_jetbrains_dir)/global-copilot-instructions.md")
  graphify_host "Copilot" "Start a new Copilot chat" copilot ${files[@]+"${files[@]}"}
fi
has_opencode && graphify_host "OpenCode" "Start a new session" opencode "$(opencode_dir)/AGENTS.md"

# The graph lives in each project, so keep it out of commits by default.
if ignore_file="$(git config --global --get core.excludesFile 2>/dev/null)" && [ -n "$ignore_file" ]; then
  ignore_file="${ignore_file/#\~/$HOME}"
else
  ignore_file="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
fi
if grep -qxF "graphify-out/" "$ignore_file" 2>/dev/null; then
  ok "Git" "graphify-out/ is already ignored in $ignore_file."
elif mkdir -p "$(dirname "$ignore_file")" && printf '\n# myagents: graphify\ngraphify-out/\n' >>"$ignore_file"; then
  ok "Git" "Ignores graphify-out/ in every repository ($ignore_file)."
else
  fail "Git" "Could not add graphify-out/ to $ignore_file."
fi

finish
