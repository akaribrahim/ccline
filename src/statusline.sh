#!/bin/sh
# ccline — a capability-aware status line for Claude Code.
# https://github.com/akaribrahim/ccline
#
# Reads Claude Code's status JSON on stdin and prints one styled line.
# Adapts to terminal color depth (truecolor / 256 / 16) and glyph support.
#
# Claude Code re-runs this on conversation events, and — when statusLine.
# refreshInterval is set in settings.json — every N seconds as well. It is
# therefore written to be fork-cheap: one jq call, two git calls (three inside
# a worktree, for the tint), no subshells in the render path. Helpers return
# values in globals rather than via $(...), which would fork.
#
# Config: env vars override ~/.claude/ccline.conf (KEY=value lines).
#   CCLINE_STYLE   plain | bars | powerline      (default: plain)
#   CCLINE_COLOR   auto | truecolor | 256 | 16    (default: auto)
#   CCLINE_ASCII   auto | 1 | 0                   (default: auto)
#   CCLINE_DIR     full | name                    (default: full — path or basename)
#   CCLINE_NAME    auto | tmux | 0                (session name; CCLINE_NAME_TRIM drops prefixes)
#   CCLINE_RC      auto | 0                       (📱 while Remote Control is on)
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
CF_PACE=''; CF_PACEWARN=''; CF_PR=''; CF_WTCOLOR=''; CF_DIR=''
CF_NAME=''; CF_NAMETRIM=''; CF_RC=''
# One machine can run several Claude Code config dirs (CLAUDE_CONFIG_DIR, one
# per account); they share ~/.claude/ccline.conf unless they carry their own.
if [ ! -f "$CONF" ] && [ -z "${CCLINE_CONFIG:-}" ] && [ -f "$HOME/.claude/ccline.conf" ]; then
  CONF="$HOME/.claude/ccline.conf"
fi
if [ -f "$CONF" ]; then
  while IFS= read -r _l || [ -n "$_l" ]; do
    case $_l in ''|'#'*) continue ;; *=*) ;; *) continue ;; esac
    trim "${_l%%=*}"; _k=$_R
    trim "${_l#*=}";  _v=$_R
    case $_v in '"'*'"') _v=${_v#\"}; _v=${_v%\"} ;; esac
    case $_k in
      CCLINE_STYLE)     CF_STYLE=$_v ;;
      CCLINE_COLOR)     CF_COLOR=$_v ;;
      CCLINE_ASCII)     CF_ASCII=$_v ;;
      CCLINE_WARN)      CF_WARN=$_v ;;
      CCLINE_HIGH)      CF_HIGH=$_v ;;
      CCLINE_CRIT)      CF_CRIT=$_v ;;
      CCLINE_WORKTREE)  CF_WT=$_v ;;
      CCLINE_WT_COLOR)  CF_WTCOLOR=$_v ;;
      CCLINE_DIR)       CF_DIR=$_v ;;
      CCLINE_PACE)      CF_PACE=$_v ;;
      CCLINE_PACE_WARN) CF_PACEWARN=$_v ;;
      CCLINE_PR)        CF_PR=$_v ;;
      CCLINE_NAME)      CF_NAME=$_v ;;
      CCLINE_NAME_TRIM) CF_NAMETRIM=$_v ;;
      CCLINE_RC)        CF_RC=$_v ;;
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
DIRMODE="${CCLINE_DIR:-${CF_DIR:-full}}"
PACE="${CCLINE_PACE:-${CF_PACE:-auto}}"
PACE_WARN="${CCLINE_PACE_WARN:-${CF_PACEWARN:-90}}"
PR="${CCLINE_PR:-${CF_PR:-auto}}"
off() { case "$1" in 0|false|no|off) return 0 ;; *) return 1 ;; esac; }
WT_COLOR="${CCLINE_WT_COLOR:-${CF_WTCOLOR:-auto}}"
off "$WORKTREE" && WT_ON=0 || WT_ON=1
off "$PACE"     && PACE_ON=0 || PACE_ON=1
off "$PR"       && PR_ON=0   || PR_ON=1
off "$WT_COLOR" && WTC_ON=0  || WTC_ON=1
NAME="${CCLINE_NAME:-${CF_NAME:-auto}}"
NAME_TRIM="${CCLINE_NAME_TRIM:-${CF_NAMETRIM:-}}"
RC="${CCLINE_RC:-${CF_RC:-auto}}"
off "$NAME"     && NAME_ON=0 || NAME_ON=1
off "$RC"       && RC_ON=0   || RC_ON=1

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
  B_NAME='48;2;58;58;58'; FG_BAR='38;2;235;235;235'; C_NAME='1;38;2;235;235;235'
  WC0_F='1;38;2;120;200;120'; WC0_B='48;2;40;72;40'      # worktree tints
  WC1_F='1;38;2;185;150;235'; WC1_B='48;2;58;46;86'
  WC2_F='1;38;2;225;170;80';  WC2_B='48;2;86;62;22'
  WC3_F='1;38;2;110;165;235'; WC3_B='48;2;32;56;94'
  WC4_F='1;38;2;230;130;180'; WC4_B='48;2;84;38;64'
  WC5_F='1;38;2;235;120;100'; WC5_B='48;2;90;40;32'
