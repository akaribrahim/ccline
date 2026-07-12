#requires -version 5.1
# ccline — a capability-aware status line for Claude Code (PowerShell port).
# https://github.com/akaribrahim/ccline
#
# Reads Claude Code's status JSON on stdin and writes one styled line.
# Adapts to terminal color depth (truecolor / 256 / 16) and glyph support.
#
# Config: env vars override ~/.claude/ccline.conf (KEY=value lines).
#   CCLINE_STYLE  plain | bars | powerline   (default: plain)
#   CCLINE_COLOR  auto | truecolor | 256 | 16
#   CCLINE_ASCII  auto | 1 | 0
#   CCLINE_WARN/HIGH/CRIT  percentage thresholds (50/75/90)

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$raw = [Console]::In.ReadToEnd()
try { $j = $raw | ConvertFrom-Json } catch { $j = $null }

# ---------------------------------------------------------------- config ----
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }

# Read the conf file once into a hashtable; last assignment of a key wins.
$CONF_MAP = @{}
$confPath = if ($env:CCLINE_CONFIG) { $env:CCLINE_CONFIG } else { Join-Path $ClaudeDir 'ccline.conf' }
if (Test-Path $confPath) {
  foreach ($line in [IO.File]::ReadAllLines($confPath)) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
      $CONF_MAP[$Matches[1]] = $Matches[2] -replace '^"(.*)"$','$1'
    }
  }
}
function Cfg($name, $def) {
  $val = [Environment]::GetEnvironmentVariable($name)
  if ($val) { return $val }
  if ($CONF_MAP.ContainsKey($name) -and $CONF_MAP[$name]) { return $CONF_MAP[$name] }
  return $def
}
$STYLE  = Cfg 'CCLINE_STYLE' 'plain'
$FCOLOR = Cfg 'CCLINE_COLOR' 'auto'
$FASCII = Cfg 'CCLINE_ASCII' 'auto'
$WARN = [int](Cfg 'CCLINE_WARN' '50')
$HIGH = [int](Cfg 'CCLINE_HIGH' '75')
$CRIT = [int](Cfg 'CCLINE_CRIT' '90')
$PACE_WARN = [int](Cfg 'CCLINE_PACE_WARN' '90')
$WT_ON   = (Cfg 'CCLINE_WORKTREE' 'auto') -notmatch '^(0|false|no|off)$'
$PACE_ON = (Cfg 'CCLINE_PACE' 'auto')     -notmatch '^(0|false|no|off)$'
$COST_ON = (Cfg 'CCLINE_COST' 'auto')     -notmatch '^(0|false|no|off)$'
$PR_ON   = (Cfg 'CCLINE_PR' 'auto')       -notmatch '^(0|false|no|off)$'

# ---------------------------------------------------- capability detection --
$isWin = $IsWindows -or ($env:OS -eq 'Windows_NT')
switch ($FCOLOR) {
  'truecolor' { $DEPTH = 'truecolor' }
  '256'       { $DEPTH = '256' }
  '16'        { $DEPTH = '16' }
  default {
    if ($env:COLORTERM -in @('truecolor','24bit')) { $DEPTH = 'truecolor' }
    elseif ($env:WT_SESSION) { $DEPTH = 'truecolor' }
    elseif ($env:TERM_PROGRAM -in @('iTerm.app','WezTerm','vscode','ghostty','Hyper','rio','Tabby')) { $DEPTH = 'truecolor' }
    elseif ($env:TERM_PROGRAM -eq 'Apple_Terminal') { $DEPTH = '256' }
    elseif ($env:TERM -match '256') { $DEPTH = '256' }
    elseif ($isWin) { $DEPTH = '256' }      # legacy conhost: play safe
    else { $DEPTH = '16' }
  }
}
switch -regex ($FASCII) {
  '^(1|true|yes|on)$'  { $ASCII = $true; break }
  '^(0|false|no|off)$' { $ASCII = $false; break }
  default {
    # legacy Windows console renders emoji / box glyphs poorly
    if ($isWin -and -not $env:WT_SESSION -and $env:TERM_PROGRAM -ne 'vscode') { $ASCII = $true }
    else { $ASCII = $false }
  }
}

