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
| Model `·` effort | `Opus 4.8 1M ⚡high` | live model + reasoning-effort level |
| 5-hour limit | `5h 4% ↺4h49m` | session limit used % + reset countdown |
| 7-day limit | `7d 12% ↺3d5h` | weekly limit used % + reset countdown |
| Context | `ctx 5% 47k/1.0M` | context window used % + tokens / size |

Percentages are **color-graded**: green `<50%` → yellow `≥50%` → orange `≥75%` → red `≥90%` (thresholds configurable). Segments that Claude doesn't report (e.g. limits before the first API response) are hidden automatically.

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

The installer copies the status line into `~/.claude/`, writes `~/.claude/ccline.conf`, and points `statusLine.command` in `~/.claude/settings.json` at it — **after backing settings.json up** to `settings.json.ccline-bak`. It never deletes your previous status line script. Open a new Claude Code session to see it.

## Terminal support

| Terminal | Color | Glyphs | Result |
|---|---|---|---|
| iTerm2 · WezTerm · VS Code · Ghostty · Kitty | truecolor | full | full fidelity |
| **Terminal.app** | 256 (no truecolor) | full | colors mapped to 256 |
| Windows Terminal | truecolor | full | full fidelity |
| PowerShell (legacy conhost) | 256 | ASCII fallback | `·→\|  ⚡→*  ↺→~  █→#` |
| Linux `xterm-256color` | 256 | full | good |

Detection is automatic via `$COLORTERM`, `$TERM_PROGRAM`, `$WT_SESSION`, `$TERM`. Override anytime with `CCLINE_COLOR` / `CCLINE_ASCII`.

## Configuration

Edit `~/.claude/ccline.conf` (or set the matching environment variable — **env wins over the file**):

| Key | Values | Default | Meaning |
|---|---|---|---|
| `CCLINE_STYLE` | `plain` `bars` `powerline` | `plain` | visual style |
| `CCLINE_COLOR` | `auto` `truecolor` `256` `16` | `auto` | force color depth |
| `CCLINE_ASCII` | `auto` `1` `0` | `auto` | force ASCII / Unicode glyphs |
| `CCLINE_WARN` | 0–100 | `50` | yellow threshold |
| `CCLINE_HIGH` | 0–100 | `75` | orange threshold |
| `CCLINE_CRIT` | 0–100 | `90` | red threshold |

See [`ccline.conf.example`](ccline.conf.example).

## How it works

Claude Code feeds the configured `statusLine.command` a JSON blob on stdin (cwd, model, `effort.level`, `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`, `context_window.*`). ccline parses it (`jq` on POSIX, `ConvertFrom-Json` on Windows), formats one line, and writes it to stdout. It runs once per refresh — fast and dependency-light.

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
