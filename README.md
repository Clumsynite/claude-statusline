# statusline

[![CI](https://github.com/Clumsynite/claude-statusline/actions/workflows/ci.yml/badge.svg)](https://github.com/Clumsynite/claude-statusline/actions/workflows/ci.yml)
[![Release](https://github.com/Clumsynite/claude-statusline/actions/workflows/release.yml/badge.svg)](https://github.com/Clumsynite/claude-statusline/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/badge/release-v0.1.0-blue)](https://github.com/Clumsynite/claude-statusline/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A two-line status line for Claude Code, packaged as a plugin with an install command.

```
my-app (feat/login) * ↑2 · handoff 2h | Opus | 1aaf2147
ctx 72% · 724k → /handoff:handoff | 5h 55% (resets 05:38, in 2h13m) | 7d 91% (resets Wed 08:25, in 4d5h)
```

**Line 1**
- Repo folder (cyan) and branch (magenta), or the short SHA on a detached HEAD.
- `*` (yellow): tracked files have uncommitted changes. `↑N`: N commits not pushed to the upstream yet.
- `handoff 2h`: age of the note for this repo and branch written by the [handoff](https://github.com/Clumsynite/claude-handoff) plugin.
- `📱`: `adb devices` lists a connected Android device (off by default).
- Model, then the session ID (first 8 characters by default, or the full ID to copy into other sessions).

**Line 2**
- `ctx`: context used, as a percentage and in tokens. Past 700k tokens a red `→ /handoff:handoff` suggests writing a handoff note and starting fresh.
- `5h` and `7d`: plan usage, green under 50%, yellow under 80%, red from 80%. The weekly reset always shows with the time left; the 5-hour reset shows once usage reaches 50%.

It also writes a small plan usage snapshot, so [usage-guard](https://github.com/Clumsynite/claude-usage-guard) works with no extra setup.

## Install

A plugin can't set a status line by itself, so the plugin ships an install command:

```
/plugin marketplace add Clumsynite/claude-statusline
/plugin install statusline@clumsyknight-statusline
/statusline:install
```

`/statusline:install` copies the script to `~/.claude/statusline/statusline.sh`, writes a config file next to it, and sets `statusLine` in `~/.claude/settings.json` (with `refreshInterval: 60`). If you already have a status line, it shows you the command and asks before replacing it. The old one is saved, and `settings.json` is backed up once to `settings.json.bak-statusline`.

- `/statusline:install status`: what's installed, and which companion plugins are present.
- `/statusline:install uninstall`: restores the status line you had before (or removes `statusLine`). The files in `~/.claude/statusline/` are kept.

After a plugin update, a silent SessionStart hook refreshes the installed copy of the script. Customise it through the config file, not by editing the script, which gets overwritten.

Needs `jq` and a POSIX `sh`. `git` and `adb` are optional. `CLAUDE_CONFIG_DIR` is honoured.

## Configure

Edit `~/.claude/statusline/config` (sh syntax). Changes show on the next refresh.

| Option | Default | Meaning |
|---|---|---|
| `SESSION_ID` | `short` | `full`, `short` (first 8 characters) or `off` |
| `GIT` | `on` | Branch, `*` and `↑N` |
| `HANDOFF` | `on` | Handoff note age |
| `HANDOFF_HINT_K` | `700` | Show the hint past this many thousand context tokens; `0` turns it off |
| `HANDOFF_HINT` | `/handoff:handoff` | What the hint suggests, e.g. `/compact` if you don't use handoff |
| `ADB` | `off` | `📱` when an Android device is connected (checked in the background every 30 seconds) |
| `RESET_5H_FROM` | `50` | Show the 5-hour reset time from this usage %; `0` always shows it |
| `SNAPSHOT` | `$HOME/.cache/claude-usage-guard/usage.json` | Where to write the plan usage snapshot; empty turns it off |

On first install, if usage-guard is installed with a custom `snapshot_path`, `SNAPSHOT` is set to match.

## Works well with

- [handoff](https://github.com/Clumsynite/claude-handoff): structured handoff notes between sessions. It provides `/handoff:handoff`, which the context hint points to, and the notes behind `handoff 2h`.
  ```
  /plugin marketplace add Clumsynite/claude-handoff
  /plugin install handoff@clumsyknight
  ```
- [usage-guard](https://github.com/Clumsynite/claude-usage-guard): pauses Claude when 5-hour or weekly usage runs hot. It reads the snapshot this status line writes.
  ```
  /plugin marketplace add Clumsynite/claude-usage-guard
  /plugin install usage-guard@clumsyknight-usage-guard
  ```

## Token cost

Zero. The status line runs outside the conversation, the SessionStart hook prints nothing, and `/statusline:install` only loads when you run it.

## Development

```
sh tests/run.sh                      # also: TEST_SH=dash sh tests/run.sh
shellcheck -s sh scripts/*.sh tests/run.sh
claude plugin validate --strict .claude-plugin/plugin.json
```

Releases are built by CI: bump `version` in `.claude-plugin/plugin.json` (and the README badge) and push to `main`.

## License

MIT
