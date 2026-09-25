#!/bin/sh
# Self-contained tests for scripts/statusline.sh and scripts/install.sh. Uses a throwaway HOME
# and git repos; touches nothing else. Usage: sh tests/run.sh
# Set TEST_SH=dash (or bash) to run the scripts under another /bin/sh.

# shellcheck disable=SC2015,SC2016 # ok/no never fail; jq filters and regexes stay single-quoted
HERE=$(cd "$(dirname "$0")/.." && pwd -P)
S="$HERE/scripts/statusline.sh"
I="$HERE/scripts/install.sh"
SH=${TEST_SH:-sh}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/statusline-test.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT INT TERM

NOW=1790371721
unset CLAUDE_CONFIG_DIR CLAUDE_HANDOFF_DIR CLAUDE_STATUSLINE_CONFIG XDG_CACHE_HOME
export HOME="$WORK/home"
export TZ=UTC
export CLAUDE_STATUSLINE_NOW=$NOW
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1
CONF="$HOME/.claude/statusline/config"
mkdir -p "$HOME/.claude/statusline" "$WORK/plain"
cd "$WORK" || exit 1

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; [ -n "$2" ] && printf '%s\n' "$2" | sed 's/^/     /'; }
# eq NAME GOT WANT - exact match.
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "got:  $2
want: $3"; fi; }
# has NAME OUTPUT PATTERN - OUTPUT matches the grep -E PATTERN.
has() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then ok "$1"; else no "$1" "$2"; fi; }
# hasnt NAME OUTPUT PATTERN - OUTPUT doesn't match.
hasnt() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then no "$1" "$2"; else ok "$1"; fi; }

ESC=$(printf '\033')
plain() { sed "s/$ESC\[[0-9;]*m//g"; }

# js DIR [EXTRA_JQ] - status line input for DIR, adjusted by a jq expression.
js() {
	jq -nc --arg d "$1" --argjson now "$NOW" '
		{session_id: "1aaf2147-91f9-48d6-aa23-caa0ebac765e", workspace: {current_dir: $d}, model: {display_name: "Opus"},
		 context_window: {used_percentage: 30.4, context_window_size: 1000000,
		   current_usage: {input_tokens: 4000, cache_creation_input_tokens: 1000, cache_read_input_tokens: 299000}},
		 rate_limits: {five_hour: {used_percentage: 55.2, resets_at: ($now + 7980)},
		   seven_day: {used_percentage: 91, resets_at: ($now + 364000)}}}' | jq -c "${2:-.}"
}
# run INPUT - raw status line output (with colours) into RAW, plain text into OUT.
run() {
	RAW=$(printf '%s' "$1" | "$SH" "$S" 2>&1)
	OUT=$(printf '%s' "$RAW" | plain)
}
setconf() { printf '%s\n' "$@" >"$CONF"; }

echo "# statusline.sh: input handling"
run ''
eq "empty input prints nothing" "$RAW" ""
run 'not json'
eq "invalid JSON prints nothing" "$RAW" ""
run '{}'
eq "empty object prints nothing" "$RAW" ""

echo "# statusline.sh: outside git"
run "$(js "$WORK/plain")"
eq "line 1 outside git" "$(printf '%s\n' "$OUT" | sed -n 1p)" "plain | Opus | 1aaf2147"
eq "line 2" "$(printf '%s\n' "$OUT" | sed -n 2p)" "ctx 30% · 304k | 5h 55% (resets 23:41, in 2h13m) | 7d 91% (resets Wed 02:35, in 4d5h)"
has "5h 55% is yellow" "$RAW" "$ESC\[0;33m55%"
has "7d 91% is red" "$RAW" "$ESC\[0;31m91%"
has "ctx 30% is green" "$RAW" "$ESC\[0;32m30%"
hasnt "no handoff hint under 700k" "$OUT" "handoff:handoff"

run "$(js "$WORK/plain" '.context_window.current_usage.cache_read_input_tokens = 720000')"
has "handoff hint over 700k" "$OUT" "ctx 30% · 725k → /handoff:handoff \|"
has "hint is red" "$RAW" "$ESC\[0;31m→ /handoff:handoff"

