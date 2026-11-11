#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Apply the proof-of-concept patches to the fetched kernel/uvc sources.
# Run kernel/fetch-sources.sh first.  Re-running is safe: an already-applied
# patch is detected and skipped.
#
# The patches carry kernel-tree paths (a/drivers/media/usb/uvc/uvc_ctrl.c) so
# they read like a submission, which means the strip level depends on where the
# sources were fetched to.  find_strip probes for it instead of hardcoding one.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
tree=$(cd "$here/../uvc" && pwd)

find_reverse_strip() {
	for n in 1 2 3 4 5 6; do
		if patch -d "$tree" -p"$n" -R --dry-run -s < "$1" >/dev/null 2>&1; then
			echo "$n"
			return 0
		fi
	done
	return 1
}

find_strip() {
	for n in 1 2 3 4 5 6; do
		if patch -d "$tree" -p"$n" --dry-run -s < "$1" >/dev/null 2>&1; then
			echo "$n"
			return 0
		fi
	done
	return 1
}

applied=0
for p in "$here"/*.patch; do
	name=$(basename "$p")
	if find_reverse_strip "$p" >/dev/null; then
		echo "already applied $name"
		applied=$((applied + 1))
		continue
	fi
	strip=$(find_strip "$p") || {
		echo "$name does not apply to $tree" >&2
		exit 1
	}
	patch -d "$tree" -p"$strip" -s < "$p"
	echo "applied $name (-p$strip)"
	applied=$((applied + 1))
done

[ "$applied" -gt 0 ] || { echo "no patches found in $here" >&2; exit 1; }
