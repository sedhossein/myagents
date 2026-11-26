#!/usr/bin/env bash
# Shared helpers for install.sh, uninstall.sh, and the plugins/<name>/ scripts of
# the same names. Source it, do not run it. Every helper is safe to run again:
# an install rerun updates instead of duplicating anything, and an uninstall
# rerun reports "Already removed." instead of failing.

MYAGENTS_DIR="${MYAGENTS_DIR:-$HOME/.myagents}"
MYAGENTS_MARKETPLACE="${MYAGENTS_MARKETPLACE:-myagents}"

if [ -t 1 ]; then
  _bold=$'\033[1m' _dim=$'\033[2m' _green=$'\033[32m' _red=$'\033[31m' _yellow=$'\033[33m' _reset=$'\033[0m'
else
  _bold="" _dim="" _green="" _red="" _yellow="" _reset=""
fi

_failed=0
_output=""

# Output. Every line is "<icon> <label> <message>" with the label in a fixed
# column, so all plugins print the same shape.

section() { printf '\n%s%s%s\n' "$_bold" "$1" "$_reset"; }
ok() { printf '  %s✓%s %-15s %s\n' "$_green" "$_reset" "$1" "$2"; }
note() { printf '  %s!%s %-15s %s\n' "$_yellow" "$_reset" "$1" "$2"; }

# Prints the failure and the tail of the last quietly-run command's output.
fail() {
  printf '  %s✗%s %-15s %s\n' "$_red" "$_reset" "$1" "$2"
  if [ -n "$_output" ]; then
    printf '%s\n' "$_output" | tail -n 5 | sed "s/^/      ${_dim}/;s/\$/${_reset}/"
    _output=""
  fi
  _failed=1
}

# Runs a command with its output hidden. On success the output is left in
# quiet_output for the caller; on failure it is kept for fail.
quiet_output=""
quietly() {
  if quiet_output="$("$@" 2>&1)"; then
    _output=""
    return 0
  fi
  _output="$quiet_output"
  return 1
}

# Exits with status 1 if any step failed. Call it last in a plugin script.
finish() { exit "$_failed"; }

# Platform detection. Claude Code counts as present without the CLI on PATH,
# since the VS Code extension and the desktop app ship their own copy.

has_claude_code() { command -v claude &>/dev/null || [ -d "$HOME/.claude" ]; }
has_cursor() { [ -d "$HOME/.cursor" ]; }
has_codex() { command -v codex &>/dev/null; }
has_copilot_cli() { command -v copilot &>/dev/null || [ -d "${COPILOT_HOME:-$HOME/.copilot}" ]; }

