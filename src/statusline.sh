#!/bin/sh
# ccline — a capability-aware status line for Claude Code.
# https://github.com/akaribrahim/ccline
#
# Reads Claude Code's status JSON on stdin and prints one styled line.
# Adapts to terminal color depth (truecolor / 256 / 16) and glyph support.
#
# Claude Code re-runs this on conversation events, and — when statusLine.
# refreshInterval is set in settings.json — every N seconds as well. It is
# therefore written to be fork-cheap: one jq call, one git call, no subshells
# in the render path. Helpers return values in globals rather than via $(...),
# which would fork.
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

trim() {                                   # -> _R  (no fork)
  _R=$1
  while :; do case $_R in ' '*|"	"*) _R=${_R#?} ;; *) break ;; esac; done
  while :; do case $_R in *' '|*"	") _R=${_R%?} ;; *) break ;; esac; done
}

# One pass over the conf file; last assignment of a key wins.
CF_STYLE=''; CF_COLOR=''; CF_ASCII=''; CF_WARN=''; CF_HIGH=''; CF_CRIT=''; CF_WT=''
if [ -f "$CONF" ]; then
  while IFS= read -r _l || [ -n "$_l" ]; do
    case $_l in ''|'#'*) continue ;; *=*) ;; *) continue ;; esac
    trim "${_l%%=*}"; _k=$_R
    trim "${_l#*=}";  _v=$_R
    case $_v in '"'*'"') _v=${_v#\"}; _v=${_v%\"} ;; esac
    case $_k in
      CCLINE_STYLE)    CF_STYLE=$_v ;;
      CCLINE_COLOR)    CF_COLOR=$_v ;;
      CCLINE_ASCII)    CF_ASCII=$_v ;;
      CCLINE_WARN)     CF_WARN=$_v ;;
      CCLINE_HIGH)     CF_HIGH=$_v ;;
      CCLINE_CRIT)     CF_CRIT=$_v ;;
      CCLINE_WORKTREE) CF_WT=$_v ;;
    esac
  done < "$CONF"
fi
STYLE="${CCLINE_STYLE:-${CF_STYLE:-plain}}"
FORCE_COLOR="${CCLINE_COLOR:-${CF_COLOR:-auto}}"
FORCE_ASCII="${CCLINE_ASCII:-${CF_ASCII:-auto}}"
WARN="${CCLINE_WARN:-${CF_WARN:-50}}"
HIGH="${CCLINE_HIGH:-${CF_HIGH:-75}}"
CRIT="${CCLINE_CRIT:-${CF_CRIT:-90}}"
WORKTREE="${CCLINE_WORKTREE:-${CF_WT:-auto}}"
case "$WORKTREE" in 0|false|no|off) WT_ON=0 ;; *) WT_ON=1 ;; esac

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
  B_STALE='48;2;58;58;58'; FG_BAR='38;2;235;235;235'
elif [ "$DEPTH" = 256 ]; then
  C_DIR='1;38;5;80'; C_DIM='38;5;244'; C_MODEL='38;5;141'; C_EFFORT='38;5;179'
  C_GREEN='38;5;114'; C_YELLOW='38;5;185'; C_ORANGE='38;5;208'; C_RED='38;5;203'
  B_DIR='48;5;23'; B_MODEL='48;5;60'; B_GREEN='48;5;22'; B_YELLOW='48;5;58'
  B_ORANGE='48;5;94'; B_RED='48;5;52'; B_STALE='48;5;238'; FG_BAR='38;5;255'
else
  C_DIR='1;36'; C_DIM='90'; C_MODEL='35'; C_EFFORT='33'
  C_GREEN='32'; C_YELLOW='33'; C_ORANGE='33'; C_RED='31'
  B_DIR='44'; B_MODEL='45'; B_GREEN='42'; B_YELLOW='43'; B_ORANGE='43'; B_RED='41'
  B_STALE='100'; FG_BAR='97'
fi

ESC=$(printf '\033')
R="$ESC[0m"
E_DIR="$ESC[${C_DIR}m";     E_DIM="$ESC[${C_DIM}m"
E_MODEL="$ESC[${C_MODEL}m"; E_EFFORT="$ESC[${C_EFFORT}m"
E_GREEN="$ESC[${C_GREEN}m"; E_YELLOW="$ESC[${C_YELLOW}m"
E_ORANGE="$ESC[${C_ORANGE}m"; E_RED="$ESC[${C_RED}m"

# ------------------------------------------------------------------- glyphs --
if [ "$ASCII" = 1 ]; then
  G_SEP='|'; G_RST='~'; G_BOLT='*'; G_DOT='*'; G_WT='wt:'; G_DASH='-'
  G_BARF='#'; G_BARE='-'; G_BL='['; G_BR=']'; PL_ARR=''