elif [ "$DEPTH" = 256 ]; then
  C_DIR='1;38;5;80'; C_DIM='38;5;244'; C_MODEL='38;5;141'; C_EFFORT='38;5;179'
  C_GREEN='38;5;114'; C_YELLOW='38;5;185'; C_ORANGE='38;5;208'; C_RED='38;5;203'
  B_DIR='48;5;23'; B_MODEL='48;5;60'; B_GREEN='48;5;22'; B_YELLOW='48;5;58'
  B_ORANGE='48;5;94'; B_RED='48;5;52'; B_NAME='48;5;238'; FG_BAR='38;5;255'
  C_NAME='1;38;5;255'
  WC0_F='1;38;5;114'; WC0_B='48;5;22'                    # worktree tints
  WC1_F='1;38;5;141'; WC1_B='48;5;60'
  WC2_F='1;38;5;179'; WC2_B='48;5;94'
  WC3_F='1;38;5;75';  WC3_B='48;5;24'
  WC4_F='1;38;5;175'; WC4_B='48;5;89'
  WC5_F='1;38;5;209'; WC5_B='48;5;52'
else
  C_DIR='1;36'; C_DIM='90'; C_MODEL='35'; C_EFFORT='33'
  C_GREEN='32'; C_YELLOW='33'; C_ORANGE='33'; C_RED='31'
  B_DIR='44'; B_MODEL='45'; B_GREEN='42'; B_YELLOW='43'; B_ORANGE='43'; B_RED='41'
  B_NAME='100'; FG_BAR='97'; C_NAME='1;97'
  WC0_F='1;32'; WC0_B='42'                               # worktree tints
  WC1_F='1;35'; WC1_B='45'
  WC2_F='1;33'; WC2_B='43'
  WC3_F='1;34'; WC3_B='44'
  WC4_F='1;95'; WC4_B='105'
  WC5_F='1;31'; WC5_B='41'
fi

ESC=$(printf '\033')
R="$ESC[0m"
# The branch takes the directory's colour minus the bold — the two read as one
# unit, and the branch never sits in the dim grey reserved for numbers you
# glance past. In a worktree C_DIR is that worktree's tint, so the branch is
# tinted with it; dir_e is re-run once the tint is known.
dir_e() { E_DIR="$ESC[${C_DIR}m"; E_BRANCH="$ESC[${C_DIR#1;}m"; }
dir_e
E_DIM="$ESC[${C_DIM}m"
E_MODEL="$ESC[${C_MODEL}m"; E_EFFORT="$ESC[${C_EFFORT}m"
E_GREEN="$ESC[${C_GREEN}m"; E_YELLOW="$ESC[${C_YELLOW}m"
E_ORANGE="$ESC[${C_ORANGE}m"; E_RED="$ESC[${C_RED}m"
E_NAME="$ESC[${C_NAME}m"

# ------------------------------------------------------------------- glyphs --
if [ "$ASCII" = 1 ]; then
  G_SEP='|'; G_RST='~'; G_BOLT='*'; G_DOT='*'; G_WT='wt:'
  G_BARF='#'; G_BARE='-'; G_BL='['; G_BR=']'; PL_ARR=''
  G_PACE='>'; G_OK='+'; G_NOK='x'; G_RC='(rc)'; G_ELL='~'
else
  G_SEP='·'; G_RST='↺'; G_BOLT='⚡'; G_DOT='●'; G_WT='⑂'
  G_BARF='█'; G_BARE='░'; G_BL='▕'; G_BR='▏'; PL_ARR=$(printf '\356\202\260')
  G_PACE='→'; G_OK='✓'; G_NOK='✗'; G_RC='📱'; G_ELL='…'
