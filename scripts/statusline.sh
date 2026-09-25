#!/bin/sh
# claude-statusline: a two-line Claude Code status line.
#   line 1: repo (branch) * ↑N · handoff 2h 📱 | model | session
#   line 2: ctx 31% · 312k → /handoff:handoff | 5h 55% (resets 05:38, in 2h13m) | 7d 91% (resets Wed 08:25, in 4d5h)
# Reads the status line JSON on stdin. Options live in $CLAUDE_CONFIG_DIR/statusline/config
# (sh syntax, see config.default). Every part fails soft: a missing tool or odd input drops
# that part, never the whole line.

input=$(cat)
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || {
	printf 'statusline: install jq'
	exit 0
}

# Defaults; the config file overrides any of them.
SESSION_ID=short         # full | short | off
GIT=on                   # branch, * uncommitted changes, ↑N unpushed commits
HANDOFF=on               # age of the handoff note for this repo and branch
HANDOFF_HINT_K=700       # past this many thousand context tokens, suggest HANDOFF_HINT; 0 = off
HANDOFF_HINT=/handoff:handoff
ADB=off                  # 📱 when `adb devices` lists a device
RESET_5H_FROM=50         # show the 5-hour reset time once usage reaches this %
SNAPSHOT="$HOME/.cache/claude-usage-guard/usage.json" # plan usage snapshot for usage-guard; empty = off

CONFIG=${CLAUDE_STATUSLINE_CONFIG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline/config}
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"
NOW=${CLAUDE_STATUSLINE_NOW:-$(date +%s)}

dir='' model='' session='' ctx='' ctx_tokens='' five='' five_at='' week='' week_at='' has_rl=''
eval "$(printf '%s' "$input" | jq -r '
	def pct: if type == "number" then (. + 0.5 | floor | tostring) else "" end;
	def int: if type == "number" then (floor | tostring) else "" end;
	(.context_window // {}) as $c
	| ($c.current_usage // null) as $u
	| @sh "dir=\(.workspace.current_dir // .cwd // "")",
	  @sh "model=\(.model.display_name // "")",
	  @sh "session=\(.session_id // "")",
	  @sh "ctx=\($c.used_percentage | pct)",
	  @sh "ctx_tokens=\(
		if ($u | type) == "object" then
			(($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) | int
		elif ($c.used_percentage | type) == "number" and ($c.context_window_size | type) == "number" then
			($c.used_percentage * $c.context_window_size / 100) | int
		else "" end)",
	  @sh "five=\(.rate_limits.five_hour.used_percentage | pct)",
	  @sh "five_at=\(.rate_limits.five_hour.resets_at | int)",
	  @sh "week=\(.rate_limits.seven_day.used_percentage | pct)",
	  @sh "week_at=\(.rate_limits.seven_day.resets_at | int)",
	  @sh "has_rl=\(if (.rate_limits | type) == "object" then "1" else "" end)"
' 2>/dev/null)"

# Snapshot plan usage for usage-guard (and anything else that wants it), written atomically.
if [ -n "$SNAPSHOT" ] && [ -n "$has_rl" ]; then
	mkdir -p "$(dirname "$SNAPSHOT")" 2>/dev/null
	printf '%s' "$input" | jq -c --argjson now "$NOW" '{updated_at: $now, rate_limits}' >"$SNAPSHOT.$$" 2>/dev/null &&
		mv -f "$SNAPSHOT.$$" "$SNAPSHOT" 2>/dev/null
fi

E=$(printf '\033')
DIM="${E}[0;2m"
RST="${E}[0m"
# col CODE TEXT - TEXT in an ANSI colour, then back to dim.
col() { printf '%s[0;%sm%s%s' "$E" "$1" "$2" "$DIM"; }
# cpct N - N% in green under 50, yellow under 80, red from 80.
cpct() {
	c=32
	[ "$1" -ge 50 ] && c=33
	[ "$1" -ge 80 ] && c=31
	col "$c" "$1%"
}
# mtime FILE - modification time in epoch seconds (GNU stat, then BSD stat).
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
# clock EPOCH FORMAT - local time (BSD date, then GNU date).
clock() { date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null; }
# span SECONDS - "4d5h", "2h13m" or "12m".
span() {
	d=$(($1 / 86400))
	h=$(($1 % 86400 / 3600))
	m=$(($1 % 3600 / 60))
	if [ "$d" -gt 0 ]; then
		printf '%dd%dh' "$d" "$h"
	elif [ "$h" -gt 0 ]; then
		printf '%dh%dm' "$h" "$m"
	else
		printf '%dm' "$m"
	fi
}
# reset EPOCH FORMAT - "05:38, in 2h13m"; just the clock time once it has passed.
reset() {
	r=$(clock "$1" "$2")
	[ -n "$r" ] || return 0
	s=$(($1 - NOW))
	if [ "$s" -gt 0 ]; then printf '%s, in %s' "$r" "$(span "$s")"; else printf '%s' "$r"; fi
}
num() { case $1 in '' | *[!0-9]*) return 1 ;; esac; }

# Git state and the handoff note, both from the session's working directory.
branch='' mark='' note=''
if [ -n "$dir" ] && { [ "$GIT" != off ] || [ "$HANDOFF" != off ]; } &&
	command -v git >/dev/null 2>&1 && cd "$dir" 2>/dev/null &&
	common=$(git --no-optional-locks rev-parse --git-common-dir 2>/dev/null); then
	sha=$(git --no-optional-locks rev-parse --short HEAD 2>/dev/null)
	branch=$(git --no-optional-locks symbolic-ref --short -q HEAD 2>/dev/null)
	if [ "$GIT" != off ] && [ -n "$sha" ]; then
		git --no-optional-locks diff --quiet HEAD -- 2>/dev/null || mark="*"
		ahead=$(git --no-optional-locks rev-list --count '@{u}..HEAD' 2>/dev/null)
		num "$ahead" && [ "$ahead" -gt 0 ] && mark="${mark:+$mark }↑$ahead"
	fi
	if [ "$HANDOFF" != off ]; then
		# Same layout as the handoff plugin: <main worktree, / -> -> / <branch, / -> +>.md
		main=$(cd "$common/.." 2>/dev/null && pwd -P)
		if [ -n "$branch" ]; then
			slug=$(printf '%s' "$branch" | sed 's#/#+#g')
		else
			slug="detached-${sha:-none}"
		fi
		f="${CLAUDE_HANDOFF_DIR:-$HOME/.claude/handoffs}/$(printf '%s' "$main" | sed 's#/#-#g')/$slug.md"
		if [ -n "$main" ] && [ -f "$f" ]; then
			t=$(sed -n 's/^created_epoch: *\([0-9][0-9]*\).*/\1/p' "$f" | sed -n 1p)
			num "$t" || t=$(mtime "$f")
			if num "$t"; then
				a=$((NOW - t))
				[ "$a" -ge 0 ] || a=0
				note=$(span "$a" | sed 's/^\([0-9]*[dh]\).*/\1/')
			fi
		fi
	fi
	[ -n "$branch" ] || branch=$sha
	[ "$GIT" != off ] || branch=
fi

# Phone connected: adb is slow, so read a cached device list that a detached refresh keeps under 30s old.
phone=
if [ "$ADB" = on ] && command -v adb >/dev/null 2>&1; then
	cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/adb-devices.txt"
	m=$(mtime "$cache")
	if [ $((NOW - ${m:-0})) -gt 30 ]; then
		mkdir -p "$(dirname "$cache")" 2>/dev/null
		touch "$cache" 2>/dev/null
		(adb devices >"$cache.$$" 2>/dev/null && mv -f "$cache.$$" "$cache") </dev/null >/dev/null 2>&1 &
	fi
	grep -q "$(printf '\t')device\$" "$cache" 2>/dev/null && phone="📱"
fi

line1=
[ -n "$dir" ] && line1=$(col 36 "$(basename "$dir")")
[ -n "$branch" ] && line1="$line1 ($(col 35 "$branch"))"
[ -n "$mark" ] && line1="$line1 $(col 33 "$mark")"
[ -n "$note" ] && line1="$line1 · handoff $note"
[ -n "$phone" ] && line1="$line1 $phone"
[ -n "$model" ] && line1="${line1:+$line1 | }$model"
case $SESSION_ID in
full) [ -n "$session" ] && line1="${line1:+$line1 | }$session" ;;
short) [ -n "$session" ] && line1="${line1:+$line1 | }${session%%-*}" ;;
esac

