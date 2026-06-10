#!/bin/sh
# ccline — a capability-aware status line for Claude Code.
# https://github.com/akaribrahim/ccline
#
# Reads Claude Code's status JSON on stdin and prints one styled line.
# Adapts to terminal color depth (truecolor / 256 / 16) and glyph support.
#
# Config: env vars override ~/.claude/ccline.conf (KEY=value lines).
#   CCLINE_STYLE   plain | bars | powerline      (default: plain)
#   CCLINE_COLOR   auto | truecolor | 256 | 16    (default: auto)
#   CCLINE_ASCII   auto | 1 | 0                   (default: auto)
#   CCLINE_WARN/HIGH/CRIT   percentage thresholds (default: 50/75/90)
#
# Requires: jq

input=$(cat)

# ---------------------------------------------------------------- config ----
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONF="${CCLINE_CONFIG:-$CLAUDE_DIR/ccline.conf}"
conf_get() {
  _k=$1; _d=$2
  if [ -f "$CONF" ]; then
    _v=$(sed -n -E "s/^[[:space:]]*$_k[[:space:]]*=[[:space:]]*//p" "$CONF" 2>/dev/null \
         | tail -1 | sed -E 's/[[:space:]]*$//; s/^"(.*)"$/\1/')
    [ -n "$_v" ] && { printf '%s' "$_v"; return; }
  fi
  printf '%s' "$_d"
}
STYLE="${CCLINE_STYLE:-$(conf_get CCLINE_STYLE plain)}"
FORCE_COLOR="${CCLINE_COLOR:-$(conf_get CCLINE_COLOR auto)}"
FORCE_ASCII="${CCLINE_ASCII:-$(conf_get CCLINE_ASCII auto)}"
WARN="${CCLINE_WARN:-$(conf_get CCLINE_WARN 50)}"
HIGH="${CCLINE_HIGH:-$(conf_get CCLINE_HIGH 75)}"
CRIT="${CCLINE_CRIT:-$(conf_get CCLINE_CRIT 90)}"

# ---------------------------------------------------- capability detection --
case "$FORCE_COLOR" in
  truecolor|256|16) DEPTH=$FORCE_COLOR ;;
  *)
    if [ "${COLORTERM:-}" = "truecolor" ] || [ "${COLORTERM:-}" = "24bit" ]; then
      DEPTH=truecolor
    elif [ -n "${WT_SESSION:-}" ]; then        # Windows Terminal
      DEPTH=truecolor
    else
      case "${TERM_PROGRAM:-}" in
        iTerm.app|WezTerm|vscode|ghostty|Hyper|rio|Tabby) DEPTH=truecolor ;;
        Apple_Terminal) DEPTH=256 ;;           # Terminal.app: 256-color only
        *)
          case "${TERM:-}" in
            *256color*|*256col*) DEPTH=256 ;;
            *) DEPTH=16 ;;
          esac ;;
      esac
    fi ;;
esac

case "$FORCE_ASCII" in
  1|true|yes|on)   ASCII=1 ;;
  0|false|no|off)  ASCII=0 ;;
  *)               ASCII=0 ;;   # auto: *nix assumed unicode-capable
esac

# ------------------------------------------------------------------ palette --
if [ "$DEPTH" = truecolor ]; then
  C_DIR='1;38;2;90;200;210'; C_DIM='38;2;120;120;120'; C_MODEL='38;2;175;155;225'
  C_EFFORT='38;2;210;185;95'; C_GREEN='38;2;120;200;120'; C_YELLOW='38;2;235;205;60'
  C_ORANGE='38;2;230;140;40'; C_RED='38;2;235;77;75'
  B_DIR='48;2;38;78;84'; B_MODEL='48;2;58;50;82'; B_GREEN='48;2;40;72;40'
  B_YELLOW='48;2;82;74;26'; B_ORANGE='48;2;88;54;18'; B_RED='48;2;88;32;32'
  FG_BAR='38;2;235;235;235'