# Copilot's JetBrains plugin keeps its MCP servers and global instructions in
# one user-level folder, which an absolute XDG_CONFIG_HOME moves (without the
# intellij folder). The plugin creates it on sign-in, so it also marks it as installed.
copilot_jetbrains_dir() {
  case "${XDG_CONFIG_HOME:-}" in
    /*) echo "$XDG_CONFIG_HOME/github-copilot" ;;
    *) echo "$HOME/.config/github-copilot/intellij" ;;
  esac
}
has_copilot_jetbrains() { [ -d "$(copilot_jetbrains_dir)" ]; }
has_copilot() { has_copilot_cli || has_copilot_jetbrains; }

# Copilot CLI, its JetBrains plugin, and the Copilot agent in JetBrains AI chat all
# read personal skills from this folder, not from ~/.agents/skills.
copilot_skills_dir() { echo "${COPILOT_HOME:-$HOME/.copilot}/skills"; }

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

# Exits the plugin script with an install hint when a required tool is missing.
need() {
  if ! command -v "$1" &>/dev/null; then
    fail "Requirements" "$1 is not installed. Install it with: brew install ${2:-$1}"
    finish
  fi
}

# Brings a shallow checkout to the latest commit of the repo's default branch,
# cloning it on the first run. Same steps as the root install.sh uses for
# ~/.myagents: local edits are discarded so a rerun never fails on them.
sync_checkout() {
  local url="$1" dir="$2"
  mkdir -p "$dir" \
    && git -C "$dir" init --quiet \
    && { git -C "$dir" remote set-url origin "$url" 2>/dev/null \
      || git -C "$dir" remote add origin "$url"; } \
    && git -C "$dir" fetch --quiet --depth 1 origin HEAD \
    && git -C "$dir" reset --quiet --hard FETCH_HEAD
}

# Points a symlink at a directory. -n replaces an existing link to a directory
# instead of creating a second link inside it.
link_dir() {
  mkdir -p "$(dirname "$2")" && ln -sfn "$1" "$2"
}

# Installs or updates a plugin from a Claude Code marketplace hosted in a git repo.
claude_marketplace_plugin() {
  local url="$1" marketplace="$2" plugin="$3" id="$3@$2"
  if ! command -v claude &>/dev/null; then
    note "Claude Code" "The claude command is not on your PATH. In Claude Code, run: /plugin marketplace add $url, then /plugin install $id"
    return 0
  fi
  if quietly claude plugin marketplace add "$url" \
    && quietly claude plugin marketplace update "$marketplace" \
    && quietly claude plugin install "$id" --scope user \
    && quietly claude plugin update "$id" --scope user; then
    ok "Claude Code" "Installed. Restart open sessions to load it."
  else
    fail "Claude Code" "Could not install $plugin."
  fi
}

# Installs or updates a plugin from a Codex marketplace hosted in a git repo.
codex_marketplace_plugin() {
  local url="$1" marketplace="$2" plugin="$3" id="$3@$2"
  if quietly codex plugin marketplace add "$url" \
    && quietly codex plugin marketplace upgrade "$marketplace" \
    && quietly codex plugin add "$id"; then
    ok "Codex" "Installed. Restart Codex, then run /hooks once to trust its hooks."
  else
    fail "Codex" "Could not install $plugin."
  fi
}

# Checks whether a JSON array on stdin has an object whose <key> equals <value>.
_json_list_has() {
  python3 -c 'import json, sys; k, v = sys.argv[1:3]; sys.exit(0 if any(x.get(k) == v for x in json.load(sys.stdin)) else 1)' "$1" "$2"
}

# Removes a plugin and its marketplace from Claude Code. Each removal runs only
# when Claude Code still lists the item, since removing a missing one fails.
claude_marketplace_plugin_remove() {
  local marketplace="$1" plugin="$2" id="$2@$1" removed=false
  if ! command -v claude &>/dev/null; then
    note "Claude Code" "The claude command is not on your PATH. In Claude Code, run: /plugin uninstall $id, then /plugin marketplace remove $marketplace"
    return 0
  fi
  if claude plugin list --json 2>/dev/null | _json_list_has id "$id"; then
    quietly claude plugin uninstall "$id" --scope user || { fail "Claude Code" "Could not remove $plugin."; return 0; }
    removed=true
  fi
  if claude plugin marketplace list --json 2>/dev/null | _json_list_has name "$marketplace"; then
    quietly claude plugin marketplace remove "$marketplace" || { fail "Claude Code" "Could not remove the $marketplace marketplace."; return 0; }
    removed=true
  fi
  if [ "$removed" = true ]; then
    ok "Claude Code" "Removed. Restart open sessions to unload it."
  else
    ok "Claude Code" "Already removed."
  fi
}

codex_has_marketplace() {
  codex plugin marketplace list 2>/dev/null | awk -v m="$1" '$1 == m { found = 1 } END { exit !found }'
}

# Removes a plugin and its marketplace from Codex. Removing a plugin that is not
# installed succeeds, but removing a missing marketplace fails, so it is checked.
codex_marketplace_plugin_remove() {
  local marketplace="$1" plugin="$2" id="$2@$1"
  if ! codex_has_marketplace "$marketplace"; then
    ok "Codex" "Already removed."
  elif quietly codex plugin remove "$id" && quietly codex plugin marketplace remove "$marketplace"; then
    ok "Codex" "Removed. Restart Codex to unload it."
  else
    fail "Codex" "Could not remove $plugin."
  fi
}

# Skills CLI (https://skills.sh) agent ids for the detected tools, with the label
# and reload hint each status line uses.
_skills_cli_agents() {
  has_claude_code && echo "claude-code|Claude Code|Restart open sessions"
  has_cursor && echo "cursor|Cursor|Start a new chat"
  has_codex && echo "codex|Codex|Restart Codex"
  # Copilot CLI and the JetBrains plugin both read skills from ~/.agents/skills.
  { has_copilot_cli || has_copilot_jetbrains; } && echo "github-copilot|Copilot|Restart Copilot"
  return 0
}

# Prints one status line per detected tool: "<verb>." alone, or followed by
# "<hint> to <action> it." when an action is given.
_skills_cli_report() {
  local verb="$1" action="${2:-}" id label hint
  while IFS='|' read -r id label hint; do
    [ -z "$id" ] && continue
    if [ -n "$action" ]; then
      ok "$label" "$verb. $hint to $action it."
    else
      ok "$label" "$verb."
    fi
  done < <(_skills_cli_agents)
}

_skills_cli() {
  DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 npx -y skills@latest "$@"
}

# Runs `skills add` for every detected tool, reporting failure under <name>.
_skills_cli_add() {
  local name="$1" agents=()
  shift
  while IFS='|' read -r id _; do [ -n "$id" ] && agents+=("$id"); done < <(_skills_cli_agents)
  [ ${#agents[@]} -eq 0 ] && return 0
  if ! command -v npx &>/dev/null; then
    fail "Requirements" "node is not installed, so $name was skipped. Install it with: brew install node"
  elif quietly _skills_cli add "$@" --global --agent "${agents[@]}" -y; then
    _skills_cli_report "Installed" "load"
  else
    fail "Skills" "Could not install $name."
  fi
}

# Runs `skills remove` for the given skills, reporting failure under <name>.
_skills_cli_remove() {
  local name="$1"
  shift
  if ! command -v npx &>/dev/null; then
    fail "Requirements" "node is not installed, so $name could not be removed. Install it with: brew install node"
  elif quietly _skills_cli remove "$@" --global -y; then
    has_copilot && unlink_skills "$(copilot_skills_dir)" "$@"
    _skills_cli_report "Removed" "unload"
  else
    fail "Skills" "Could not remove $name."
  fi
}

# Installs or updates a skill with the Skills CLI for every detected tool. The
# CLI keeps the skill in ~/.agents/skills, which Cursor and Codex read, and links
# it into ~/.claude/skills for Claude Code. Extra arguments are passed to
# `skills add`, for flags a skill's own install command uses, such as --copy.
# Rerunning reinstalls the latest version. Install telemetry is turned off.
skills_cli_skill() {
  local url="$1" skill="$2"
  shift 2
  _skills_cli_add "$skill" "$url" --skill "$skill" "$@"
  _skills_cli_link "$url"
}

# Removes a skill the Skills CLI installed, from every tool.
skills_cli_skill_remove() {
  local skill="$1"
  # -L also catches a Claude Code link whose target is already gone.
  if [ ! -e "$HOME/.agents/skills/$skill" ] && [ ! -e "$HOME/.claude/skills/$skill" ] \
    && [ ! -L "$HOME/.claude/skills/$skill" ]; then
    has_copilot && unlink_skills "$(copilot_skills_dir)" "$skill"
    _skills_cli_report "Already removed"
  else
    _skills_cli_remove "$skill" "$skill"
  fi
}

# Installs or updates every skill in a GitHub repository with the Skills CLI,
# the same way as skills_cli_skill. Skills the repository adds later come in on
# the next run.
skills_cli_repo() {
  local url="$1"
  shift
  _skills_cli_add "$(_skills_cli_source "$url")" "$url" --skill '*' "$@"
  _skills_cli_link "$url"
}

# Removes every skill the Skills CLI installed from a GitHub repository. The
# CLI's lock file records each skill's source, so skills from other
# repositories are left alone.
skills_cli_repo_remove() {
  local source skills=()
  source="$(_skills_cli_source "$1")"
  while IFS= read -r skill; do [ -n "$skill" ] && skills+=("$skill"); done < <(
    jq -r --arg source "$source" \
      '.skills // {} | to_entries[] | select(.value.source == $source) | .key' \
      "$HOME/.agents/.skill-lock.json" 2>/dev/null
  )
  if [ ${#skills[@]} -eq 0 ]; then
    _skills_cli_report "Already removed"
  else
    _skills_cli_remove "$source" "${skills[@]}"
  fi
}

# Links the skills the Skills CLI installed from a repository into the folder
# Copilot reads. The lock file records each skill's source.
_skills_cli_link() {
  has_copilot || return 0
  local source name names=()
  source="$(_skills_cli_source "$1")"
  while IFS= read -r name; do [ -n "$name" ] && names+=("$HOME/.agents/skills/$name"); done < <(
    jq -r --arg source "$source" \
      '.skills // {} | to_entries[] | select(.value.source == $source) | .key' \
      "$HOME/.agents/.skill-lock.json" 2>/dev/null
  )
  [ ${#names[@]} -eq 0 ] && return 0
  quietly link_skills "$(copilot_skills_dir)" "${names[@]}" \
    || fail "Copilot" "Could not link the skills into $(copilot_skills_dir)."
}

# Turns a GitHub URL into the owner/repo form the Skills CLI records as source.
_skills_cli_source() {
  local source="${1#https://github.com/}"
  source="${source%/}"
  echo "${source%.git}"
}

_homebrew_bin() {
  local bin
  for bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$bin" ] && echo "$bin" && return 0
  done
  return 1
}

# Makes brew available, installing Homebrew first when it is missing (its
# installer may ask for your password). Also adds Homebrew to PATH for new
# shells, as its installer asks you to, so the apps find what it installs.
ensure_homebrew() {
  command -v brew &>/dev/null && return 0
  local bin profile line
  if ! bin="$(_homebrew_bin)"; then
    note "Homebrew" "Installing Homebrew to install the missing tools. It may ask for your password."
    if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty \
      || ! bin="$(_homebrew_bin)"; then
      fail "Homebrew" "Could not install Homebrew. Install it from https://brew.sh, then rerun."
      return 1
    fi
    ok "Homebrew" "Installed."
  fi
  eval "$("$bin" shellenv)"

  profile="$HOME/.zprofile"
  [ "$(basename "${SHELL:-zsh}")" = "bash" ] && profile="$HOME/.bash_profile"
  line="eval \"\$($bin shellenv)\""
  if ! grep -qF "$line" "$profile" 2>/dev/null; then
    printf '\n%s\n' "$line" >>"$profile"
    ok "Homebrew" "Added to PATH in ~/${profile##*/}."
  fi
}