# ------------------------------------------------------------------ palette --
$ESC = [char]27
function E($spec) { return $ESC + '[' + $spec + 'm' }
$NC = E '0'      # reset (named $NC, not $R: PowerShell vars are case-insensitive)
if ($DEPTH -eq 'truecolor') {
  $C_DIR='1;38;2;90;200;210'; $C_DIM='38;2;120;120;120'; $C_MODEL='38;2;175;155;225'
  $C_EFFORT='38;2;210;185;95'; $C_GREEN='38;2;120;200;120'; $C_YELLOW='38;2;235;205;60'
  $C_ORANGE='38;2;230;140;40'; $C_RED='38;2;235;77;75'
  $B_DIR='48;2;38;78;84'; $B_MODEL='48;2;58;50;82'; $B_GREEN='48;2;40;72;40'
  $B_YELLOW='48;2;82;74;26'; $B_ORANGE='48;2;88;54;18'; $B_RED='48;2;88;32;32'
  $B_STALE='48;2;58;58;58'; $B_COST='48;2;48;48;56'; $FG_BAR='38;2;235;235;235'
} elseif ($DEPTH -eq '256') {
  $C_DIR='1;38;5;80'; $C_DIM='38;5;244'; $C_MODEL='38;5;141'; $C_EFFORT='38;5;179'
  $C_GREEN='38;5;114'; $C_YELLOW='38;5;185'; $C_ORANGE='38;5;208'; $C_RED='38;5;203'
  $B_DIR='48;5;23'; $B_MODEL='48;5;60'; $B_GREEN='48;5;22'; $B_YELLOW='48;5;58'
  $B_ORANGE='48;5;94'; $B_RED='48;5;52'; $B_STALE='48;5;238'; $B_COST='48;5;236'; $FG_BAR='38;5;255'
} else {
  $C_DIR='1;36'; $C_DIM='90'; $C_MODEL='35'; $C_EFFORT='33'
  $C_GREEN='32'; $C_YELLOW='33'; $C_ORANGE='33'; $C_RED='31'
  $B_DIR='44'; $B_MODEL='45'; $B_GREEN='42'; $B_YELLOW='43'; $B_ORANGE='43'; $B_RED='41'
  $B_STALE='100'; $B_COST='100'; $FG_BAR='97'
}
$E_DIR=E $C_DIR; $E_DIM=E $C_DIM; $E_MODEL=E $C_MODEL; $E_EFFORT=E $C_EFFORT
$E_GREEN=E $C_GREEN; $E_YELLOW=E $C_YELLOW; $E_ORANGE=E $C_ORANGE; $E_RED=E $C_RED

# ------------------------------------------------------------------- glyphs --
if ($ASCII) {
  $G_SEP='|'; $G_RST='~'; $G_BOLT='*'; $G_DOT='*'; $G_WT='wt:'; $G_DASH='-'
  $G_BARF='#'; $G_BARE='-'; $G_BL='['; $G_BR=']'; $PL_ARR=''
  $G_PACE='^'; $G_OK='+'; $G_NOK='x'
} else {
  $G_SEP=[string][char]0x00B7; $G_RST=[string][char]0x21BA; $G_BOLT=[string][char]0x26A1; $G_DOT=[string][char]0x25CF
  $G_WT=[string][char]0x2442; $G_DASH=[string][char]0x2014
  $G_BARF=[string][char]0x2588; $G_BARE=[string][char]0x2591; $G_BL=[string][char]0x2595; $G_BR=[string][char]0x258F
  $PL_ARR=[string][char]0xE0B0
  $G_PACE=[string][char]0x21C8; $G_OK=[string][char]0x2713; $G_NOK=[string][char]0x2717
}

# -------------------------------------------------------------- parse input --
function Prop($obj, $name) { if ($obj) { return $obj.$name } else { return $null } }
$cwd         = [string](Prop $j 'cwd')
$model       = [string](Prop (Prop $j 'model') 'display_name')
$effort      = [string](Prop (Prop $j 'effort') 'level')
$rl          = Prop $j 'rate_limits'
$five        = Prop (Prop $rl 'five_hour') 'used_percentage'
$five_reset  = Prop (Prop $rl 'five_hour') 'resets_at'
$seven       = Prop (Prop $rl 'seven_day') 'used_percentage'
$seven_reset = Prop (Prop $rl 'seven_day') 'resets_at'
$cw          = Prop $j 'context_window'
$ctx         = Prop $cw 'used_percentage'
$ctx_tok     = Prop $cw 'total_input_tokens'
$ctx_max     = Prop $cw 'context_window_size'
$ws          = Prop $j 'workspace'
$git_worktree = [string](Prop $ws 'git_worktree')
$cost        = Prop $j 'cost'
$cost_cents  = [int][math]::Round(([double](Prop $cost 'total_cost_usd')) * 100)
$lines_add   = [int](Prop $cost 'total_lines_added')
$lines_del   = [int](Prop $cost 'total_lines_removed')
$prj         = Prop $j 'pr'
$pr_num      = [string](Prop $prj 'number')
$pr_state    = ([string](Prop $prj 'review_state')).ToLowerInvariant()

