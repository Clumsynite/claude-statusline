---
name: install
description: Install, update, check or remove the three-line claude-statusline status line (repo, worktree, branch, git state, handoff age, model; context tokens and 5-hour/weekly plan usage; session name and ID).
argument-hint: "[status | uninstall]"
disable-model-invocation: true
allowed-tools: Bash(sh "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" *)
---

# Install the status line

Arguments: $ARGUMENTS

## Current state (captured when you invoked this)

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" status`

## Steps

1. If the arguments are `status`, summarise the state above in a few lines and stop.
2. If the arguments are `uninstall`, run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" uninstall`, report what it printed, and stop.
3. Otherwise install or update:
   - If `jq` is missing, tell the user to install it and stop.
   - If `installed: no` and `statusLine` is not `null`, show the user that command and ask whether to replace it. Say it is saved and `/statusline:install uninstall` restores it. Only after they agree, run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" install --force`.
   - Otherwise run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" install`.
4. Report in a few lines: what changed, the config file path, and that it shows from the next status line refresh. Mention the options in the config file: `SESSION_ID`, `GIT`, `HANDOFF`, `HANDOFF_HINT_K`, `ADB` (off by default; turn it on for Android work), `RESET_5H_FROM` and `SNAPSHOT`.
5. Suggest the companion plugins the status line works with, for each one the state shows as `not installed`:
   - **handoff** (https://github.com/Clumsynite/claude-handoff) writes the notes behind `handoff 2h` on line 1, and is what the red `→ /handoff:handoff` hint (past 700k context tokens) asks you to run. Install:
     ```
     /plugin marketplace add Clumsynite/claude-handoff
     /plugin install handoff@clumsyknight
     ```
     Without it, the hint still shows but the command won't exist. The user can set `HANDOFF_HINT` to something else, e.g. `/compact`.
   - **usage-guard** (https://github.com/Clumsynite/claude-usage-guard) pauses Claude when 5-hour or weekly usage runs hot. It reads the snapshot this status line writes to `SNAPSHOT`. Install:
     ```
     /plugin marketplace add Clumsynite/claude-usage-guard
     /plugin install usage-guard@clumsyknight-usage-guard
     ```
   If usage-guard is installed and the state shows its `snapshot_path`, check that the config's `SNAPSHOT` is the same file (install sets it on first run; an existing config is never overwritten).
