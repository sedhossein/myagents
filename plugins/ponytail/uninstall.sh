#!/usr/bin/env bash
# Removes the third-party ponytail plugin. Run by the root uninstall.sh.
set -euo pipefail
# shellcheck source=../../scripts/install-lib.sh
source "$MYAGENTS_DIR/scripts/install-lib.sh"

CHECKOUT_DIR="$MYAGENTS_DIR/plugins/ponytail/checkout"

# ponytail's own cleanup script removes what the host uninstall commands leave
# behind: its Cursor hooks, mode flags, config file, and statusline entry. It
# ships inside the plugin, so it runs before the plugin files are removed.
cleanup=""
for candidate in "$CHECKOUT_DIR" "$HOME"/.claude/plugins/cache/ponytail/ponytail/* "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/ponytail/ponytail/*; do
  [ -f "$candidate/scripts/uninstall.js" ] && cleanup="$candidate/scripts/uninstall.js"
done

cleanup_result="absent"
if [ -n "$cleanup" ]; then
  if ! command -v node &>/dev/null; then
    cleanup_result="no-node"
  elif quietly node "$cleanup"; then
    cleanup_result="removed"
  else
    fail "Cleanup" "Could not remove ponytail's settings and Cursor hooks."
    cleanup_result="failed"
  fi
fi

has_claude_code && claude_marketplace_plugin_remove ponytail ponytail
has_codex && codex_marketplace_plugin_remove ponytail ponytail
has_copilot_cli && copilot_marketplace_plugin_remove ponytail ponytail

# Reported last to match the platform order of install.sh.
case "$cleanup_result" in
  no-node) note "Cleanup" "node is not installed, so ponytail's settings and Cursor hooks were left in place. Install node and rerun to remove them." ;;
  removed) has_cursor && ok "Cursor" "Removed. Start a new chat to unload it." ;;
  absent) has_cursor && ok "Cursor" "Already removed." ;;
esac

if has_opencode; then
  oc_names=()
  for dir in "$CHECKOUT_DIR"/skills/*/; do [ -f "$dir/SKILL.md" ] && oc_names+=("$(basename "$dir")"); done
  oc_left=false
  for name in ${oc_names[@]+"${oc_names[@]}"}; do [ -L "$(opencode_dir)/skills/$name" ] && oc_left=true; done
  unlink_skills "$(opencode_dir)/skills" ${oc_names[@]+"${oc_names[@]}"}
  if [ "$oc_left" = true ]; then
    ok "OpenCode" "Removed. Start a new session to unload it."
  else
    ok "OpenCode" "Already removed."
  fi
fi

rm -rf "$CHECKOUT_DIR"

finish
