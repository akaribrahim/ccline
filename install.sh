#!/usr/bin/env bash
# ccline installer — macOS / Linux / Git Bash (WSL).
#
#   curl -fsSL https://raw.githubusercontent.com/akaribrahim/ccline/main/install.sh | bash
#   # or from a clone:  bash install.sh [plain|bars|powerline]
#
# Idempotent. Backs up settings.json before touching it. Never deletes your
# old status line script — only repoints settings.json at ccline.
set -eu

REPO_RAW="https://raw.githubusercontent.com/akaribrahim/ccline/main"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CLAUDE_DIR/ccline.sh"
CONF="$CLAUDE_DIR/ccline.conf"
SETTINGS="$CLAUDE_DIR/settings.json"
STYLE="${1:-}"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

say ""
say "  ccline — Claude Code status line"
say "  ────────────────────────────────"
mkdir -p "$CLAUDE_DIR"

# 1) place the status line script (local clone first, else download) ---------
SRC=""
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/src/statusline.sh" ]; then
  SRC="$SELF_DIR/src/statusline.sh"
  cp "$SRC" "$DEST"
  ok "installed from clone -> $DEST"
else
  if ! command -v curl >/dev/null 2>&1; then
    warn "curl not found and no local clone — cannot fetch ccline.sh"; exit 1
  fi
  curl -fsSL "$REPO_RAW/src/statusline.sh" -o "$DEST"
  ok "downloaded -> $DEST"
fi
chmod +x "$DEST"

# 2) jq is required at runtime ----------------------------------------------
if command -v jq >/dev/null 2>&1; then
  ok "jq found"
else
  warn "jq not found — ccline needs it to parse Claude's JSON."
  warn "  macOS: brew install jq    Debian/Ubuntu: sudo apt-get install -y jq"
fi

# 3) optional style ----------------------------------------------------------
if [ -n "$STYLE" ]; then
  case "$STYLE" in
    plain|bars|powerline)
      if [ -f "$CONF" ] && grep -q '^[[:space:]]*CCLINE_STYLE[[:space:]]*=' "$CONF"; then
        tmp=$(mktemp); sed -E "s/^[[:space:]]*CCLINE_STYLE[[:space:]]*=.*/CCLINE_STYLE=$STYLE/" "$CONF" > "$tmp" && mv "$tmp" "$CONF"
      else
        printf 'CCLINE_STYLE=%s\n' "$STYLE" >> "$CONF"
      fi
      ok "style = $STYLE  (edit $CONF to change)" ;;
    *) warn "unknown style '$STYLE' (use plain|bars|powerline) — skipping" ;;
  esac
fi

# 4) point settings.json at ccline (with backup) -----------------------------
CMD="bash $DEST"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.ccline-bak"
  ok "backed up settings.json -> settings.json.ccline-bak"
fi

if command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  if [ -f "$SETTINGS" ]; then
    jq --arg c "$CMD" '.statusLine = {type:"command", command:$c}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  else
    printf '{\n  "statusLine": { "type": "command", "command": "%s" }\n}\n' "$CMD" > "$SETTINGS"
  fi
  ok "settings.json updated (jq)"
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS" "$CMD" <<'PY'
import json, os, sys
p, cmd = sys.argv[1], sys.argv[2]
d = {}
if os.path.exists(p):
    try: d = json.load(open(p))
    except Exception: d = {}
d["statusLine"] = {"type": "command", "command": cmd}
json.dump(d, open(p, "w"), indent=2)
PY
  ok "settings.json updated (python3)"
else
  warn "neither jq nor python3 found — add this to $SETTINGS yourself:"
  warn "  \"statusLine\": { \"type\": \"command\", \"command\": \"$CMD\" }"
fi

say ""
say "  Done. Open a new Claude Code session (or wait a tick) to see it."
say "  Config: $CONF   Styles: plain | bars | powerline"
say "  Uninstall: restore settings.json.ccline-bak, or run uninstall.sh"
say ""