else
  G_SEP='·'; G_RST='↺'; G_BOLT='⚡'; G_DOT='●'; G_WT='⑂'; G_DASH='—'
  G_BARF='█'; G_BARE='░'; G_BL='▕'; G_BR='▏'; PL_ARR=$(printf '\356\202\260')
fi

# --------------------------------------------------------------------- now --
# bash 5 / zsh expose EPOCHSECONDS for free; older shells pay one fork.
NOW=${EPOCHSECONDS:-}
[ -z "$NOW" ] && NOW=$(date +%s)

# -------------------------------------------------------------- parse input --
# Single jq call, fields joined by US (0x1f) — a NON-whitespace separator so
# `read` preserves empty fields (tabs would collapse, shifting columns).
# has_ws tells us whether this Claude Code emits .workspace at all: if it does,
# git_worktree is authoritative and we can skip probing git for it entirely.
_oldifs=$IFS
IFS=$(printf '\037')
read -r cwd model effort five_hr five_reset seven_day seven_reset ctx ctx_tok ctx_max wt has_ws <<EOF
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
  (.context_window.context_window_size // ""),
  (.workspace.git_worktree // ""),
  (if .workspace then "1" else "0" end)
] | map(tostring) | join("\u001f")' 2>/dev/null)
EOF
IFS=$_oldifs

dir=${cwd##*/}
[ -z "$dir" ] && dir="~"

# "Sonnet 4.5 (1M context)" -> "Sonnet 4.5 1M"
case $model in
  *'('*' context)'*)
    _pre=${model%%'('*}; _rest=${model#*'('}
    model="$_pre${_rest%%' context)'*}${_rest#*' context)'}" ;;
esac
trim "$model"; model=$_R

[ -z "$effort" ] && effort=$(sed -n -E 's/.*"effortLevel"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$CLAUDE_DIR/settings.json" 2>/dev/null | head -1)

intval() { _IV=${1%%.*}; case $_IV in ''|*[!0-9]*) _IV=0 ;; esac; }
[ -n "$five_hr" ]   && { intval "$five_hr";   five_hr=$_IV; }
[ -n "$seven_day" ] && { intval "$seven_day"; seven_day=$_IV; }
intval "$ctx"; ctx=$_IV

# A rate-limit window whose resets_at has passed is a *known-stale* reading:
# rate_limits only refresh when an API response arrives, so after the window
# rolls over the old percentage is simply wrong until the next message. Show a
# dash rather than a number we know to be false.
expired() {                                # -> _EX (1 = window already reset)
  _EX=0
  [ -z "$1" ] && return
  _t=${1%.*}
  case $_t in ''|*[!0-9]*) return ;; esac
  [ "$_t" -le "$NOW" ] && _EX=1
}
expired "$five_reset";  five_stale=$_EX
expired "$seven_reset"; seven_stale=$_EX

# ---------------------------------------------------------------------- git --
# One `git status --porcelain=v2 --branch -uno` yields branch AND dirtiness;
# -uno skips the untracked walk, which is the expensive part on big trees.
git_branch=''; git_dirty=0; git_worktree=$wt; _oid=''
if [ -n "$cwd" ]; then
  while IFS= read -r _l; do
    case $_l in
      '# branch.head '*) git_branch=${_l#'# branch.head '} ;;
      '# branch.oid '*) _oid=${_l#'# branch.oid '} ;;
      '#'*) ;;
      ?*) git_dirty=1 ;;
    esac
  done <<EOF
$(git -C "$cwd" status --porcelain=v2 --branch -uno 2>/dev/null)
EOF
fi
# detached HEAD: porcelain reports "(detached)" — fall back to a short sha
if [ "$git_branch" = '(detached)' ]; then
  case $_oid in
    '(initial)'|'') git_branch='' ;;
    *) git_branch=${_oid%"${_oid#???????}"} ;;
  esac
fi
# Older Claude Code (no .workspace in the payload): probe git for the worktree.
if [ "$has_ws" != 1 ] && [ "$WT_ON" = 1 ] && [ -n "$git_branch" ]; then
  { read -r _gd; read -r _gcd; read -r _top; } <<EOF