line2=
add() { line2="${line2:+$line2 | }$1"; }
if [ -n "$ctx" ] || [ -n "$ctx_tokens" ]; then
	c=ctx
	[ -n "$ctx" ] && c="$c $(cpct "$ctx")"
	if [ -n "$ctx_tokens" ]; then
		c="$c · $((ctx_tokens / 1000))k"
		num "$HANDOFF_HINT_K" && [ "$HANDOFF_HINT_K" -gt 0 ] && [ "$ctx_tokens" -gt $((HANDOFF_HINT_K * 1000)) ] &&
			c="$c $(col 31 "→ $HANDOFF_HINT")"
	fi
	add "$c"
fi
if [ -n "$five" ]; then
	c="5h $(cpct "$five")"
	if [ -n "$five_at" ] && num "$RESET_5H_FROM" && [ "$five" -ge "$RESET_5H_FROM" ]; then
		r=$(reset "$five_at" '%H:%M')
		[ -n "$r" ] && c="$c (resets $r)"
	fi
	add "$c"
fi
if [ -n "$week" ]; then
	c="7d $(cpct "$week")"
	if [ -n "$week_at" ]; then
		r=$(reset "$week_at" '%a %H:%M')
		[ -n "$r" ] && c="$c (resets $r)"
	fi
	add "$c"
fi

if [ -n "$line1" ] && [ -n "$line2" ]; then
	printf '%s%s%s\n%s%s%s' "$DIM" "$line1" "$RST" "$DIM" "$line2" "$RST"
elif [ -n "$line1$line2" ]; then
	printf '%s%s%s' "$DIM" "$line1$line2" "$RST"
fi
exit 0