fi

# ------------------------------------------------------------------- locale --
# A long session title is cut by characters, not bytes: a byte cut can split a
# multi-byte letter. bash counts characters under a UTF-8 locale — and a
# session started over ssh or inside tmux often has no locale at all. So
# borrow C.UTF-8 just for the count and hand the caller's locale back (date's
# weekday names come from it). Not bash, or no UTF-8 locale to borrow: MB=0,
# and a long name is left whole.
mb_on()  { _lcs=${LC_ALL+1}; _lco=${LC_ALL:-}; { LC_ALL=C.UTF-8; } 2>/dev/null; }
mb_off() { if [ -n "$_lcs" ]; then LC_ALL=$_lco; else unset LC_ALL; fi; }
MB=0
if [ -n "${BASH_VERSION:-}" ]; then
  _probe='·'; mb_on; [ "${#_probe}" = 1 ] && MB=1; mb_off
fi

# --------------------------------------------------------------------- now --
# bash 5 / zsh expose EPOCHSECONDS for free; older shells pay one fork.
NOW=${EPOCHSECONDS:-}
[ -z "$NOW" ] && NOW=$(date +%s)

# Reset times print as a local clock (18:42), not a countdown, so we need to
# turn an epoch into wall-clock fields. GNU date wants `-d @EPOCH`, BSD/macOS
# wants `-r EPOCH` — probe once (`date -r 0` is a valid epoch on BSD, a missing
# file on GNU). Stash today's day-of-year too so fmt_reset only forks for the
# reset itself and can tell "later today" from "another day" without recomputing.
if date -r 0 +%s >/dev/null 2>&1; then DATE_R=1; else DATE_R=0; fi
epoch_fmt() {                              # epoch strftime -> _EF (local time)
  if [ "$DATE_R" = 1 ]; then _EF=$(date -r "$1" +"$2"); else _EF=$(date -d "@$1" +"$2"); fi
}
epoch_fmt "$NOW" %j; NOW_JDAY=$_EF
epoch_fmt "$NOW" %a; NOW_WDAY=$_EF

