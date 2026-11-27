#!/usr/bin/env bash
set -euo pipefail

# OpenCode reads agents from Markdown files in ~/.config/opencode/agents and cannot
# load them from a plugin, so the Markdown files in agents/ stay the single source
# of truth and this script projects them into that format: the description, a
# subagent mode, and read-only permissions for the agents marked readonly. Each
# file ends with a myagents marker, so a rerun refreshes it and a file the user
# wrote is never touched.
#
# Usage: gen-opencode-agents.sh install|uninstall <output-dir>

if [ $# -ne 2 ]; then
  echo "Usage: gen-opencode-agents.sh install|uninstall <output-dir>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - "$SCRIPT_DIR/../agents" "$@" <<'PY'
import json
import pathlib
import sys

agents_dir, action, out_dir = sys.argv[1:4]
out = pathlib.Path(out_dir)
MARKER = "<!-- managed by myagents -->"


def parse(path):
    text = path.read_text()
    end = text.find("\n---\n", 3) if text.startswith("---\n") else -1
    if end == -1:
        sys.exit(f"{path.name} has no frontmatter.")
    meta = {}
    for line in text[4:end].splitlines():
        if ": " in line:
            key, value = line.split(": ", 1)
            meta[key.strip()] = value.strip().strip("'\"")
    return meta, text[end + 5 :].strip()


def ours(path):
    return path.exists() and MARKER in path.read_text()


changed = 0
for path in sorted(pathlib.Path(agents_dir).glob("*.md")):
    meta, body = parse(path)
    name = meta.get("name")
    if not name or not meta.get("description") or not body:
        sys.exit(f"{path.name} has no name, description, or body.")
    target = out / f"{name}.md"
    if action == "uninstall":
        if ours(target):
            target.unlink()
            changed += 1
        continue
    if target.exists() and not ours(target):
        continue
    head = ["---", f"description: {json.dumps(meta['description'])}", "mode: subagent"]
    if meta.get("readonly", "").lower() == "true":
        head += [
            "permissions:",
            '  - {action: edit, resource: "*", effect: deny}',
            '  - {action: shell, resource: "*", effect: deny}',
        ]
    head.append("---")
    text = "\n".join(head) + "\n\n" + body + "\n\n" + MARKER + "\n"
    out.mkdir(parents=True, exist_ok=True)
    if not target.exists() or target.read_text() != text:
        target.write_text(text)
        changed += 1
print(f"{action}: {changed} changed", file=sys.stderr)
PY
