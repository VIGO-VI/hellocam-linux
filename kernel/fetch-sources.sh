#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Fetch the upstream uvcvideo sources this out-of-tree build compiles.
#
# The tree in kernel/uvc/ is a verbatim copy of drivers/media/usb/uvc from a
# released kernel, so it is not vendored here: only Kbuild ships, and this
# script fills in the rest at the exact tag the patches were made against.
set -eu

tag="${1:-v7.3}"
dir=$(cd "$(dirname "$0")" && pwd)/uvc
base="https://raw.githubusercontent.com/torvalds/linux/$tag/drivers/media/usb/uvc"

mkdir -p "$dir"
for f in Makefile uvc_ctrl.c uvc_debugfs.c uvc_driver.c uvc_entity.c \
	 uvc_isight.c uvc_metadata.c uvc_queue.c uvc_status.c uvc_v4l2.c \
	 uvc_video.c uvcvideo.h; do
	if [ -e "$dir/$f" ]; then
		echo "have $f"
		continue
	fi
	echo "fetch $f"
	curl -sSfL -o "$dir/$f" "$base/$f"
done

# The in-tree Makefile is kept for reference; Kbuild is what we build with.
mv "$dir/Makefile" "$dir/Makefile.intree" 2>/dev/null || true

echo "sources for $tag are in $dir"
echo "next: kernel/patches/apply.sh, then make -C /lib/modules/\$(uname -r)/build M=$dir LLVM=1 modules"