# -------------------------------------------------------------- parse input --
# Single jq call, fields joined by US (0x1f) — a NON-whitespace separator so
# `read` preserves empty fields (tabs would collapse, shifting columns).
# has_ws tells us whether this Claude Code emits .workspace at all: if it does,
# git_worktree is authoritative and we can skip probing git for it entirely.
_oldifs=$IFS
IFS=$(printf '\037')
read -r cwd model effort five_hr five_reset seven_day seven_reset ctx ctx_tok ctx_max wt has_ws \
        pr_num pr_state sid sname <<EOF
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
  (if .workspace then "1" else "0" end),
  (.pr.number // ""),
  (.pr.review_state // "" | ascii_downcase),
  (.session_id // ""),
  (.session_name // "" | gsub("[[:cntrl:]]"; ""))
] | map(tostring) | join("\u001f")' 2>/dev/null)
EOF
IFS=$_oldifs

# The directory segment is the whole path, $HOME folded to ~. A basename is
# ambiguous the moment worktrees are in play: Claude Code puts them under
# <project>/.claude/worktrees/<name>, so the basename is the worktree's name and
# the project's name is nowhere on the line — with several sessions open across
# several projects, every tab reads alike. The path says both, and says where on
# disk to go. CCLINE_DIR=name restores the basename.
case $DIRMODE in
  name) dir=${cwd##*/} ;;
  *)    dir=$cwd
        case $dir in
          "$HOME")   dir='~' ;;
          "$HOME"/*) dir="~${dir#"$HOME"}" ;;
        esac ;;
esac
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

# ------------------------------------------------------------------ session --
# Claude Code's own per-process state file, $CLAUDE_DIR/sessions/<pid>.json,
# knows two things the payload doesn't: whether Remote Control is on, and which
# tmux pane the session runs in. We are that process's child — directly, or
# through one shell — and the file must name this payload's session, so a
# recycled pid can't answer for it. Read on every run, so Remote Control
# toggled mid-session shows up within one refreshInterval.
_SJ=''
state_file() {                             # pid -> 0 if its state file is ours (-> _SJ)
  _SJ=''
  [ -f "$CLAUDE_DIR/sessions/$1.json" ] || return 1
  IFS= read -r _SJ < "$CLAUDE_DIR/sessions/$1.json"
  case $_SJ in *"\"sessionId\":\"$sid\""*) return 0 ;; esac
  _SJ=''; return 1
}
if [ -n "$sid" ] && { [ "$RC_ON" = 1 ] || [ "$NAME" = tmux ]; }; then
  if ! state_file "$PPID"; then
    _pp=$(ps -o ppid= -p "$PPID" 2>/dev/null); trim "$_pp"
    case $_R in ''|*[!0-9]*) ;; *) state_file "$_R" ;; esac
  fi
fi

# Which conversation is this? With several open — tabs, tmux panes, chats
# reached over ssh — path and model read alike in all of them; the name
# doesn't. It comes from --name, /rename, or Claude Code's generated title.
# CCLINE_NAME=tmux names it after the tmux session it runs in instead — the
# handle you attach and switch by, when each conversation gets a session of
# its own — and falls back to Claude Code's name outside tmux.
# CCLINE_NAME_TRIM drops a launcher's prefix ("makira-ibrahim" -> "ibrahim").
name=''
if [ "$NAME_ON" = 1 ]; then
  if [ "$NAME" = tmux ]; then
    _k='"tmux":"'                          # "tmux":"<session>:@<window>.%<pane>"
    case $_SJ in *"$_k"*) name=${_SJ#*"$_k"}; name=${name%%\"*}; name=${name%%:*} ;; esac
    if [ -z "$name" ] && [ -n "${TMUX:-}" ]; then
      if [ -n "${TMUX_PANE:-}" ]; then
        name=$(tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null)
      else
        name=$(tmux display-message -p '#S' 2>/dev/null)
      fi
    fi
  fi
  [ -z "$name" ] && name=$sname
  for _p in $NAME_TRIM; do
    case $name in "$_p"?*) name=${name#"$_p"}; break ;; esac
  done
  # A generated title can run long; the row belongs to the numbers. (eval keeps
  # the bash-only substring away from a POSIX sh parser.)
  if [ "$MB" = 1 ] && [ -n "$name" ]; then
    mb_on; [ "${#name}" -gt 24 ] && eval 'name="${name:0:23}$G_ELL"'; mb_off
  fi
fi

# Remote Control — can this session be picked up from claude.ai or the phone?
# The payload doesn't say (its `remote` field means the reverse: this terminal
# watching a session that runs elsewhere); the state file holds a
# bridgeSessionId while it's on.
rc=0
if [ "$RC_ON" = 1 ]; then
  case $_SJ in *'"bridgeSessionId":"'*) rc=1 ;; esac
fi

# A rate-limit window whose resets_at has passed is a *known-stale* reading:
# rate_limits only refresh when an API response arrives, so once the window
# rolls over the old percentage is simply wrong until the next message.
expired() {                                # -> _EX (1 = window already reset)
  _EX=0
  [ -z "$1" ] && return
  _ep=${1%.*}
  case $_ep in ''|*[!0-9]*) return ;; esac
  [ "$_ep" -le "$NOW" ] && _EX=1
}

# A window is shown only while Claude Code reports it. Absent — before the first
# response, or on a plan that doesn't meter that window at all — it takes no
# room: a slot held open with a dash reads as "coming", and for some accounts
# it never comes. Expired counts as absent too (current Claude Code drops an
# expired window from the payload itself; older versions kept the stale figure).
expired "$five_reset"
if [ -n "$five_hr" ] && [ "$_EX" = 0 ]; then five_show=1; else five_show=0; fi
expired "$seven_reset"
if [ -n "$seven_day" ] && [ "$_EX" = 0 ]; then seven_show=1; else seven_show=0; fi

# Pace: "at this burn rate, where does the window end up?" The window length is
# fixed (5h / 7d) and resets_at is its end, so elapsed — and therefore the
# projection — is pure local arithmetic; no history file, no extra process.
#   projected = used% / elapsed_fraction
# Early in a window a couple of percent projects to absurd numbers, so stay
# quiet until 15% of it has elapsed, and only speak up at PACE_WARN and above:
# a marker that appears only when it means something.
W_5H=18000; W_7D=604800
pace() {                                   # used% reset window -> _P ('' = quiet)
  _P=''
  [ "$PACE_ON" = 1 ] || return
  [ -z "$1" ] && return
  [ -z "$2" ] && return
  _ep=${2%.*}
  case $_ep in ''|*[!0-9]*) return ;; esac
  _rem=$(( _ep - NOW ))
  [ "$_rem" -le 0 ] && return              # already reset — the window is hidden then
  _el=$(( $3 - _rem ))                     # seconds elapsed in the window
  [ "$_el" -le 0 ] && return               # clock skew / longer window than we assume
  [ $(( _el * 100 / $3 )) -lt 15 ] && return
  [ "$1" -le 0 ] && return
  _pj=$(( $1 * $3 / _el ))
  [ "$_pj" -gt 999 ] && _pj=999
  [ "$_pj" -lt "$PACE_WARN" ] && return
  _P=$_pj
}

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
# Ask git where we are rather than trusting the payload to carry it: older
# Claude Code has no .workspace at all, and we shouldn't bet the badge on a
# newer one always populating .workspace.git_worktree. A linked worktree has a
# git-dir (.git/worktrees/<n>) distinct from the shared git-common-dir.
_gd=''; _gcd=''; _top=''
if [ "$WT_ON" = 1 ] && [ -n "$git_branch" ]; then
  { read -r _gd; read -r _gcd; read -r _top; } <<EOF
$(git -C "$cwd" rev-parse --git-dir --git-common-dir --show-toplevel 2>/dev/null)
EOF
  if [ -n "$_gd" ] && [ "$_gd" != "$_gcd" ]; then
    [ -z "$git_worktree" ] && git_worktree=${_top##*/}
  else
    git_worktree=''                        # main tree: the payload can't override that
  fi