$(git -C "$cwd" rev-parse --git-dir --git-common-dir --show-toplevel 2>/dev/null)
EOF
  [ -n "$_gd" ] && [ "$_gd" != "$_gcd" ] && git_worktree=${_top##*/}
fi
[ "$WT_ON" = 1 ] || git_worktree=''

# ------------------------------------------------------------------ helpers --
fmt_k() {                                  # 47210 -> _K=47k, 1000000 -> _K=1.0M
  if [ "$1" -ge 1000000 ]; then
    _K="$(( $1 / 1000000 )).$(( ($1 % 1000000) / 100000 ))M"
  else
    _K="$(( ($1 + 500) / 1000 ))k"
  fi
}
fmt_reset() {                              # epoch -> _RS=3d5h / 5h12m / 45m ('' if past)
  _RS=''
  [ -z "$1" ] && return
  _t=${1%.*}
  case $_t in ''|*[!0-9]*) return ;; esac
  _d=$(( _t - NOW ))
  [ "$_d" -le 0 ] && return
  _m=$(( _d / 60 )); _h=$(( _m / 60 )); _dd=$(( _h / 24 )); _h=$(( _h % 24 )); _m=$(( _m % 60 ))
  if   [ "$_dd" -gt 0 ]; then _RS="${_dd}d${_h}h"
  elif [ "$_h"  -gt 0 ]; then _RS="${_h}h${_m}m"
  else _RS="${_m}m"; fi
}
pct_e() {                                  # fg escape for a percentage -> _E
  if   [ "$1" -ge "$CRIT" ]; then _E=$E_RED
  elif [ "$1" -ge "$HIGH" ]; then _E=$E_ORANGE
  elif [ "$1" -ge "$WARN" ]; then _E=$E_YELLOW
  else _E=$E_GREEN; fi
}
pct_bg() {                                 # bg spec for a percentage -> _BG
  if   [ "$1" -ge "$CRIT" ]; then _BG=$B_RED
  elif [ "$1" -ge "$HIGH" ]; then _BG=$B_ORANGE
  elif [ "$1" -ge "$WARN" ]; then _BG=$B_YELLOW
  else _BG=$B_GREEN; fi
}
bar() {                                    # bar PCT WIDTH -> _BAR
  _p=$1; _w=${2:-6}; _f=$(( _p * _w / 100 ))
  [ "$_f" -gt "$_w" ] && _f=$_w; [ "$_f" -lt 0 ] && _f=0
  _BAR=''; _i=0
  while [ "$_i" -lt "$_f" ]; do _BAR="$_BAR$G_BARF"; _i=$((_i+1)); done
  while [ "$_i" -lt "$_w" ]; do _BAR="$_BAR$G_BARE"; _i=$((_i+1)); done
}

# ---------------------------------------------------------------- renderers --
# plain / bars share a " · " separator join; powerline uses bg segments.
SEP="$E_DIM $G_SEP $R"
L=""
add() { if [ -z "$L" ]; then L=$1; else L="$L$SEP$1"; fi; }

seg_dir() {                                # -> _SEG
  _SEG="$E_DIR$dir$R"
  if [ -n "$git_branch" ]; then
    _SEG="$_SEG$SEP$E_DIM$git_branch$R"
    [ "$git_dirty" = 1 ] && _SEG="$_SEG $E_ORANGE$G_DOT$R"
  fi
  [ -n "$git_worktree" ] && _SEG="$_SEG $E_DIM$G_WT$git_worktree$R"
}
seg_model() {                              # -> _SEG
  _SEG=''
  [ -z "$model" ] && return
  _SEG="$E_MODEL$model$R"
  [ -n "$effort" ] && _SEG="$_SEG $E_EFFORT$G_BOLT$effort$R"
}
seg_limit() {                              # label pct reset stale -> _SEG
  if [ "$4" = 1 ]; then _SEG="$E_DIM$1 $G_DASH$R"; return; fi
  pct_e "$2"
  _SEG="$E_DIM$1 $_E$2%$R"
  fmt_reset "$3"; [ -n "$_RS" ] && _SEG="$_SEG $E_DIM$G_RST$_RS$R"
}
seg_limit_bar() {                          # label pct reset stale -> _SEG
  if [ "$4" = 1 ]; then _SEG="$E_DIM$1 $G_DASH$R"; return; fi
  pct_e "$2"; bar "$2" 6
  _SEG="$E_DIM$1 $G_BL$_E$_BAR$E_DIM$G_BR $_E$2%$R"
  fmt_reset "$3"; [ -n "$_RS" ] && _SEG="$_SEG $E_DIM$G_RST$_RS$R"
}
seg_ctx() {                                # -> _SEG
  pct_e "$ctx"
  _SEG="${E_DIM}ctx $_E$ctx%$R"
  if [ -n "$ctx_tok" ] && [ -n "$ctx_max" ] && [ "$ctx_max" -gt 0 ] 2>/dev/null; then
    fmt_k "$ctx_tok"; _t=$_K; fmt_k "$ctx_max"
    _SEG="$_SEG $E_DIM$_t/$_K$R"
  fi
}
seg_ctx_bar() {                            # -> _SEG
  pct_e "$ctx"; bar "$ctx" 6
  _SEG="${E_DIM}ctx $G_BL$_E$_BAR$E_DIM$G_BR $_E$ctx%$R"
  if [ -n "$ctx_tok" ] && [ -n "$ctx_max" ] && [ "$ctx_max" -gt 0 ] 2>/dev/null; then
    fmt_k "$ctx_tok"; _t=$_K; fmt_k "$ctx_max"
    _SEG="$_SEG $E_DIM$_t/$_K$R"
  fi
}