function Iv($x) { if ($x -ne $null -and "$x" -ne '') { return [int][math]::Floor([double]$x) } else { return $null } }
$five = Iv $five; $seven = Iv $seven
$ctx = Iv $ctx; if ($ctx -eq $null) { $ctx = 0 }

# A rate-limit window whose resets_at has passed is a *known-stale* reading:
# rate_limits only refresh when an API response arrives, so once the window
# rolls over the old percentage is simply wrong until the next message. Show a
# dash rather than a number we know to be false.
$NOW = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
function Expired($epoch) {
  if (-not $epoch) { return $false }
  return ([int64][math]::Floor([double]$epoch) -le $NOW)
}
$five_stale  = Expired $five_reset
$seven_stale = Expired $seven_reset

# Pace: "at this burn rate, where does the window end up?" The window length is
# fixed (5h / 7d) and resets_at is its end, so elapsed — and therefore the
# projection — is pure local arithmetic. Early in a window a couple of percent
# projects to absurd numbers, so stay quiet until 15% of it has elapsed, and
# only speak up at PACE_WARN and above.
$W_5H = 18000; $W_7D = 604800
function Pace($used, $reset, $window) {    # -> $null when it should stay quiet
  if (-not $PACE_ON -or -not $reset -or $used -eq $null) { return $null }
  $rem = [int64][math]::Floor([double]$reset) - $NOW
  if ($rem -le 0) { return $null }         # already reset — the stale path owns this
  $el = $window - $rem
  if ($el -le 0) { return $null }
  if ((100 * $el / $window) -lt 15) { return $null }
  if ($used -le 0) { return $null }
  $pj = [int][math]::Floor($used * $window / $el)
  if ($pj -gt 999) { $pj = 999 }
  if ($pj -lt $PACE_WARN) { return $null }
  return $pj
}

if ($cwd) { $dir = Split-Path $cwd -Leaf } else { $dir = '~' }
if (-not $dir) { $dir = '~' }
$model = $model -replace '\(([0-9]+[A-Za-z]*) context\)','$1' -replace '  +',' ' -replace ' +$',''
if (-not $effort) {
  $sp = Join-Path $ClaudeDir 'settings.json'
  if (Test-Path $sp) {
    $hit = Select-String -Path $sp -Pattern '"effortLevel"\s*:\s*"([^"]+)"' | Select-Object -First 1
    if ($hit) { $effort = $hit.Matches[0].Groups[1].Value }
  }
}

# One `git status --porcelain=v2 --branch -uno` yields branch AND dirtiness.
# Every git call is a process spawn, so keep it to one: -uno skips the untracked
# walk (the expensive part) and the header lines carry the branch.
$git_branch = ''; $git_dirty = $false; $oid = ''
if ($cwd -and (Test-Path $cwd)) {
  $st = @(git -C $cwd status --porcelain=v2 --branch -uno 2>$null)
  if ($LASTEXITCODE -eq 0) {
    foreach ($line in $st) {
      if     ($line -like '# branch.head *') { $git_branch = $line.Substring(14).Trim() }
      elseif ($line -like '# branch.oid *')  { $oid = $line.Substring(13).Trim() }
      elseif ($line -like '#*')              { }
      elseif ($line)                         { $git_dirty = $true }
    }
    if ($git_branch -eq '(detached)') {
      if ($oid -and $oid -ne '(initial)') { $git_branch = $oid.Substring(0, [math]::Min(7, $oid.Length)) }
      else { $git_branch = '' }
    }
  }
  # Older Claude Code (no .workspace in the payload): probe git for the worktree.
  if (-not $ws -and $WT_ON -and $git_branch) {
    $rp = @(git -C $cwd rev-parse --git-dir --git-common-dir --show-toplevel 2>$null)
    if ($rp.Count -ge 3 -and $rp[0] -ne $rp[1]) { $git_worktree = Split-Path $rp[2].Trim() -Leaf }
  }
}
if (-not $WT_ON) { $git_worktree = '' }