run "$(js "$WORK/plain" '.context_window = {used_percentage: 12, context_window_size: 200000}')"
has "tokens estimated from % x window" "$OUT" "ctx 12% · 24k \|"

run "$(js "$WORK/plain" '.rate_limits.five_hour.used_percentage = 49.4')"
has "5h reset hidden under 50%" "$OUT" "\| 5h 49% \| 7d"

run "$(js "$WORK/plain" '.rate_limits.seven_day.resets_at = 1790000000')"
has "past reset shows only the clock" "$OUT" "7d 91% \(resets Mon 14:13\)$"

run "$(js "$WORK/plain" 'del(.rate_limits)')"
eq "no rate limits: ctx only" "$(printf '%s\n' "$OUT" | sed -n 2p)" "ctx 30% · 304k"

run "$(js "$WORK/plain" '.rate_limits.five_hour.resets_at = "soon"')"
has "non-numeric reset is dropped" "$OUT" "\| 5h 55% \| 7d"

run '{"rate_limits": {"seven_day": {"used_percentage": 10}}}'
eq "single line when only usage is known" "$OUT" "7d 10%"

echo "# statusline.sh: config"
setconf SESSION_ID=full
run "$(js "$WORK/plain")"
has "SESSION_ID=full" "$OUT" "\| 1aaf2147-91f9-48d6-aa23-caa0ebac765e$"
setconf SESSION_ID=off
run "$(js "$WORK/plain")"
eq "SESSION_ID=off" "$(printf '%s\n' "$OUT" | sed -n 1p)" "plain | Opus"
setconf HANDOFF_HINT_K=0
run "$(js "$WORK/plain" '.context_window.current_usage.cache_read_input_tokens = 900000')"
hasnt "HANDOFF_HINT_K=0 turns the hint off" "$OUT" "→"
setconf HANDOFF_HINT_K=100 HANDOFF_HINT=/compact
run "$(js "$WORK/plain")"
has "custom hint and threshold" "$OUT" "304k → /compact"
setconf RESET_5H_FROM=0
run "$(js "$WORK/plain" '.rate_limits.five_hour.used_percentage = 5')"
has "RESET_5H_FROM=0 always shows the reset" "$OUT" "5h 5% \(resets 23:41"
setconf HANDOFF_HINT_K=abc RESET_5H_FROM=x
run "$(js "$WORK/plain" '.context_window.current_usage.cache_read_input_tokens = 900000')"
eq "bad numbers in config are ignored quietly" "$(printf '%s\n' "$OUT" | sed -n 2p)" "ctx 30% · 905k | 5h 55% | 7d 91% (resets Wed 02:35, in 4d5h)"
: >"$CONF"

echo "# statusline.sh: usage snapshot"
SNAP="$HOME/.cache/claude-usage-guard/usage.json"
run "$(js "$WORK/plain")"
eq "snapshot written for usage-guard" "$(jq -c '[.updated_at, .rate_limits.five_hour.used_percentage]' "$SNAP" 2>&1)" "[$NOW,55.2]"
setconf "SNAPSHOT=\"$WORK/other/u.json\""
run "$(js "$WORK/plain")"
[ -f "$WORK/other/u.json" ] && ok "custom SNAPSHOT path" || no "custom SNAPSHOT path"
setconf "SNAPSHOT=''"
mv "$SNAP" "$WORK/old-snap"
run "$(js "$WORK/plain")"
[ -f "$SNAP" ] && no "SNAPSHOT='' writes nothing" || ok "SNAPSHOT='' writes nothing"
run "$(js "$WORK/plain" 'del(.rate_limits)')"
: >"$CONF"
run "$(js "$WORK/plain" 'del(.rate_limits)')"
[ -f "$SNAP" ] && no "no snapshot without rate limits" || ok "no snapshot without rate limits"

echo "# statusline.sh: git and handoff"
git init -q --bare "$WORK/remote.git"
git init -q -b feat/x "$WORK/repo"
(cd "$WORK/repo" && echo a >f && git add f && git commit -qm one && git remote add origin "$WORK/remote.git" &&
	git push -q -u origin feat/x 2>/dev/null && echo b >g && git add g && git commit -qm two && git commit -qm three --allow-empty)
