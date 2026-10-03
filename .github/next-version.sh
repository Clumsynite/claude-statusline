#!/bin/sh
# Usage: next-version.sh VERSION < commit messages
# Prints the next x.y.z when a message says "release" or "releasing", or nothing.
# "major", "minor" or "patch" on such a line picks the bump (the highest wins); the default is patch.

case $1 in
[0-9]*.[0-9]*.[0-9]*) ;;
*)
	echo "next-version: '$1' is not x.y.z" >&2
	exit 2
	;;
esac
lines=$(grep -iE '(^|[^[:alnum:]_-])releas(e|ing)([^[:alnum:]_-]|$)')
[ -n "$lines" ] || exit 0

level='patch'
if printf '%s\n' "$lines" | grep -qiE '(^|[^[:alnum:]])major([^[:alnum:]]|$)'; then
	level='major'
elif printf '%s\n' "$lines" | grep -qiE '(^|[^[:alnum:]])minor([^[:alnum:]]|$)'; then
	level='minor'
fi

IFS=. read -r x y z <<EOF
$1
EOF
case $level in
major) echo "$((x + 1)).0.0" ;;
minor) echo "$x.$((y + 1)).0" ;;
patch) echo "$x.$y.$((z + 1))" ;;
esac
