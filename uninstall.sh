#!/usr/bin/env bash
# ccline uninstaller — macOS / Linux / Git Bash.
#   bash uninstall.sh
# Restores settings.json from the backup ccline made, or strips the
# statusLine key if there is no backup. Removes ccline.sh / ccline.conf.
set -eu

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

if [ -f "$SETTINGS.ccline-bak" ]; then
  mv "$SETTINGS.ccline-bak" "$SETTINGS"
  ok "restored settings.json from backup"
elif [ -f "$SETTINGS" ]; then
  if command -v jq >/dev/null 2>&1; then
    tmp=$(mktemp); jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$SETTINGS" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d.pop("statusLine",None); json.dump(d,open(p,"w"),indent=2)
PY
  fi
  ok "removed statusLine from settings.json"
fi

rm -f "$CLAUDE_DIR/ccline.sh" "$CLAUDE_DIR/ccline.conf"
ok "removed ccline.sh and ccline.conf"
printf '  ccline uninstalled.\n'
