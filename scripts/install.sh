#!/bin/sh
# shellcheck disable=SC2016 # jq filters and the literal $HOME are meant to stay unexpanded
# Installs, checks and removes the claude-statusline status line. Usage: install.sh COMMAND
#   status           report the status line setting, the installed copy, the config and related plugins
#   install [--force] copy statusline.sh into $CLAUDE_CONFIG_DIR/statusline/, write a config if there is
#                    none, and point settings.json at it. Another status line is only replaced with
#                    --force; it is saved first so uninstall can restore it.
#   uninstall        restore the status line install replaced (or drop statusLine); files are kept
#   sync             SessionStart hook: refresh the installed copy after a plugin update. Silent, exits 0.

HERE=$(cd "$(dirname "$0")" && pwd -P)
SRC="$HERE/statusline.sh"
CONF_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
SETTINGS="$CONF_DIR/settings.json"
DEST="$CONF_DIR/statusline"
SCRIPT="$DEST/statusline.sh"
CONFIG="$DEST/config"
PREV="$DEST/previous-statusline.json"
BACKUP="$SETTINGS.bak-statusline"
CMD="sh \"$SCRIPT\""

say() { printf 'statusline: %s\n' "$*"; }

# current - the statusLine setting as compact JSON, or null.
current() {
	if [ -f "$SETTINGS" ]; then jq -c '.statusLine // null' "$SETTINGS" 2>/dev/null || echo invalid; else echo null; fi
}
# ours - settings.json already runs the installed copy.
ours() { [ -f "$SETTINGS" ] && jq -e --arg s "$SCRIPT" '(.statusLine.command // "") | contains($s)' "$SETTINGS" >/dev/null 2>&1; }
# plugin NAME - "installed (id)" or "not installed".
plugin() {
	id=$(jq -r --arg n "$1@" '.plugins // {} | keys[] | select(startswith($n))' "$CONF_DIR/plugins/installed_plugins.json" 2>/dev/null | sed -n 1p)
	if [ -n "$id" ]; then echo "installed ($id)"; else echo "not installed"; fi
}
# guard_snapshot - usage-guard's configured snapshot_path, with ~/ spelled $HOME/, or nothing.
guard_snapshot() {
	jq -r '.pluginConfigs // {} | to_entries[] | select(.key | startswith("usage-guard@")) | .value.options.snapshot_path // empty' \
		"$SETTINGS" 2>/dev/null | sed -n 1p | sed 's#^~/#$HOME/#'
}
# write_settings FILTER [ARGS...] - apply a jq filter to settings.json atomically.
write_settings() {
	filter=$1
	shift
	[ -f "$SETTINGS" ] || printf '{}\n' >"$SETTINGS"
	tmp="$SETTINGS.statusline.$$"
	if jq "$@" "$filter" "$SETTINGS" >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
		mv -f "$tmp" "$SETTINGS"
	else
		rm -f "$tmp"
		say "could not update $SETTINGS; nothing changed"
		exit 1
	fi
}

need_jq() { command -v jq >/dev/null 2>&1 || {
	say "jq is required (brew install jq, apt install jq, ...)"
	exit 1
}; }

cmd_status() {
	need_jq
	printf 'settings: %s\n' "$SETTINGS"
	printf 'statusLine: %s\n' "$(current)"
	if ours; then echo "installed: yes"; else echo "installed: no"; fi
	if [ ! -f "$SCRIPT" ]; then
		echo "script: missing ($SCRIPT)"
	elif cmp -s "$SRC" "$SCRIPT"; then
		echo "script: up to date ($SCRIPT)"
	else
		echo "script: differs from this plugin version ($SCRIPT)"
	fi
	if [ -f "$CONFIG" ]; then echo "config: $CONFIG"; else echo "config: none yet ($CONFIG)"; fi
	for t in jq git adb; do
		if command -v "$t" >/dev/null 2>&1; then echo "$t: found"; else echo "$t: missing"; fi
	done
	echo "handoff plugin: $(plugin handoff)"
	echo "usage-guard plugin: $(plugin usage-guard)"
	s=$(guard_snapshot)
	[ -n "$s" ] && echo "usage-guard snapshot_path: $s"
	[ -f "$PREV" ] && echo "saved previous statusLine: $(cat "$PREV")"
	return 0
}

cmd_install() {
	need_jq
	cur=$(current)
	if [ "$cur" = invalid ]; then
		say "$SETTINGS is not valid JSON; fix it first"
		exit 1
	fi
	if ! ours && [ "$cur" != null ] && [ "$1" != --force ]; then
		say "another status line is set: $cur"
		say "rerun with --force to replace it (it is saved, and uninstall restores it)"
		exit 2
	fi
	mkdir -p "$DEST" || exit 1
	cp -f "$SRC" "$SCRIPT" || exit 1
	if [ ! -f "$CONFIG" ]; then
		s=$(guard_snapshot)
		if [ -n "$s" ]; then
			awk -v p="$s" '/^SNAPSHOT=/ { print "SNAPSHOT=\"" p "\""; next } { print }' "$HERE/config.default" >"$CONFIG"
		else
			cp "$HERE/config.default" "$CONFIG"
		fi
		say "wrote config $CONFIG"
	fi
	if ! ours; then
		[ -f "$SETTINGS" ] && [ ! -f "$BACKUP" ] && cp "$SETTINGS" "$BACKUP" && say "backed up settings to $BACKUP"
		printf '%s\n' "$cur" >"$PREV"
		write_settings '.statusLine = {type: "command", command: $cmd, refreshInterval: 60}' --arg cmd "$CMD"
		say "status line set: $CMD"
	else
		say "already installed; script refreshed"
	fi
}

cmd_uninstall() {
	need_jq
	if ! ours; then
		say "not installed (statusLine is $(current)); nothing changed"
		return 0
	fi
	prev=null
	[ -f "$PREV" ] && prev=$(jq -c . "$PREV" 2>/dev/null || echo null)
	if [ "$prev" = null ]; then
		write_settings 'del(.statusLine)'
		say "removed statusLine"
	else
		write_settings '.statusLine = $p' --argjson p "$prev"
		say "restored previous statusLine: $prev"
	fi
	say "kept $DEST (script, config); delete it yourself if you don't want it"
}

cmd_sync() {
	command -v jq >/dev/null 2>&1 || exit 0
	ours && [ -f "$SCRIPT" ] && ! cmp -s "$SRC" "$SCRIPT" && cp -f "$SRC" "$SCRIPT" 2>/dev/null
	exit 0
}

case $1 in
status) cmd_status ;;
install) cmd_install "$2" ;;
uninstall) cmd_uninstall ;;
sync) cmd_sync ;;
*)
	echo "usage: install.sh status | install [--force] | uninstall | sync" >&2
	exit 64
	;;
esac
