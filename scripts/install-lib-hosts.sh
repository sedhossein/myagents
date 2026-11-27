#!/usr/bin/env bash
# Helpers for hosts that read skills, instructions, and MCP servers from folders:
# Copilot (CLI, the JetBrains plugin, and the Copilot agent in JetBrains AI chat),
# and the Cursor agent when it runs outside the Cursor app. Sourced at the end of
# install-lib.sh, so plugin scripts only source that one file.

# Copilot CLI, its JetBrains plugin, and the Copilot agent in JetBrains AI chat all
# read personal skills from this folder, not from ~/.agents/skills.
copilot_skills_dir() { echo "${COPILOT_HOME:-$HOME/.copilot}/skills"; }

# OpenCode reads personal skills, agents, and instructions (AGENTS.md) from one
# folder, and its MCP servers from the opencode.jsonc inside it.
opencode_dir() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/opencode"; }
has_opencode() { command -v opencode &>/dev/null || [ -d "$(opencode_dir)" ]; }

# Rewrites a JSON file with a jq filter (extra arguments go to jq), creating it
# as {} first. Never leaves a half-written file behind.
jq_set_file() {
  local file="$1" filter="$2" tmp
  shift 2
  need jq
  mkdir -p "$(dirname "$file")"
  [ -s "$file" ] || echo '{}' >"$file"
  tmp="$(mktemp "$file.XXXXXX")"
  if jq "$@" "$filter" "$file" >"$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Symlinks each skill folder given into <dest>, for tools that read only <dest>.
# A name that already exists there and is not a stale link of ours is the user's
# own, so it is left alone.
link_skills() {
  local dest="$1" src name
  shift
  mkdir -p "$dest"
  for src in "$@"; do
    src="${src%/}"
    name="$(basename "$src")"
    [ -f "$src/SKILL.md" ] || continue
    if [ -L "$dest/$name" ] && [ ! -e "$dest/$name" ]; then rm -f "$dest/$name"; fi
    [ -e "$dest/$name" ] || [ -L "$dest/$name" ] || ln -s "$src" "$dest/$name"
  done
}

# Cursor skips symlinked skill and agent folders when it runs inside another host,
# such as the JetBrains AI chat, which also does not load Cursor plugins. So a
# plugin's skills and agents are copied into ~/.cursor, and each copy is marked as
# ours, so a rerun refreshes it and an item the user wrote is never overwritten.
MANAGED_MARK="managed by myagents"

# copy_skills <dest> <skill dir>...: one folder per skill, with a marker file inside.
copy_skills() {
  local dest="$1" src name
  shift
  mkdir -p "$dest"
  for src in "$@"; do
    src="${src%/}"
    name="$(basename "$src")"
    [ -f "$src/SKILL.md" ] || continue
    if [ -e "$dest/$name" ] && [ ! -f "$dest/$name/.myagents" ]; then continue; fi
    rm -rf "${dest:?}/$name"
    cp -R "$src" "$dest/$name"
    echo "$MANAGED_MARK" >"$dest/$name/.myagents"
  done
}

# copy_agents <dest> <agent file>...: each file gets a marker comment at the end.
copy_agents() {
  local dest="$1" src target
  shift
  mkdir -p "$dest"
  for src in "$@"; do
    [ -f "$src" ] || continue
    target="$dest/$(basename "$src")"
    if [ -e "$target" ] && ! grep -qF "<!-- $MANAGED_MARK -->" "$target"; then continue; fi
    { cat "$src"; printf '\n<!-- %s -->\n' "$MANAGED_MARK"; } >"$target"
  done
}

# Remove only the copies the two functions above marked, by name.
remove_copied_skills() {
  local dest="$1" name
  shift
  for name in "$@"; do
    [ -f "$dest/$name/.myagents" ] && rm -rf "${dest:?}/$name"
  done
  return 0
}
remove_copied_agents() {
  local dest="$1" name
  shift
  for name in "$@"; do
    if grep -qF "<!-- $MANAGED_MARK -->" "$dest/$name.md" 2>/dev/null; then rm -f "$dest/$name.md"; fi
  done
  return 0
}

# Removes the links link_skills made for the named skills, and only links that
# point into a folder myagents installs skills to.
unlink_skills() {
  local dest="$1" name target
  shift
  for name in "$@"; do
    [ -L "$dest/$name" ] || continue
    target="$(readlink "$dest/$name")"
    case "$target" in
      "$HOME/.agents/skills/"* | "$HOME/.cursor/skills/"* | "$MYAGENTS_DIR/"*) rm -f "$dest/$name" ;;
    esac
  done
  return 0
}