elif [ "$DEPTH" = 256 ]; then
  C_DIR='1;38;5;80'; C_DIM='38;5;244'; C_MODEL='38;5;141'; C_EFFORT='38;5;179'
  C_GREEN='38;5;114'; C_YELLOW='38;5;185'; C_ORANGE='38;5;208'; C_RED='38;5;203'
  B_DIR='48;5;23'; B_MODEL='48;5;60'; B_GREEN='48;5;22'; B_YELLOW='48;5;58'
  B_ORANGE='48;5;94'; B_RED='48;5;52'; FG_BAR='38;5;255'
else
  C_DIR='1;36'; C_DIM='90'; C_MODEL='35'; C_EFFORT='33'
  C_GREEN='32'; C_YELLOW='33'; C_ORANGE='33'; C_RED='31'
  B_DIR='44'; B_MODEL='45'; B_GREEN='42'; B_YELLOW='43'; B_ORANGE='43'; B_RED='41'
  FG_BAR='97'
fi

R=$(printf '\033[0m')
e() { printf '\033[%sm' "$1"; }   # escape for a color spec
# precompute frequently used escapes
E_DIR=$(e "$C_DIR"); E_DIM=$(e "$C_DIM"); E_MODEL=$(e "$C_MODEL"); E_EFFORT=$(e "$C_EFFORT")
E_GREEN=$(e "$C_GREEN"); E_YELLOW=$(e "$C_YELLOW"); E_ORANGE=$(e "$C_ORANGE"); E_RED=$(e "$C_RED")

# ------------------------------------------------------------------- glyphs --
if [ "$ASCII" = 1 ]; then
  G_SEP='|'; G_RST='~'; G_BOLT='*'; G_DOT='*'
  G_BARF='#'; G_BARE='-'; G_BL='['; G_BR=']'; PL_ARR=''
else
  G_SEP='·'; G_RST='↺'; G_BOLT='⚡'; G_DOT='●'
  G_BARF='█'; G_BARE='░'; G_BL='▕'; G_BR='▏'; PL_ARR=$(printf '\356\202\260')
fi