run "$(js "$WORK/repo")"
eq "branch and unpushed count" "$(printf '%s\n' "$OUT" | sed -n 1p)" "repo (feat/x) ↑2 | Opus | 1aaf2147"
has "repo cyan, branch magenta" "$RAW" "$ESC\[0;36mrepo$ESC\[0;2m \($ESC\[0;35mfeat/x"
echo c >>"$WORK/repo/f"
mkdir -p "$WORK/repo/sub"
run "$(js "$WORK/repo/sub")"
eq "uncommitted mark, from a subdirectory" "$(printf '%s\n' "$OUT" | sed -n 1p)" "sub (feat/x) * ↑2 | Opus | 1aaf2147"

ND="$HOME/.claude/handoffs/$(printf '%s' "$WORK/repo" | sed 's#/#-#g')"
mkdir -p "$ND"
printf -- '---\nrepo: x\ncreated_epoch: %s\n---\ngoal: g\n' $((NOW - 7500)) >"$ND/feat+x.md"
run "$(js "$WORK/repo")"
has "handoff note age (hours)" "$OUT" "^repo \(feat/x\) \* ↑2 · handoff 2h \|"
printf -- '---\ncreated_epoch: %s\n---\n' $((NOW - 190000)) >"$ND/feat+x.md"
run "$(js "$WORK/repo")"
has "handoff note age (days)" "$OUT" "· handoff 2d \|"
printf -- '---\ncreated_epoch: %s\n---\n' $((NOW - 600)) >"$ND/feat+x.md"
run "$(js "$WORK/repo")"
has "handoff note age (minutes)" "$OUT" "· handoff 10m \|"

git -C "$WORK/repo" worktree add -q "$WORK/wt" -b other 2>/dev/null
printf -- '---\ncreated_epoch: %s\n---\n' $((NOW - 3600)) >"$ND/other.md"
run "$(js "$WORK/wt")"
has "worktree uses the main repo's note folder" "$OUT" "^wt \(other\) · handoff 1h \|"

setconf GIT=off
run "$(js "$WORK/repo")"
eq "GIT=off keeps the handoff age" "$(printf '%s\n' "$OUT" | sed -n 1p)" "repo · handoff 10m | Opus | 1aaf2147"
setconf HANDOFF=off
run "$(js "$WORK/repo")"
hasnt "HANDOFF=off" "$OUT" "handoff 10m"
: >"$CONF"

sha=$(git -C "$WORK/repo" rev-parse --short HEAD)
git -C "$WORK/repo" checkout -q --detach 2>/dev/null
printf -- '---\ncreated_epoch: %s\n---\n' $((NOW - 60)) >"$ND/detached-$sha.md"
run "$(js "$WORK/repo")"
has "detached HEAD shows the sha and its note" "$OUT" "^repo \($sha\) \* · handoff 1m \|"

echo "# statusline.sh: adb"
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nprintf "List of devices attached\\nABC123\\tdevice\\n"\n' >"$WORK/bin/adb"
chmod +x "$WORK/bin/adb"
setconf ADB=on
RAW=$(js "$WORK/plain" | PATH="$WORK/bin:$PATH" "$SH" "$S")
sleep 1
RAW=$(js "$WORK/plain" | PATH="$WORK/bin:$PATH" "$SH" "$S")
has "📱 when adb lists a device" "$RAW" "plain.*📱 \| Opus"
: >"$CONF"
RAW=$(js "$WORK/plain" | PATH="$WORK/bin:$PATH" "$SH" "$S")
hasnt "ADB off by default" "$RAW" "📱"

