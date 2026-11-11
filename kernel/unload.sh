#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Put the distribution module back.
set -eu

if [ ! -d /sys/module/uvcvideo ]; then
	modprobe uvcvideo
	echo "loaded $(modinfo -F filename uvcvideo)"
	exit 0
fi

refcnt=$(cat /sys/module/uvcvideo/refcnt 2>/dev/null || echo 0)
if [ "$refcnt" != 0 ]; then
	echo "uvcvideo is in use (refcnt $refcnt); openers:" >&2
	fuser -v /dev/video* 2>&1 | sed 's/^/  /' >&2
	echo "close the camera (browser tab, meeting app) and run this again," >&2
	echo "or just reboot: a reboot always returns to the distribution module." >&2
	exit 1
fi

modprobe -r uvcvideo
modprobe uvcvideo

have=$(cat /sys/module/uvcvideo/srcversion 2>/dev/null || echo "?")
stock=$(modinfo -F srcversion uvcvideo 2>/dev/null || echo "?")
if [ "$have" = "$stock" ]; then
	echo "restored the distribution module (srcversion $have)"
else
	echo "still running a non-distribution module (srcversion $have)" >&2
	exit 1
fi