# Copilot CLI plugin marketplaces. The JetBrains plugin and the Copilot agent in
# JetBrains AI chat load the plugins installed here too.
copilot_has_marketplace() { copilot plugin marketplace list 2>/dev/null | grep -qE "^[[:space:]]*•[[:space:]]+$1 \("; }
copilot_has_plugin() { copilot plugin list 2>/dev/null | grep -qE "•[[:space:]]+$1@"; }

# Installs or updates a plugin from a Copilot CLI marketplace: a GitHub URL, or a
# local folder. Adding a marketplace twice fails, so a rerun updates it instead.
copilot_marketplace_plugin() {
  local source="$1" marketplace="$2" plugin="$3"
  if ! command -v copilot &>/dev/null; then
    note "Copilot CLI" "The copilot command is not on your PATH. In Copilot CLI, run: /plugin marketplace add $source, then /plugin install $plugin@$marketplace"
    return 0
  fi
  if { if copilot_has_marketplace "$marketplace"; then
    quietly copilot plugin marketplace update "$marketplace"
  else
    quietly copilot plugin marketplace add "$source"
  fi; } && quietly copilot plugin install "$plugin@$marketplace"; then
    ok "Copilot CLI" "Installed. Restart Copilot to load it."
  else
    fail "Copilot CLI" "Could not install $plugin."
  fi
}

# Removes a plugin and its marketplace; reports "Already removed." when neither exists.
copilot_marketplace_plugin_remove() {
  local marketplace="$1" plugin="$2" removed=false
  if ! command -v copilot &>/dev/null; then
    note "Copilot CLI" "The copilot command is not on your PATH. In Copilot CLI, run: /plugin uninstall $plugin, then /plugin marketplace remove $marketplace"
    return 0
  fi
  if copilot_has_plugin "$plugin"; then
    quietly copilot plugin uninstall "$plugin" || { fail "Copilot CLI" "Could not remove $plugin."; return 0; }
    removed=true
  fi
  if copilot_has_marketplace "$marketplace"; then
    quietly copilot plugin marketplace remove "$marketplace" || { fail "Copilot CLI" "Could not remove the $marketplace marketplace."; return 0; }
    removed=true
  fi
  if [ "$removed" = true ]; then
    ok "Copilot CLI" "Removed. Restart Copilot to unload it."
  else
    ok "Copilot CLI" "Already removed."
  fi
}

# Writes or removes one named block of text in an instructions file, between
# myagents markers, never touching text outside them. The text comes from a file
# whose frontmatter, if any, is dropped. Prints "changed" or "unchanged".
#   instructions_block install <file> <name> <text file>
#   instructions_block uninstall <file> <name>
instructions_block() {
  python3 - "$@" <<'PY'
import os, pathlib, re, sys

action, target, name = sys.argv[1:4]
target = pathlib.Path(target)
begin = f"<!-- myagents:{name}:begin (written by the myagents installer; edits are overwritten) -->"
end = f"<!-- myagents:{name}:end -->"
block = re.compile(r"<!-- myagents:%s:begin[^\n]*\n.*?<!-- myagents:%s:end -->\n?" % (re.escape(name), re.escape(name)), re.S)

current = target.read_text() if target.exists() else ""
match = block.search(current)
rest = current
if match:
    before = current[: match.start()].rstrip("\n")
    after = current[match.end():].lstrip("\n")
    rest = before + ("\n\n" if before and after else "") + after
    if before and not after:
        rest += "\n"
new = rest if match else current
if action == "install":
    text = pathlib.Path(sys.argv[4]).read_text()
    if text.startswith("---\n"):
        text = text[text.find("\n---\n", 3) + 5:]
    new = (rest.rstrip("\n") + "\n\n" if rest.strip() else "") + begin + "\n\n" + text.strip() + "\n\n" + end + "\n"
if new != current:
    if new.strip():
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_name(target.name + ".tmp")
        tmp.write_text(new)
        os.replace(tmp, target)
    else:
        target.unlink()
    print("changed")
else:
    print("unchanged")
PY
}