echo "# install.sh"
rm -rf "$HOME/.claude"
C="$HOME/.claude"
mkdir -p "$C"
out=$("$SH" "$I" install 2>&1)
has "install on a fresh setup" "$out" "status line set"
eq "settings point at the copy" "$(jq -c .statusLine "$C/settings.json")" "{\"type\":\"command\",\"command\":\"sh \\\"$C/statusline/statusline.sh\\\"\",\"refreshInterval\":60}"
cmp -s "$S" "$C/statusline/statusline.sh" && ok "script copied" || no "script copied"
cmp -s "$HERE/scripts/config.default" "$C/statusline/config" && ok "default config written" || no "default config written"
out=$("$SH" "$I" uninstall 2>&1)
eq "uninstall with nothing before drops statusLine" "$(jq -c '.statusLine // "none"' "$C/settings.json")" '"none"'

rm -rf "$C"
mkdir -p "$C/plugins"
printf '{"theme":"dark","statusLine":{"type":"command","command":"bash ~/old.sh"},"pluginConfigs":{"usage-guard@m":{"options":{"snapshot_path":"~/snap/u.json"}}}}\n' >"$C/settings.json"
printf '{"plugins":{"usage-guard@m":[{}]}}\n' >"$C/plugins/installed_plugins.json"
before=$(cat "$C/settings.json")
out=$("$SH" "$I" install 2>&1)
rc=$?
eq "refuses to replace another status line (exit 2)" "$rc" "2"
eq "settings untouched after refusal" "$(cat "$C/settings.json")" "$before"
out=$("$SH" "$I" install --force 2>&1)
has "--force replaces it" "$out" "status line set"
eq "other settings kept" "$(jq -r .theme "$C/settings.json")" "dark"
eq "settings backed up" "$(cat "$C/settings.json.bak-statusline")" "$before"
eq "previous status line saved" "$(cat "$C/statusline/previous-statusline.json")" '{"type":"command","command":"bash ~/old.sh"}'
has "config uses usage-guard's snapshot_path" "$(cat "$C/statusline/config")" '^SNAPSHOT="\$HOME/snap/u.json"$'
out=$("$SH" "$I" status 2>&1)
has "status: installed" "$out" "^installed: yes$"
has "status: script up to date" "$out" "^script: up to date"
has "status: usage-guard found" "$out" "^usage-guard plugin: installed \(usage-guard@m\)$"
has "status: handoff missing" "$out" "^handoff plugin: not installed$"
echo '# local edit' >>"$C/statusline/config"
out=$("$SH" "$I" install 2>&1)
has "reinstall only refreshes" "$out" "already installed"
has "reinstall keeps the config" "$(cat "$C/statusline/config")" "^# local edit$"

echo "# edited" >>"$C/statusline/statusline.sh"
"$SH" "$I" sync >"$WORK/sync.out" 2>&1
eq "sync is silent" "$(cat "$WORK/sync.out")" ""
cmp -s "$S" "$C/statusline/statusline.sh" && ok "sync refreshes the installed copy" || no "sync refreshes the installed copy"

out=$("$SH" "$I" uninstall 2>&1)
eq "uninstall restores the previous status line" "$(jq -c .statusLine "$C/settings.json")" '{"type":"command","command":"bash ~/old.sh"}'
echo "# edited" >>"$C/statusline/statusline.sh"
"$SH" "$I" sync
has "sync leaves it alone when not installed" "$(tail -n 1 "$C/statusline/statusline.sh")" "^# edited$"
out=$("$SH" "$I" uninstall 2>&1)
has "second uninstall is a no-op" "$out" "not installed"

printf '{bad' >"$C/settings.json"
out=$("$SH" "$I" install --force 2>&1)
rc=$?
has "invalid settings.json is refused" "$out" "not valid JSON"
eq "invalid settings.json left as is" "$(cat "$C/settings.json")" "{bad"
[ "$rc" -ne 0 ] && ok "invalid settings.json exits non-zero" || no "invalid settings.json exits non-zero"

export CLAUDE_CONFIG_DIR="$WORK/cfg"
mkdir -p "$CLAUDE_CONFIG_DIR"
"$SH" "$I" install >/dev/null 2>&1
has "CLAUDE_CONFIG_DIR is honoured" "$(jq -r .statusLine.command "$WORK/cfg/settings.json")" "$WORK/cfg/statusline/statusline.sh"
unset CLAUDE_CONFIG_DIR

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