# ------------------------------------------------------------------ helpers --
function Fmt-K($n) {
  $n = [int64]$n
  if ($n -ge 1000000) {
    return ('{0}.{1}M' -f [int][math]::Floor($n/1000000), [int][math]::Floor(($n%1000000)/100000))
  }
  return ('{0}k' -f [int][math]::Floor(($n + 500)/1000))
}
function Fmt-Reset($epoch) {
  if (-not $epoch) { return '' }
  $e = [int64][math]::Floor([double]$epoch)
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $d = $e - $now
  if ($d -le 0) { return '' }
  $mm=[int][math]::Floor($d/60); $hh=[int][math]::Floor($mm/60); $dd=[int][math]::Floor($hh/24)
  $hh=$hh%24; $mm=$mm%60
  if ($dd -gt 0) { return ('{0}d{1}h' -f $dd,$hh) }
  elseif ($hh -gt 0) { return ('{0}h{1}m' -f $hh,$mm) }
  else { return ('{0}m' -f $mm) }
}
function Pct-E($p) { if ($p -ge $CRIT){$E_RED} elseif ($p -ge $HIGH){$E_ORANGE} elseif ($p -ge $WARN){$E_YELLOW} else {$E_GREEN} }
function Pct-Bg($p){ if ($p -ge $CRIT){$B_RED} elseif ($p -ge $HIGH){$B_ORANGE} elseif ($p -ge $WARN){$B_YELLOW} else {$B_GREEN} }
function Bar($p,$w){ if (-not $w){$w=6}; $f=[int][math]::Floor([double]$p*$w/100); if($f -gt $w){$f=$w}; if($f -lt 0){$f=0}; return ($G_BARF*$f)+($G_BARE*($w-$f)) }
function Af-Of($bg){ (($bg -replace '^48;','38;') -replace '^4([0-7])$','3$1') -replace '^10([0-7])$','9$1' }

