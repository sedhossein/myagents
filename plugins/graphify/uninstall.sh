#!/usr/bin/env bash
# Removes the graphify rule and skill. The graphify command and each project's graphify-out/
# folder belong to the user and are kept. Run by the root uninstall.sh.
set -euo pipefail
# shellcheck source=../../scripts/install-lib.sh
source "$MYAGENTS_DIR/scripts/install-lib.sh"

# Removes the rule from one tool's instructions file(s); sets rule_changed when any had it.
rule_changed=false
drop_rule() {
  local file
  for file in "$@"; do
    [ -f "$file" ] || continue
    case "$file" in
      */.claude/rules/*)
        if grep -qF "<!-- $MANAGED_MARK -->" "$file"; then rm -f "$file"; rule_changed=true; fi ;;
      *)
        quietly instructions_block uninstall "$file" graphify || return 1
        [ "$quiet_output" = "changed" ] && rule_changed=true ;;
    esac
  done
  return 0
}

has_graphify=false
command -v graphify &>/dev/null && has_graphify=true

# graphify's own uninstall removes its skill from every tool at once and leaves the
# user's other files alone, so it runs once, after the rules are gone.
host_report() {
  local label="$1" hint="$2" present="$3"
  shift 3
  rule_changed=false
  if ! drop_rule "$@"; then
    fail "$label" "Could not remove the graphify rule."
  elif [ "$rule_changed" = true ] || eval "$present" &>/dev/null; then
    ok "$label" "Removed. $hint to unload it."
  else
    ok "$label" "Already removed."
  fi
}

# $3 succeeds while the tool still has graphify's skill.
has_claude_code && host_report "Claude Code" "Restart open sessions" '[ -f "$HOME/.claude/skills/graphify/SKILL.md" ]' "$HOME/.claude/rules/graphify.md"
has_cursor && host_report "Cursor" "Start a new chat" '[ -f "$HOME/.agents/skills/graphify/SKILL.md" ]'
has_codex && host_report "Codex" "Restart Codex" '[ -f "${CODEX_HOME:-$HOME/.codex}/skills/graphify/SKILL.md" ]' "${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
if has_copilot; then
  files=()
  has_copilot_cli && files+=("${COPILOT_HOME:-$HOME/.copilot}/copilot-instructions.md")
  has_copilot_jetbrains && files+=("$(copilot_jetbrains_dir)/global-copilot-instructions.md")
  host_report "Copilot" "Start a new Copilot chat" '[ -f "${COPILOT_HOME:-$HOME/.copilot}/skills/graphify/SKILL.md" ]' ${files[@]+"${files[@]}"}
fi
has_opencode && host_report "OpenCode" "Start a new session" '[ -f "$(opencode_dir)/skills/graphify/SKILL.md" ]' "$(opencode_dir)/AGENTS.md"

if [ "$has_graphify" = true ] && ! quietly graphify uninstall; then
  fail "graphify" "Could not remove the graphify skill."
fi

ignore_file="$(git config --global --get core.excludesFile 2>/dev/null || true)"
if [ -n "$ignore_file" ]; then ignore_file="${ignore_file/#\~/$HOME}"; else ignore_file="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"; fi
if grep -qxF "# myagents: graphify" "$ignore_file" 2>/dev/null; then
  tmp="$(mktemp)"
  grep -vxF -e "# myagents: graphify" -e "graphify-out/" "$ignore_file" >"$tmp" || true
  if [ -s "$tmp" ]; then cp "$tmp" "$ignore_file"; else rm -f "$ignore_file"; fi
  rm -f "$tmp"
  ok "Git" "Stopped ignoring graphify-out/."
else
  ok "Git" "Already removed."
fi

finish