# -------------------------------------------------------------- parse input --
# Single jq call, fields joined by US (0x1f) — a NON-whitespace separator so
# `read` preserves empty fields (tabs would collapse, shifting columns).
_oldifs=$IFS
IFS=$(printf '\037')
read -r cwd model effort five_hr five_reset seven_day seven_reset ctx ctx_tok ctx_max <<EOF
$(printf '%s' "$input" | jq -r '[
  (.cwd // ""),
  (.model.display_name // ""),
  (.effort.level // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.rate_limits.seven_day.resets_at // ""),
  (.context_window.used_percentage // ""),
  (.context_window.total_input_tokens // ""),
  (.context_window.context_window_size // "")
] | map(tostring) | join("\u001f")' 2>/dev/null)
EOF
IFS=$_oldifs

dir=$(basename "$cwd" 2>/dev/null)
[ -z "$dir" ] && dir="~"
model=$(printf '%s' "$model" | sed -E 's/\(([0-9]+[A-Za-z]*) context\)/\1/; s/  +/ /g; s/ +$//')
[ -z "$effort" ] && effort=$(sed -n -E 's/.*"effortLevel"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$CLAUDE_DIR/settings.json" 2>/dev/null | head -1)

intval() { printf '%s' "$1" | awk '{printf "%d",$1}' 2>/dev/null; }
[ -n "$five_hr" ]   && five_hr=$(intval "$five_hr")
[ -n "$seven_day" ] && seven_day=$(intval "$seven_day")
[ -z "$ctx" ] && ctx=0; ctx=$(intval "$ctx")

# git
git_branch=''; git_dirty=0
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
               || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$git_branch" ]; then
    if ! git -C "$cwd" diff --quiet 2>/dev/null || ! git -C "$cwd" diff --cached --quiet 2>/dev/null; then
      git_dirty=1
    fi
  fi
fi

# ------------------------------------------------------------------ helpers --
fmt_k() {                                  # 47210 -> 47k, 1000000 -> 1.0M
  if [ "$1" -ge 1000000 ]; then
    printf '%d.%dM' $(( $1 / 1000000 )) $(( ($1 % 1000000) / 100000 ))
  else
    printf '%dk' $(( ($1 + 500) / 1000 ))
  fi
}
fmt_reset() {                              # epoch -> 3d5h / 5h12m / 45m (empty if past)
  [ -z "$1" ] && return
  _n=$(date +%s); _d=$(( ${1%.*} - _n ))
  [ "$_d" -le 0 ] && return
  _m=$(( _d / 60 )); _h=$(( _m / 60 )); _dd=$(( _h / 24 )); _h=$(( _h % 24 )); _m=$(( _m % 60 ))
  if   [ "$_dd" -gt 0 ]; then printf '%dd%dh' "$_dd" "$_h"
  elif [ "$_h"  -gt 0 ]; then printf '%dh%dm' "$_h" "$_m"
  else printf '%dm' "$_m"; fi
}
pct_e() {                                  # fg escape for a percentage
  if   [ "$1" -ge "$CRIT" ]; then printf '%s' "$E_RED"
  elif [ "$1" -ge "$HIGH" ]; then printf '%s' "$E_ORANGE"
  elif [ "$1" -ge "$WARN" ]; then printf '%s' "$E_YELLOW"
  else printf '%s' "$E_GREEN"; fi
}
pct_bg() {                                 # bg spec for a percentage
  if   [ "$1" -ge "$CRIT" ]; then printf '%s' "$B_RED"
  elif [ "$1" -ge "$HIGH" ]; then printf '%s' "$B_ORANGE"
  elif [ "$1" -ge "$WARN" ]; then printf '%s' "$B_YELLOW"
  else printf '%s' "$B_GREEN"; fi
}
bar() {                                    # bar PCT WIDTH -> filled/empty blocks
  _p=$1; _w=${2:-6}; _f=$(( _p * _w / 100 ))
  [ "$_f" -gt "$_w" ] && _f=$_w; [ "$_f" -lt 0 ] && _f=0
  _i=0; while [ "$_i" -lt "$_f" ]; do printf '%s' "$G_BARF"; _i=$((_i+1)); done
  while [ "$_i" -lt "$_w" ]; do printf '%s' "$G_BARE"; _i=$((_i+1)); done
}

# ---------------------------------------------------------------- renderers --
# plain / bars share a " · " separator join; powerline uses bg segments.
SEP="$E_DIM $G_SEP $R"
L=""
add() { if [ -z "$L" ]; then L="$1"; else L="$L$SEP$1"; fi; }

seg_dir() {
  _s="$E_DIR$dir$R"
  [ -n "$git_branch" ] && {
    _s="$_s$SEP$E_DIM$git_branch$R"
    [ "$git_dirty" = 1 ] && _s="$_s $E_ORANGE$G_DOT$R"
  }
  printf '%s' "$_s"
}
seg_model() {
  [ -z "$model" ] && return
  _s="$E_MODEL$model$R"
  [ -n "$effort" ] && _s="$_s $E_EFFORT$G_BOLT$effort$R"
  printf '%s' "$_s"
}
seg_limit() {                              # label pct reset  (plain)
  _e=$(pct_e "$2"); _s="$E_DIM$1 $_e$2%$R"
  _r=$(fmt_reset "$3"); [ -n "$_r" ] && _s="$_s $E_DIM$G_RST$_r$R"
  printf '%s' "$_s"
}
seg_limit_bar() {                          # label pct reset  (bars)
  _e=$(pct_e "$2"); _s="$E_DIM$1 $G_BL$_e$(bar "$2" 6)$E_DIM$G_BR $_e$2%$R"
  _r=$(fmt_reset "$3"); [ -n "$_r" ] && _s="$_s $E_DIM$G_RST$_r$R"
  printf '%s' "$_s"
}
seg_ctx() {                                # plain ctx
  _e=$(pct_e "$ctx"); _s="${E_DIM}ctx $_e$ctx%$R"
  [ -n "$ctx_tok" ] && [ -n "$ctx_max" ] && [ "$ctx_max" -gt 0 ] \
    && _s="$_s $E_DIM$(fmt_k "$ctx_tok")/$(fmt_k "$ctx_max")$R"
  printf '%s' "$_s"
}
seg_ctx_bar() {
  _e=$(pct_e "$ctx"); _s="${E_DIM}ctx $G_BL$_e$(bar "$ctx" 6)$E_DIM$G_BR $_e$ctx%$R"
  [ -n "$ctx_tok" ] && [ -n "$ctx_max" ] && [ "$ctx_max" -gt 0 ] \
    && _s="$_s $E_DIM$(fmt_k "$ctx_tok")/$(fmt_k "$ctx_max")$R"
  printf '%s' "$_s"
}

render_plain() {
  add "$(seg_dir)"; add "$(seg_model)"
  [ -n "$five_hr" ]   && add "$(seg_limit 5h "$five_hr" "$five_reset")"
  [ -n "$seven_day" ] && add "$(seg_limit 7d "$seven_day" "$seven_reset")"
  add "$(seg_ctx)"
  printf '%s' "$L"
}
render_bars() {
  add "$(seg_dir)"; add "$(seg_model)"
  [ -n "$five_hr" ]   && add "$(seg_limit_bar 5h "$five_hr" "$five_reset")"
  [ -n "$seven_day" ] && add "$(seg_limit_bar 7d "$seven_day" "$seven_reset")"
  add "$(seg_ctx_bar)"
  printf '%s' "$L"
}

# powerline: chained bg segments with  transitions
PL=""; PREV_AF=""
af_of() { printf '%s' "$1" | sed 's/^48;/38;/; s/^4\([0-7]\)$/3\1/; s/^10\([0-7]\)$/9\1/'; }
pl_add() {                                 # fg bg text
  _fg=$1; _bg=$2; _txt=$3; _af=$(af_of "$_bg")
  if [ -z "$PL" ]; then
    PL="$(e "$_fg;$_bg") $_txt "
  else
    PL="$PL$(e "$PREV_AF;$_bg")$PL_ARR$(e "$_fg;$_bg") $_txt "
  fi
  PREV_AF=$_af
}
pl_end() { PL="$PL$R$(e "$PREV_AF")$PL_ARR$R"; }
render_powerline() {
  _t="$dir"; [ -n "$git_branch" ] && { _t="$dir $G_SEP $git_branch"; [ "$git_dirty" = 1 ] && _t="$_t $G_DOT"; }
  pl_add "$FG_BAR" "$B_DIR" "$_t"
  [ -n "$model" ] && { _t="$model"; [ -n "$effort" ] && _t="$model $G_BOLT$effort"; pl_add "$FG_BAR" "$B_MODEL" "$_t"; }
  if [ -n "$five_hr" ]; then _r=$(fmt_reset "$five_reset"); _t="5h $five_hr%"; [ -n "$_r" ] && _t="$_t $G_RST$_r"; pl_add "$FG_BAR" "$(pct_bg "$five_hr")" "$_t"; fi
  if [ -n "$seven_day" ]; then _r=$(fmt_reset "$seven_reset"); _t="7d $seven_day%"; [ -n "$_r" ] && _t="$_t $G_RST$_r"; pl_add "$FG_BAR" "$(pct_bg "$seven_day")" "$_t"; fi
  _t="ctx $ctx%"; [ -n "$ctx_tok" ] && [ -n "$ctx_max" ] && [ "$ctx_max" -gt 0 ] && _t="$_t $(fmt_k "$ctx_tok")/$(fmt_k "$ctx_max")"
  pl_add "$FG_BAR" "$(pct_bg "$ctx")" "$_t"
  pl_end
  printf '%s' "$PL"
}

case "$STYLE" in
  bars)      render_bars ;;
  powerline) if [ "$ASCII" = 1 ]; then render_bars; else render_powerline; fi ;;
  *)         render_plain ;;
esac