else
  git_worktree=''
fi

# ---------------------------------------------------------- worktree colour --
# Three tabs, three worktrees, three colours: the directory segment is tinted so
# you can tell which tab you're in without reading a word. The main tree keeps
# the default cyan, so "not in a worktree" stays a distinct signal.
#
# The colour comes from the worktree's *position* in `git worktree list`, not a
# hash of its name. A hash collides: with six tints, three worktrees have a ~44%
# chance that two of them land on the same colour — which defeats the whole
# point. Positions are distinct by construction, so the first six worktrees can
# never clash. (Removing a worktree can shift the ones after it; a recolour is a
# far smaller cost than two tabs that look alike.)
wt_index() {                               # -> _WI (0-based among linked, -1 unknown)
  _WI=-1
  [ -n "$_top" ] || return
  _i=-1                                    # the main tree is listed first; skip it
  while IFS= read -r _wl; do
    case $_wl in
      'worktree '*)
        [ "${_wl#worktree }" = "$_top" ] && { _WI=$_i; return; }
        _i=$(( _i + 1 )) ;;
    esac
  done <<EOF
$(git -C "$cwd" worktree list --porcelain 2>/dev/null)
EOF
}
if [ "$WTC_ON" = 1 ] && [ -n "$git_worktree" ]; then
  wt_index
  if [ "$_WI" -ge 0 ]; then
    case $(( _WI % 6 )) in
      0) C_DIR=$WC0_F; B_DIR=$WC0_B ;;
      1) C_DIR=$WC1_F; B_DIR=$WC1_B ;;
      2) C_DIR=$WC2_F; B_DIR=$WC2_B ;;
      3) C_DIR=$WC3_F; B_DIR=$WC3_B ;;
      4) C_DIR=$WC4_F; B_DIR=$WC4_B ;;
      5) C_DIR=$WC5_F; B_DIR=$WC5_B ;;
    esac
    dir_e
  fi
fi

# The worktree badge exists to say "this is a linked worktree" — a path alone
# can't, since a worktree parked next to its project looks like any other
# directory. Its *name*, though, is already in the path segment, and repeating
# it is noise. So keep the glyph and drop the name whenever the name is
# on the line already (always, under CCLINE_DIR=full).
wt_label=$git_worktree
[ -n "$git_worktree" ] && case $dir in *"$git_worktree"*) wt_label='' ;; esac
# ASCII renders the glyph as the prefix "wt:", which reads as a dropped field
# with nothing after it. No name, no colon.
wt_glyph=$G_WT
[ -z "$wt_label" ] && wt_glyph=${G_WT%:}

