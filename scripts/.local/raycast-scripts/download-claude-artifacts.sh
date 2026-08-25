#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Download Claude artifacts
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🧩
# @raycast.packageName Claude
# @raycast.argument1 { "type": "dropdown", "placeholder": "Source", "data": [{ "title": "Claude Code", "value": "code" }, { "title": "Claude Desktop", "value": "desktop" }] }
# @raycast.argument2 { "type": "dropdown", "placeholder": "Which", "optional": true, "data": [{ "title": "Latest", "value": "latest" }, { "title": "Pick from list…", "value": "pick" }, { "title": "Everything", "value": "all" }] }

# Documentation:
# @raycast.author Arhun Saday
# @raycast.description Download the artifacts Claude built — published Claude Code artifacts, or the files and artifacts of a Claude Desktop chat — to ~/Downloads. Copies the path to the clipboard.

set -euo pipefail

args=("${1}")
case "${2:-latest}" in
  pick) args+=(--pick) ;;
  all) args+=(--all) ;;
esac

exec "$HOME/.local/bin/claude-export" --artifacts "${args[@]}"