render_plain() {
  seg_dir; add "$_SEG"
  seg_model; [ -n "$_SEG" ] && add "$_SEG"
  [ -n "$five_hr" ]   && { seg_limit 5h "$five_hr" "$five_reset" "$five_stale"; add "$_SEG"; }
  [ -n "$seven_day" ] && { seg_limit 7d "$seven_day" "$seven_reset" "$seven_stale"; add "$_SEG"; }
  seg_ctx; add "$_SEG"
  printf '%s' "$L"
}
render_bars() {
  seg_dir; add "$_SEG"
  seg_model; [ -n "$_SEG" ] && add "$_SEG"
  [ -n "$five_hr" ]   && { seg_limit_bar 5h "$five_hr" "$five_reset" "$five_stale"; add "$_SEG"; }
  [ -n "$seven_day" ] && { seg_limit_bar 7d "$seven_day" "$seven_reset" "$seven_stale"; add "$_SEG"; }
  seg_ctx_bar; add "$_SEG"
  printf '%s' "$L"
}

# powerline: chained bg segments with  transitions
PL=""; PREV_AF=""
af_of() {                                  # bg spec -> _AF (same color as fg)
  case $1 in
    48\;*)   _AF="38;${1#48;}" ;;
    4[0-7])  _AF="3${1#4}" ;;
    10[0-7]) _AF="9${1#10}" ;;
    *)       _AF=$1 ;;
  esac
}
pl_add() {                                 # fg bg text
  _fg=$1; _bg=$2; _txt=$3
  if [ -z "$PL" ]; then
    PL="$ESC[$_fg;${_bg}m $_txt "
  else
    PL="$PL$ESC[$PREV_AF;${_bg}m$PL_ARR$ESC[$_fg;${_bg}m $_txt "
  fi
  af_of "$_bg"; PREV_AF=$_AF
}
pl_limit() {                               # label pct reset stale
  if [ "$4" = 1 ]; then pl_add "$FG_BAR" "$B_STALE" "$1 $G_DASH"; return; fi
  fmt_reset "$3"; _t="$1 $2%"
  [ -n "$_RS" ] && _t="$_t $G_RST$_RS"
  pct_bg "$2"; pl_add "$FG_BAR" "$_BG" "$_t"
}
render_powerline() {
  _t="$dir"
  [ -n "$git_branch" ] && { _t="$dir $G_SEP $git_branch"; [ "$git_dirty" = 1 ] && _t="$_t $G_DOT"; }
  [ -n "$git_worktree" ] && _t="$_t $G_WT$git_worktree"
  pl_add "$FG_BAR" "$B_DIR" "$_t"
  if [ -n "$model" ]; then
    _t="$model"; [ -n "$effort" ] && _t="$model $G_BOLT$effort"
    pl_add "$FG_BAR" "$B_MODEL" "$_t"
  fi
  [ -n "$five_hr" ]   && pl_limit 5h "$five_hr" "$five_reset" "$five_stale"
  [ -n "$seven_day" ] && pl_limit 7d "$seven_day" "$seven_reset" "$seven_stale"
  _t="ctx $ctx%"
  if [ -n "$ctx_tok" ] && [ -n "$ctx_max" ] && [ "$ctx_max" -gt 0 ] 2>/dev/null; then
    fmt_k "$ctx_tok"; _c=$_K; fmt_k "$ctx_max"; _t="$_t $_c/$_K"
  fi
  pct_bg "$ctx"; pl_add "$FG_BAR" "$_BG" "$_t"
  PL="$PL$R$ESC[${PREV_AF}m$PL_ARR$R"
  printf '%s' "$PL"
}

case "$STYLE" in
  bars)      render_bars ;;
  powerline) if [ "$ASCII" = 1 ]; then render_bars; else render_powerline; fi ;;
  *)         render_plain ;;
esac