# ------------------------------------------------------------------ helpers --
fmt_k() {                                  # 47210 -> _K=47k, 1000000 -> _K=1M, 1500000 -> _K=1.5M
  if [ "$1" -ge 1000000 ]; then
    _d=$(( ($1 % 1000000) / 100000 ))
    if [ "$_d" = 0 ]; then _K="$(( $1 / 1000000 ))M"; else _K="$(( $1 / 1000000 )).${_d}M"; fi
  else
    _K="$(( ($1 + 500) / 1000 ))k"
  fi
}
fmt_reset() {                              # epoch -> _RS=18:42 / "Sal 09:00" ('' if past)
  _RS=''
  [ -z "$1" ] && return
  _ep=${1%.*}
  case $_ep in ''|*[!0-9]*) return ;; esac
  [ "$_ep" -le "$NOW" ] && return          # already reset — the window is hidden then
  epoch_fmt "$_ep" %H:%M; _hm=$_EF
  # Same calendar day -> bare clock; another day (7d window, or a 5h that crosses
  # midnight) -> prefix the locale's short weekday so the time isn't ambiguous.
  epoch_fmt "$_ep" %j
  if [ "$_EF" = "$NOW_JDAY" ]; then _RS=$_hm; return; fi
  # ...except a fresh 7d window ends ~7 days out, landing on today's weekday
  # again: "Cts 19:25" on a Saturday reads as tonight, a week early. When the
  # weekday repeats, the day itself is the only thing that disambiguates.
  epoch_fmt "$_ep" %a
  [ "$_EF" = "$NOW_WDAY" ] && epoch_fmt "$_ep" '%d %b'
  _RS="$_EF $_hm"
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
# Everything that forks (date, for the reset clocks) is worked out once, here;
# the segment builders below only assemble strings.
five_p=''; five_rs=''; seven_p=''; seven_rs=''
if [ "$five_show" = 1 ]; then
  pace "$five_hr" "$five_reset" "$W_5H"; five_p=$_P
  fmt_reset "$five_reset"; five_rs=$_RS
fi
if [ "$seven_show" = 1 ]; then
  pace "$seven_day" "$seven_reset" "$W_7D"; seven_p=$_P
  fmt_reset "$seven_reset"; seven_rs=$_RS
fi
ctx_tt=''                                  # "98k/1M"
if [ -n "$ctx_tok" ] && [ -n "$ctx_max" ] && [ "$ctx_tok" -gt 0 ] 2>/dev/null && [ "$ctx_max" -gt 0 ] 2>/dev/null; then
  fmt_k "$ctx_tok"; _t=$_K; fmt_k "$ctx_max"; ctx_tt="$_t/$_K"
fi

# plain / bars share a " · " separator join; powerline uses bg segments.
SEP="$E_DIM $G_SEP $R"
L=""
add() { if [ -z "$L" ]; then L=$1; else L="$L$SEP$1"; fi; }

[ "$STYLE" = powerline ] && [ "$ASCII" = 1 ] && STYLE=bars   # no arrow glyph in ASCII
SHOW_BAR=0; [ "$STYLE" = bars ] && SHOW_BAR=1   # bars: a gauge on each meter

