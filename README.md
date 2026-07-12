# ccline

A capability-aware **status line for [Claude Code](https://claude.com/claude-code)** — shows your model, reasoning effort, **5-hour & 7-day usage limits with reset countdowns**, and context-window fill, color-graded so it stays calm when you have headroom and turns red as you approach a limit.

It adapts to whatever your terminal supports: 24-bit color where available, 256-color on Terminal.app, 16-color elsewhere, and ASCII glyphs on legacy consoles. One script for macOS/Linux (`sh` + `jq`), a matching one for Windows (PowerShell).

```
my-project · Opus 4.8 1M ⚡high · 5h 4% ↺4h49m · 7d 12% ↺3d5h · ctx 5% 47k/1.0M
```

## What each segment means

| Segment | Example | Source |
|---|---|---|
| Directory `·` git branch | `my-project · main ●` | cwd + git (● = uncommitted changes) |
| Git worktree | `⑂feature` | shown only inside a linked worktree — and the directory is **tinted per worktree**, see [Telling worktrees apart](#telling-worktrees-apart) |
| Pull request | `#42 ✓` | PR for the branch: `✓` approved, `✗` changes requested |
| Model `·` effort | `Opus 4.8 1M ⚡high` | live model + reasoning-effort level |
| 5-hour limit | `5h 4% ↺4h49m` | session limit used % + reset countdown |
| 7-day limit | `7d 12% ↺3d5h` | weekly limit used % + reset countdown |
| **Burn-rate warning** | `⇈173%` | where the window lands **at this rate** — see [Pace](#pace) |
| Context | `ctx 5% 47k/1.0M` | context window used % + tokens / size |
| Session cost `·` edits | `$1.24 edits +128/-34` | cost so far + lines this **session** added/removed (not the working tree's diff) |

Percentages are **color-graded**: green `<50%` → yellow `≥50%` → orange `≥75%` → red `≥90%` (thresholds configurable). Segments that Claude doesn't report (e.g. limits before the first API response) are hidden automatically.

A limit reads `5h —` when its window has already reset but no new usage figure has arrived yet — see [Freshness](#freshness).

## Pace

`5h 30%` tells you where you *are*. It doesn't tell you the thing you actually want to know: **will I hit the wall before this window resets?**

So when you're burning quota faster than the window refills, ccline says so:

```
5h 30% ⇈173% ↺4h8m
```

Read it as: *30% used, and at this rate you'd end the window at 173% — i.e. you run out well before the reset.* The window length is fixed (5 hours, 7 days) and `resets_at` is its end, so elapsed time — and therefore the projection — is plain local arithmetic: `used% ÷ elapsed-fraction`. No history file, no extra process, nothing to configure.

It stays quiet when there's nothing to say. Under `CCLINE_PACE_WARN` (default 90%) no marker appears at all — the absence *is* the good news. It also holds its tongue for the first 15% of a window, where a couple of percent would project to nonsense. Orange at 90–99%, red at 100%+ (in `powerline` the whole segment goes red, outranking the used-% color).

Set `CCLINE_PACE=0` to turn it off.

## Telling worktrees apart

If you keep a terminal tab per worktree, the tabs look alike — same project, same status line shape. ccline gives you three independent signals, and one of them you can read without reading at all:

```
wt-auth  · feat-auth  ⑂wt-auth      ← directory tinted green
wt-perf  · feat-perf  ⑂wt-perf      ← tinted violet
wt-docs  · feat-docs  ⑂wt-docs      ← tinted amber
my-proj  · main                     ← main tree keeps the default cyan
```

The tint comes from the worktree's **position in `git worktree list`**, not a hash of its name. That matters: with six tints, three worktrees have a ~44% chance that two of them collide on the same colour — which would defeat the point. Positions are distinct by construction, so the first six worktrees can never clash. (Removing a worktree can shift the colours of the ones after it. A recolour is a much smaller cost than two tabs that look identical.)

The main tree is never tinted, so "no colour" stays a meaningful signal: *you're not in a worktree*. Turn the tinting off with `CCLINE_WT_COLOR=0`, or drop the whole worktree segment with `CCLINE_WORKTREE=0`.

## Styles

Pick with `CCLINE_STYLE` (config file or env var):

**plain** — clean, separator-joined
```
my-project · Opus 4.8 1M ⚡high · 5h 4% ↺4h49m · 7d 12% ↺3d5h · ctx 5% 47k/1.0M
```

**bars** — adds a mini gauge per limit
```
my-project · Opus 4.8 1M ⚡high · 5h ▕░░░░░░▏ 4% ↺4h49m · 7d ▕█░░░░░▏ 12% ↺3d5h · ctx ▕░░░░░░▏ 5% 47k/1.0M
```

**powerline** — chained background segments ( arrows; needs a Nerd Font or iTerm's "Use built-in Powerline glyphs")
```
 my-project  Opus 4.8 1M ⚡high  5h 4%  7d 12%  ctx 5% 47k/1.0M 
```

## Install

### macOS / Linux

```sh
curl -fsSL https://raw.githubusercontent.com/akaribrahim/ccline/main/install.sh | bash
```

Defaults to the `plain` style; change it later in `~/.claude/ccline.conf`, or install from a clone with `bash install.sh bars` to pick one up front.

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/akaribrahim/ccline/main/install.ps1 | iex
```

### From a clone (works while the repo is private)

```sh
git clone https://github.com/akaribrahim/ccline.git && cd ccline
bash install.sh            # or: bash install.sh powerline
# Windows:  ./install.ps1 -Style powerline
```

The installer copies the status line into `~/.claude/` and points `statusLine.command` in `~/.claude/settings.json` at it — **after backing settings.json up** to `settings.json.ccline-bak`. It also sets `statusLine.refreshInterval` to `10` (see [Freshness](#freshness)); export `CCLINE_REFRESH` before running the installer to choose another value. If you pass a style (`bash install.sh bars`), it writes that choice to `~/.claude/ccline.conf`; with no argument it defaults to `plain` and writes no conf file. It never deletes your previous status line script. Open a new Claude Code session to see it.

## Terminal support

| Terminal | Color | Glyphs | Result |
|---|---|---|---|
| iTerm2 · WezTerm · VS Code · Ghostty · Kitty | truecolor | full | full fidelity |
| **Terminal.app** | 256 (no truecolor) | full | colors mapped to 256 |
| Windows Terminal | truecolor | full | full fidelity |
| PowerShell (legacy conhost) | 256 | ASCII fallback | `·→\|  ⚡→*  ↺→~  █→#  ⑂→wt:` |
| Linux `xterm-256color` | 256 | full | good |

Detection is automatic via `$COLORTERM`, `$TERM_PROGRAM`, `$WT_SESSION`, `$TERM`. Override anytime with `CCLINE_COLOR` / `CCLINE_ASCII`.

## Configuration

Create or edit `~/.claude/ccline.conf` (or set the matching environment variable — **env wins over the file**):

| Key | Values | Default | Meaning |
|---|---|---|---|
| `CCLINE_STYLE` | `plain` `bars` `powerline` | `plain` | visual style |
| `CCLINE_COLOR` | `auto` `truecolor` `256` `16` | `auto` | force color depth |
| `CCLINE_ASCII` | `auto` `1` `0` | `auto` | force ASCII / Unicode glyphs |
| `CCLINE_WORKTREE` | `auto` `0` | `auto` | `⑂name` when in a linked worktree; `0` hides it |
| `CCLINE_WT_COLOR` | `auto` `0` | `auto` | tint the directory per worktree ([why](#telling-worktrees-apart)) |
| `CCLINE_PACE` | `auto` `0` | `auto` | burn-rate projection on the limits ([Pace](#pace)) |
| `CCLINE_PACE_WARN` | 0–999 | `90` | projected % at which the `⇈` marker appears |
| `CCLINE_PR` | `auto` `0` | `auto` | `#42 ✓` pull-request segment |
| `CCLINE_COST` | `auto` `0` | `auto` | `$1.24 +128/-34` session cost + diff |
| `CCLINE_WARN` | 0–100 | `50` | yellow threshold |
| `CCLINE_HIGH` | 0–100 | `75` | orange threshold |
| `CCLINE_CRIT` | 0–100 | `90` | red threshold |

See [`ccline.conf.example`](ccline.conf.example).

## How it works

Claude Code feeds the configured `statusLine.command` a JSON blob on stdin (cwd, model, `effort.level`, `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`, `context_window.*`, `workspace.git_worktree`). ccline parses it (`jq` on POSIX, `ConvertFrom-Json` on Windows), formats one line, and writes it to stdout.

It is built to be cheap to re-run: one `jq` call, one `git` call, and no subshells in the render path — about **20 ms** per line. That matters, because Claude Code re-runs the command often and *slow scripts block the status line from updating*.

## Freshness

Different segments go stale in different ways, and it's worth knowing which is which.

Claude Code re-runs the status line **on conversation events** — each new assistant message, after `/compact`, on permission-mode and vim-mode changes — debounced at 300 ms. Left at that, anything time-based freezes between messages: sit idle for twenty minutes and the countdown still claims `↺2h13m`.

So the installer also sets **`refreshInterval: 10`** in `settings.json`, which re-runs the command every 10 seconds on top of those events:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/ccline.sh",
  "refreshInterval": 10
}
```

That keeps the reset countdowns ticking and lets the git segment notice a branch you switched in another terminal — or one a background subagent switched under you. Set it to any value ≥ 1 (or drop the key to go back to events-only).

**Usage percentages are the exception.** `rate_limits` only arrives with an API response, so no timer can refresh it — the number is a snapshot from your last message, and it does not tick upward on its own.

That leaves two moments where a percentage would be a lie, and both render as a dash — *the slot is here, the value isn't*:

```
5h —          we don't know yet
```

- **A fresh session**, before your first message. The figures simply haven't arrived. Holding the slot open keeps the line from reshuffling the moment they do.
- **A window that has already reset** while you sat idle. The old percentage is now *known* to be wrong, so we stop showing it; the real figure lands with your next message.

A dash that never resolves would be its own lie, though: `rate_limits` never arrives at all on API-key accounts. So once a response *has* landed (we have cost or token counts) and the limits are still missing, ccline concludes this account doesn't have them and drops both segments for good.

| Segment | Refreshed by |
|---|---|
| Directory, git branch/dirty, worktree | every run — so every 10 s with `refreshInterval` |
| Reset countdowns (`↺2h13m`), pace (`⇈173%`) | every run — computed locally from `resets_at` |
| Model, effort, context, cost, PR | every event — they only change when the conversation does |
| **5h / 7d percentages** | **API responses only** — i.e. when you send a message |

## Requirements

- **macOS/Linux:** `sh`, `git`, and **`jq`** (`brew install jq` / `apt-get install jq`).
- **Windows:** PowerShell 5.1+ (built in) or PowerShell 7+. `git` optional (enables the branch segment).

## Uninstall

```sh
bash uninstall.sh        # macOS/Linux
./uninstall.ps1          # Windows
```

Restores `settings.json` from the backup (or removes just the `statusLine` key) and deletes `ccline.sh` / `ccline.conf`.

## License

[MIT](LICENSE)