# ---------------------------------------------------------------- renderers --
$SEP = "$E_DIM $G_SEP $NC"
function Pr-Mark {                         # -> glyph, '' when there's nothing to say
  if (-not $PR_ON -or -not $pr_num) { return '' }
  if ($pr_state -like '*approv*') { return $G_OK }
  if ($pr_state -like '*change*') { return $G_NOK }
  return ''
}
function Pr-Color {
  if ($pr_state -like '*approv*') { return $E_GREEN }
  if ($pr_state -like '*change*') { return $E_ORANGE }
  return $E_DIM
}
function Pace-E($pj) { if ($pj -ge 100) { $E_RED } else { $E_ORANGE } }
function Seg-Dir {
  $s = "$E_DIR$dir$NC"
  if ($git_branch) { $s += "$SEP$E_DIM$git_branch$NC"; if ($git_dirty) { $s += " $E_ORANGE$G_DOT$NC" } }
  if ($git_worktree) { $s += " $E_DIM$G_WT$git_worktree$NC" }
  if ($PR_ON -and $pr_num) {
    $s += " $E_DIM#$pr_num$NC"
    $m = Pr-Mark
    if ($m) { $s += "$(Pr-Color)$m$NC" }
  }
  return $s
}
function Seg-Cost {                        # -> '' when nothing spent yet
  if (-not $COST_ON) { return '' }
  if ($cost_cents -eq 0 -and $lines_add -eq 0 -and $lines_del -eq 0) { return '' }
  $s = "$E_DIM`$$([int][math]::Floor($cost_cents / 100)).$('{0:d2}' -f ($cost_cents % 100))$NC"
  if ($lines_add -gt 0 -or $lines_del -gt 0) {
    $s += " $E_GREEN+$lines_add$NC$E_DIM/$NC$E_RED-$lines_del$NC"
  }
  return $s
}
function Seg-Model {
  if (-not $model) { return '' }
  $s = "$E_MODEL$model$NC"
  if ($effort) { $s += " $E_EFFORT$G_BOLT$effort$NC" }
  return $s
}
function Seg-Limit($label,$p,$reset,$bars,$stale,$window) {
  if ($stale) { return "$E_DIM$label $G_DASH$NC" }
  $pe = Pct-E $p
  if ($bars) { $s = "$E_DIM$label $G_BL$pe$(Bar $p 6)$E_DIM$G_BR $pe$p%$NC" }
  else       { $s = "$E_DIM$label $pe$p%$NC" }
  $pj = Pace $p $reset $window
  if ($pj) { $s += " $(Pace-E $pj)$G_PACE$pj%$NC" }
  $rs = Fmt-Reset $reset
  if ($rs) { $s += " $E_DIM$G_RST$rs$NC" }
  return $s
}
function Seg-Ctx($bars) {
  $pe = Pct-E $ctx
  if ($bars) { $s = "${E_DIM}ctx $G_BL$pe$(Bar $ctx 6)$E_DIM$G_BR $pe$ctx%$NC" }
  else       { $s = "${E_DIM}ctx $pe$ctx%$NC" }
  if ($ctx_tok -and $ctx_max -and ([int64]$ctx_max -gt 0)) { $s += " $E_DIM$(Fmt-K $ctx_tok)/$(Fmt-K $ctx_max)$NC" }
  return $s
}
function Render-Flat($bars) {
  $segs = @(); $segs += Seg-Dir
  if ($model) { $segs += Seg-Model }
  if ($five  -ne $null) { $segs += (Seg-Limit '5h' $five  $five_reset  $bars $five_stale  $W_5H) }
  if ($seven -ne $null) { $segs += (Seg-Limit '7d' $seven $seven_reset $bars $seven_stale $W_7D) }
  $segs += (Seg-Ctx $bars)
  $c = Seg-Cost
  if ($c) { $segs += $c }
  return ($segs -join $SEP)
}
function Render-Powerline {
  $segs = @()
  $t = $dir
  if ($git_branch) { $t = "$dir $G_SEP $git_branch"; if ($git_dirty) { $t = "$t $G_DOT" } }
  if ($git_worktree) { $t = "$t $G_WT$git_worktree" }
  if ($PR_ON -and $pr_num) { $t = "$t #$pr_num$(Pr-Mark)" }
  $segs += @{ bg=$B_DIR; txt=$t }
  if ($model) { $t = $model; if ($effort) { $t = "$model $G_BOLT$effort" }; $segs += @{ bg=$B_MODEL; txt=$t } }
  foreach ($w in @(
    @{ lbl='5h'; p=$five;  reset=$five_reset;  stale=$five_stale;  win=$W_5H },
    @{ lbl='7d'; p=$seven; reset=$seven_reset; stale=$seven_stale; win=$W_7D })) {
    if ($w.p -eq $null) { continue }
    if ($w.stale) { $segs += @{ bg=$B_STALE; txt="$($w.lbl) $G_DASH" }; continue }
    $t = "$($w.lbl) $($w.p)%"
    $pj = Pace $w.p $w.reset $w.win
    if ($pj) { $t = "$t $G_PACE$pj%" }
    $rs = Fmt-Reset $w.reset
    if ($rs) { $t = "$t $G_RST$rs" }
    # a window projected past its cap outranks the used-% colour — that's the point
    $bg = if ($pj -and $pj -ge 100) { $B_RED } else { Pct-Bg $w.p }
    $segs += @{ bg=$bg; txt=$t }
  }
  $t = "ctx $ctx%"; if ($ctx_tok -and $ctx_max -and ([int64]$ctx_max -gt 0)) { $t = "$t $(Fmt-K $ctx_tok)/$(Fmt-K $ctx_max)" }
  $segs += @{ bg=(Pct-Bg $ctx); txt=$t }
  if ($COST_ON -and ($cost_cents -gt 0 -or $lines_add -gt 0 -or $lines_del -gt 0)) {
    $t = "`$$([int][math]::Floor($cost_cents / 100)).$('{0:d2}' -f ($cost_cents % 100))"
    if ($lines_add -gt 0 -or $lines_del -gt 0) { $t = "$t +$lines_add/-$lines_del" }
    $segs += @{ bg=$B_COST; txt=$t }
  }

  $out = ''; $prevAf = ''
  for ($i = 0; $i -lt $segs.Count; $i++) {
    $bg = $segs[$i].bg; $txt = $segs[$i].txt; $af = Af-Of $bg
    if ($i -eq 0) { $out += (E "$FG_BAR;$bg") + " $txt " }
    else { $out += (E "$prevAf;$bg") + $PL_ARR + (E "$FG_BAR;$bg") + " $txt " }
    $prevAf = $af
  }
  $out += $NC + (E $prevAf) + $PL_ARR + $NC
  return $out
}

switch ($STYLE) {
  'bars'      { $line = Render-Flat $true }
  'powerline' { if ($ASCII) { $line = Render-Flat $true } else { $line = Render-Powerline } }
  default     { $line = Render-Flat $false }
}
[Console]::Out.Write($line)
