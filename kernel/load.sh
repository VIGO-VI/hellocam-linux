#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Load the locally built uvcvideo (proof of concept) over the distro module.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
ko="$here/uvc/uvcvideo.ko"

if [ ! -f "$ko" ]; then
	echo "no module; build it first:" >&2
	echo "  make -C /lib/modules/$(uname -r)/build M=$here/uvc LLVM=1 modules" >&2
	exit 1
fi

want=$(modinfo -F srcversion "$ko")

# insmod does not resolve dependencies, so make sure the stock module (and
# therefore uvc, videobuf2-*, videodev, mc) is loaded first.  rmmod then
# removes only uvcvideo and leaves its dependencies in place.
modprobe uvcvideo 2>/dev/null || true

if lsmod | grep -q '^uvcvideo'; then
	if ! rmmod uvcvideo; then
		echo "uvcvideo is in use (close anything streaming) and cannot be replaced" >&2
		exit 1
	fi
fi

extra=""
[ "${1:-}" = "--trace" ] && extra="trace=0xffff"

# shellcheck disable=SC2086
if ! insmod "$ko" $extra; then
	echo "insmod failed, see: journalctl -k | tail" >&2
	exit 1
fi

sleep 1

if ! lsmod | grep -q '^uvcvideo'; then
	echo "module did not stay loaded, see journalctl -k" >&2
	exit 1
fi

have=$(cat /sys/module/uvcvideo/srcversion)
if [ "$have" != "$want" ]; then
	echo "loaded module is not ours (srcversion $have, expected $want)" >&2
	exit 1
fi
echo "loaded our uvcvideo (srcversion $have)"

found=0
for node in /dev/video*; do
	ctrl=$(v4l2-ctl -d "$node" --list-ctrls 2>/dev/null |
	       grep -iE 'face.authentication' || true)
	if [ -n "$ctrl" ]; then
		echo "$node: $ctrl"
		found=1
	fi
done

if [ "$found" = 0 ]; then
	echo "no Face Authentication control appeared; journalctl -k | tail -5:" >&2
	journalctl -k -n 5 -o cat >&2
	exit 1
fi
exit 0
