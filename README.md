# ccline

A capability-aware **status line for [Claude Code](https://claude.com/claude-code)** — shows where you are (path, branch, worktree), your model, reasoning effort, **5-hour & 7-day usage limits with the time each one resets**, and context-window fill, color-graded so it stays calm when you have headroom and turns red as you approach a limit.

It adapts to whatever your terminal supports: 24-bit color where available, 256-color on Terminal.app, 16-color elsewhere, and ASCII glyphs on legacy consoles. One script for macOS/Linux (`sh` + `jq`), a matching one for Windows (PowerShell).

```
~/dev/my-project · main · Opus 4.8 1M ⚡high · 5h 4% ↺18:42 · 7d 12% ↺Sun 09:15 · ctx 5% 47k/1.0M
```

## What each segment means

| Segment | Example | Source |
|---|---|---|
| Directory `·` git branch | `~/dev/my-project · main ●` | cwd (`$HOME` folded to `~`) + git (● = uncommitted changes). The branch shares the directory's colour — see [Where am I?](#where-am-i) |
| Git worktree | `⑂` | marks a linked worktree — and the directory is **tinted per worktree**, see [Telling worktrees apart](#telling-worktrees-apart) |
| Pull request | `#42 ✓` | PR for the branch: `✓` approved, `✗` changes requested |
| Model `·` effort | `Opus 4.8 1M ⚡high` | live model + reasoning-effort level |
| 5-hour limit | `5h 4% ↺18:42` | session limit used % + the local time it resets |
| 7-day limit | `7d 12% ↺Sun 09:15` | weekly limit used % + the local time it resets |
| **Burn-rate warning** | `⇈173%` | where the window lands **at this rate** — see [Pace](#pace) |
| Context | `ctx 5% 47k/1.0M` | context window used % + tokens / size |

Percentages are **color-graded**: green `<50%` → yellow `≥50%` → orange `≥75%` → red `≥90%` (thresholds configurable). Segments that Claude doesn't report (e.g. limits before the first API response) are hidden automatically.

A limit reads `5h —` when its window has already reset but no new usage figure has arrived yet — see [Freshness](#freshness).

**Resets are a wall clock, not a countdown.** `↺18:42` is a time you can plan around — "after lunch", "before the standup" — where `↺4h49m` makes you do the arithmetic yourself, every time you look. A reset landing on another day gets your locale's short weekday in front of it (`↺Sun 09:15`); and because a fresh 7-day window ends on *today's* weekday one week out — where `↺Sun 09:15` on a Sunday reads as tonight, a week early — a repeated weekday is dated instead: `↺14 Jun 09:15`.

## Where am I?

The directory segment is the **whole path**, `$HOME` folded to `~`, and the branch next to it is **never dim**.

That is a deliberate trade of width for an answer. A basename stops being an answer the moment worktrees are in play: Claude Code parks them at `<project>/.claude/worktrees/<name>`, so the basename *is* the worktree's name and the project's name appears nowhere on the line. Run agents across three projects and every tab reads alike:

```
support-tickets-2026-08 · fix/p1-small-hardening ⑂support-tickets-2026-08   ← which project?
~/Projects/makinego/makinego-src/.claude/worktrees/support-tickets-2026-08 · fix/p1-small-hardening ⑂
```

The path answers *which project*, *which worktree*, and *where on disk to go* in one read — and it keeps answering when the cwd is somewhere below the worktree root (`.../support-tickets-2026-08/api`), where a basename says only `api`.

The `⑂` badge drops its name once the path already carries it. The glyph stays, because it's the part the path can't say: a worktree parked beside its project looks like any other directory.

The branch takes the directory's colour minus the bold, so the two read as one unit and the branch never sits in the dim grey used for numbers you glance past. Inside a worktree that colour is the worktree's tint (below), so the branch is tinted with it.

Prefer the old basename? `CCLINE_DIR=name`. The `⑂` badge then carries the worktree's name again, since nothing else on the line does.

## Pace

`5h 30%` tells you where you *are*. It doesn't tell you the thing you actually want to know: **will I hit the wall before this window resets?**

So when you're burning quota faster than the window refills, ccline says so:

```
5h 30% ⇈173% ↺18:42
```

Read it as: *30% used, and at this rate you'd end the window at 173% — i.e. you run out well before the reset.* The window length is fixed (5 hours, 7 days) and `resets_at` is its end, so elapsed time — and therefore the projection — is plain local arithmetic: `used% ÷ elapsed-fraction`. No history file, no extra process, nothing to configure.

It stays quiet when there's nothing to say. Under `CCLINE_PACE_WARN` (default 90%) no marker appears at all — the absence *is* the good news. It also holds its tongue for the first 15% of a window, where a couple of percent would project to nonsense. Orange at 90–99%, red at 100%+ (in `powerline` the whole segment goes red, outranking the used-% color).

Set `CCLINE_PACE=0` to turn it off.

## Telling worktrees apart

If you keep a terminal tab per worktree, the tabs look alike — same project, same status line shape. ccline gives you three independent signals, and one of them you can read without reading at all:

```
~/dev/my-proj/.claude/worktrees/wt-auth · feat-auth ⑂   ← directory + branch tinted green
~/dev/my-proj/.claude/worktrees/wt-perf · feat-perf ⑂   ← tinted violet
~/dev/my-proj/.claude/worktrees/wt-docs · feat-docs ⑂   ← tinted amber
~/dev/my-proj · main                                    ← main tree keeps the default cyan
```

The tint comes from the worktree's **position in `git worktree list`**, not a hash of its name. That matters: with six tints, three worktrees have a ~44% chance that two of them collide on the same colour — which would defeat the point. Positions are distinct by construction, so the first six worktrees can never clash. (Removing a worktree can shift the colours of the ones after it. A recolour is a much smaller cost than two tabs that look identical.)

The main tree is never tinted, so "no colour" stays a meaningful signal: *you're not in a worktree*. Turn the tinting off with `CCLINE_WT_COLOR=0`, or drop the whole worktree segment with `CCLINE_WORKTREE=0`.

## Styles

Pick with `CCLINE_STYLE` (config file or env var):

**plain** — clean, separator-joined
```
~/dev/my-project · main · Opus 4.8 1M ⚡high · 5h 4% ↺18:42 · 7d 12% ↺Sun 09:15 · ctx 5% 47k/1.0M
```

**bars** — adds a mini gauge per limit
```
~/dev/my-project · main · Opus 4.8 1M ⚡high · 5h ▕░░░░░░▏ 4% ↺18:42 · 7d ▕█░░░░░▏ 12% ↺Sun 09:15 · ctx ▕░░░░░░▏ 5% 47k/1.0M
```

**powerline** — chained background segments ( arrows; needs a Nerd Font or iTerm's "Use built-in Powerline glyphs")
```
 ~/dev/my-project · main  Opus 4.8 1M ⚡high  5h 4%  7d 12%  ctx 5% 47k/1.0M 
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

### For coding agents

If someone hands you this repo and asks you to set it up for them, this is the whole job. It is idempotent — re-running it is safe.

```sh
# 1. jq is required (macOS/Linux). Stop and ask the user to install it if missing.
command -v jq >/dev/null || echo "needs jq:  brew install jq   |   sudo apt-get install -y jq"

# 2. Install. Backs settings.json up to settings.json.ccline-bak (and never
#    overwrites an existing backup), never deletes their old status line script.
curl -fsSL https://raw.githubusercontent.com/akaribrahim/ccline/main/install.sh | bash

# 3. Verify the config landed — expect type/command/refreshInterval.
jq '.statusLine' ~/.claude/settings.json

# 4. Verify it actually renders, by feeding it a sample of Claude Code's payload.
printf '{"cwd":"%s","model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":12,"total_input_tokens":24000,"context_window_size":200000}}' "$PWD" \
  | bash ~/.claude/ccline.sh; echo
```

Windows is the same shape: `irm https://raw.githubusercontent.com/akaribrahim/ccline/main/install.ps1 | iex`, then verify with `~/.claude/ccline.ps1`.

Then **tell the user the two things you cannot do for them**:

1. **Restart Claude Code.** `statusLine` is read at session start, so the line will not appear in the session you just ran this from. This is the step agents most often forget to mention, and it makes a correct install look broken.
2. Optionally pick a style — `CCLINE_STYLE=plain|bars|powerline` in `~/.claude/ccline.conf`.

Two things not to do: don't hand-edit `statusLine` in `settings.json` (the installer writes it *and* keeps the pre-ccline backup — an ad-hoc edit loses that), and don't report success on step 2 alone. Step 4 is what proves it works; a status line that errors prints nothing and fails silently.

To undo: `bash uninstall.sh`, or restore `~/.claude/settings.json.ccline-bak`.

## Terminal support

| Terminal | Color | Glyphs | Result |
|---|---|---|---|
| iTerm2 · WezTerm · VS Code · Ghostty · Kitty | truecolor | full | full fidelity |
| **Terminal.app** | 256 (no truecolor) | full | colors mapped to 256 |
| Windows Terminal | truecolor | full | full fidelity |
| PowerShell (legacy conhost) | 256 | ASCII fallback | `·→\|  ⚡→*  ↺→~  █→#  ⑂→wt` |
| Linux `xterm-256color` | 256 | full | good |

Detection is automatic via `$COLORTERM`, `$TERM_PROGRAM`, `$WT_SESSION`, `$TERM`. Override anytime with `CCLINE_COLOR` / `CCLINE_ASCII`.

## Configuration

Create or edit `~/.claude/ccline.conf` (or set the matching environment variable — **env wins over the file**):

| Key | Values | Default | Meaning |
|---|---|---|---|
| `CCLINE_STYLE` | `plain` `bars` `powerline` | `plain` | visual style |
| `CCLINE_COLOR` | `auto` `truecolor` `256` `16` | `auto` | force color depth |
| `CCLINE_ASCII` | `auto` `1` `0` | `auto` | force ASCII / Unicode glyphs |
| `CCLINE_DIR` | `full` `name` | `full` | whole path (`~/dev/proj`) or basename (`proj`) ([why](#where-am-i)) |
| `CCLINE_WORKTREE` | `auto` `0` | `auto` | `⑂` when in a linked worktree; `0` hides it |
| `CCLINE_WT_COLOR` | `auto` `0` | `auto` | tint the directory per worktree ([why](#telling-worktrees-apart)) |
| `CCLINE_PACE` | `auto` `0` | `auto` | burn-rate projection on the limits ([Pace](#pace)) |
| `CCLINE_PACE_WARN` | 0–999 | `90` | projected % at which the `⇈` marker appears |
| `CCLINE_PR` | `auto` `0` | `auto` | `#42 ✓` pull-request segment |
| `CCLINE_WARN` | 0–100 | `50` | yellow threshold |
| `CCLINE_HIGH` | 0–100 | `75` | orange threshold |
| `CCLINE_CRIT` | 0–100 | `90` | red threshold |

See [`ccline.conf.example`](ccline.conf.example).

## How it works

Claude Code feeds the configured `statusLine.command` a JSON blob on stdin (`cwd`, `model`, `effort.level`, `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`, `context_window.*`, `workspace.git_worktree`, `pr.{number,review_state}`). ccline parses it (`jq` on POSIX, `ConvertFrom-Json` on Windows), formats one line, and writes it to stdout.

It is built to be cheap to re-run: **one** `jq` call, **two** `git` calls (`status --porcelain=v2 --branch -uno` for branch + dirtiness in one shot, `rev-parse` to tell a linked worktree from the main tree), and no subshells in the render path — tens of milliseconds. A third `git` call, `worktree list`, runs only inside a worktree, to pick the tint. The cost is dominated by `git status`, so it scales with the tree, not with ccline: `-uno` is there because skipping the untracked walk is what keeps a large repo cheap. That matters, because Claude Code re-runs the command often and *slow scripts block the status line from updating*.

## Freshness

Different segments go stale in different ways, and it's worth knowing which is which.

Claude Code re-runs the status line **on conversation events** — each new assistant message, after `/compact`, on permission-mode and vim-mode changes — debounced at 300 ms. Left at that, anything that changes while you are *not* typing freezes: sit idle past a window's reset and the line still shows the spent percentage of a window that has already rolled over, and a branch you switched in another terminal never lands.

So the installer also sets **`refreshInterval: 10`** in `settings.json`, which re-runs the command every 10 seconds on top of those events:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/ccline.sh",
  "refreshInterval": 10
}
```

That lets the git segment notice a branch you switched in another terminal — or one a background subagent switched under you — and lets a window that resets while you are idle flip to `5h —` on its own rather than sitting on a figure that is no longer true. (The reset time itself is a wall clock, so it doesn't need a timer to stay honest; the pace projection does, since it divides by elapsed time.) Set it to any value ≥ 1 (or drop the key to go back to events-only).

**Usage percentages are the exception.** ccline can't compute them — it can only print what Claude Code puts in the payload, and `rate_limits` lands there when Claude Code has fresh figures (with an API response, and a beat after a `--resume` starts). The number is a snapshot; it does not tick upward on its own between messages.

That leaves two moments where a percentage would be a lie, and both render as a dash — *the slot is here, the value isn't*:

```
5h —          we don't know yet
```

- **A fresh session**, before your first message. The figures simply haven't arrived. Holding the slot open keeps the line from reshuffling the moment they do.
- **A window that has already reset** while you sat idle. The old percentage is now *known* to be wrong, so we stop showing it; the real figure lands with your next message.

A dash that never resolves would be its own lie, though: `rate_limits` never arrives at all on API-key accounts. But a single payload can't tell the two apart — a resumed session already carries its token counts while its limits are still missing. So ccline answers the question the only way it can: *have we ever seen limits here?* The first sighting is remembered (`~/.claude/.ccline-limits-seen`), and from then on an absent limit means "not here yet" rather than "not for you".

| Segment | Refreshed by |
|---|---|
| Directory, git branch/dirty, worktree | every run — so every 10 s with `refreshInterval` |
| Reset times (`↺18:42`), pace (`⇈173%`) | every run — computed locally from `resets_at` |
| Model, effort, context, PR | every event — they only change when the conversation does |
| **5h / 7d percentages** | **Claude Code, not us** — they refresh when it has new figures, which is not on our timer |

## Requirements

- **macOS/Linux:** `sh`, `git`, and **`jq`** (`brew install jq` / `apt-get install jq`).
- **Windows:** PowerShell 5.1+ (built in) or PowerShell 7+. `git` optional (enables the branch, worktree, and tint).

## Uninstall

```sh
bash uninstall.sh        # macOS/Linux
./uninstall.ps1          # Windows
```

Restores `settings.json` from the backup (or removes just the `statusLine` key) and deletes `ccline.sh` / `ccline.conf`.

## License

[MIT](LICENSE)