pr_mark() {                                # -> _PM glyph, _PME its color ('' = no PR)
  _PM=''; _PME=$E_DIM
  [ "$PR_ON" = 1 ] || return
  [ -z "$pr_num" ] && return
  case $pr_state in                        # jq lowercases it for us
    *approv*) _PM=$G_OK;  _PME=$E_GREEN ;;   # approved
    *change*) _PM=$G_NOK; _PME=$E_ORANGE ;;  # changes_requested
  esac
}
pace_e() {                                 # projected% -> _PE (its color)
  if [ "$1" -ge 100 ]; then _PE=$E_RED; else _PE=$E_ORANGE; fi
}
seg_dir() {                                # -> _SEG
  _SEG="$E_DIR$dir$R"
  if [ -n "$git_branch" ]; then
    _SEG="$_SEG$SEP$E_BRANCH$git_branch$R"
    [ "$git_dirty" = 1 ] && _SEG="$_SEG $E_ORANGE$G_DOT$R"
  fi
  [ -n "$git_worktree" ] && _SEG="$_SEG $E_DIM$wt_glyph$wt_label$R"
  if [ "$PR_ON" = 1 ] && [ -n "$pr_num" ]; then
    pr_mark
    _SEG="$_SEG $E_DIM#$pr_num$R"
    [ -n "$_PM" ] && _SEG="$_SEG$_PME$_PM$R"
  fi
}
seg_who() {                                # session name + Remote Control -> _SEG ('' = none)
  _SEG=''
  [ -n "$name" ] && _SEG="$E_NAME$name$R"
  if [ "$rc" = 1 ]; then
    [ -n "$_SEG" ] && _SEG="$_SEG "
    _SEG="$_SEG$G_RC"
  fi
}
seg_model() {                              # one row: "Opus 4.8 ⚡high" -> _SEG
  _SEG=''
  [ -z "$model" ] && return
  _SEG="$E_MODEL$model$R"
  [ -n "$effort" ] && _SEG="$_SEG $E_EFFORT$G_BOLT$effort$R"
}
seg_limit() {                              # label pct pace reset -> _SEG
  pct_e "$2"
  if [ "$SHOW_BAR" = 1 ]; then
    bar "$2" 6; _SEG="$E_DIM$1 $G_BL$_E$_BAR$E_DIM$G_BR $_E$2%$R"
  else
    _SEG="$E_DIM$1 $_E$2%$R"
  fi
  if [ -n "$3" ]; then pace_e "$3"; _SEG="$_SEG $_PE$G_PACE$3%$R"; fi
  if [ -n "$4" ]; then _SEG="$_SEG $E_DIM$G_RST$4$R"; fi
}
seg_ctx() {                                # -> _SEG
  pct_e "$ctx"
  if [ "$SHOW_BAR" = 1 ]; then
    bar "$ctx" 6; _SEG="${E_DIM}ctx $G_BL$_E$_BAR$E_DIM$G_BR $_E$ctx%$R"
  else
    _SEG="${E_DIM}ctx $_E$ctx%$R"
  fi
  if [ -n "$ctx_tt" ]; then _SEG="$_SEG $E_DIM$ctx_tt$R"; fi
}

render_line() {
  seg_dir; add "$_SEG"
  seg_who; [ -n "$_SEG" ] && add "$_SEG"
  seg_model; [ -n "$_SEG" ] && add "$_SEG"
  [ "$five_show" = 1 ] && { seg_limit 5h "$five_hr" "$five_p" "$five_rs"; add "$_SEG"; }
  [ "$seven_show" = 1 ] && { seg_limit 7d "$seven_day" "$seven_p" "$seven_rs"; add "$_SEG"; }
  seg_ctx; add "$_SEG"
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
pl_end() { PL="$PL$R$ESC[${PREV_AF}m$PL_ARR$R"; }
pl_limit() {                               # label pct pace reset
  _t="$1 $2%"
  [ -n "$3" ] && _t="$_t $G_PACE$3%"
  [ -n "$4" ] && _t="$_t $G_RST$4"
  # a window projected past its cap outranks the used-% colour — that's the point
  if [ -n "$3" ] && [ "$3" -ge 100 ]; then _BG=$B_RED; else pct_bg "$2"; fi
  pl_add "$FG_BAR" "$_BG" "$_t"
}
pl_where() {
  _t="$dir"
  [ -n "$git_branch" ] && { _t="$dir $G_SEP $git_branch"; [ "$git_dirty" = 1 ] && _t="$_t $G_DOT"; }
  [ -n "$git_worktree" ] && _t="$_t $wt_glyph$wt_label"
  if [ "$PR_ON" = 1 ] && [ -n "$pr_num" ]; then
    pr_mark; _t="$_t #$pr_num"; [ -n "$_PM" ] && _t="$_t$_PM"
  fi
  pl_add "$FG_BAR" "$B_DIR" "$_t"
  _t=$name
  [ "$rc" = 1 ] && _t="${_t:+$_t }$G_RC"
  [ -n "$_t" ] && pl_add "$FG_BAR" "$B_NAME" "$_t"
  if [ -n "$model" ]; then
    _t="$model"; [ -n "$effort" ] && _t="$model $G_BOLT$effort"
    pl_add "$FG_BAR" "$B_MODEL" "$_t"
  fi
}
pl_meters() {
  [ "$five_show" = 1 ] && pl_limit 5h "$five_hr" "$five_p" "$five_rs"
  [ "$seven_show" = 1 ] && pl_limit 7d "$seven_day" "$seven_p" "$seven_rs"
  _t="ctx $ctx%"; [ -n "$ctx_tt" ] && _t="$_t $ctx_tt"
  pct_bg "$ctx"; pl_add "$FG_BAR" "$_BG" "$_t"
}
render_powerline() {
  pl_where; pl_meters; pl_end
  printf '%s' "$PL"
}

if [ "$STYLE" = powerline ]; then render_powerline; else render_line; fi
