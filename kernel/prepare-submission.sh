#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Regenerate kernel/submission/ from kernel/patches/, as git-format-patch
# commits on a v7.3 baseline.  The bare diffs are what the local build harness
# uses; these are what a mailing list would receive.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
out=$here/submission
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/drivers/media/usb/uvc"
cd "$work"
git init -q
git config user.name "Your Name"
git config user.email "you@example.com"
curl -sSfL -o drivers/media/usb/uvc/uvc_ctrl.c \
	https://raw.githubusercontent.com/torvalds/linux/v7.3/drivers/media/usb/uvc/uvc_ctrl.c
git add -A
git commit -q -m "media: uvcvideo: baseline (Linux v7.3)"

git apply "$here/patches/0002-uvcvideo-scope-ROI-quirk-to-the-RGB-interface.patch"
git add -A
git commit -q -F - <<'MSG'
media: uvcvideo: ignore Region of Interest on the NexiGo N930W RGB terminal

The NexiGo N930W / HelloCam Pro (3443:930d) advertises the UVC 1.5
Region of Interest control on both of its camera terminals.  On the RGB
terminal (video control interface 0) the device stalls every request for
that control with UVC error code 7 (Invalid Request), so listing controls
on that node fails and the driver permanently disables the associated
auto sub-control.  The IR terminal (interface 2) implements the same
control: the identical GET_CUR returns ten valid bytes.

v4l2-compliance on the RGB node with the distribution driver reports
46/49 with three failures, all of them this control ("maximum must be
non-zero for a bitmask control", "invalid control 00981ae2", and a
TRY_EXT_CTRLS error).  With this patch it reports 49/49.  The IR node is
unchanged at 48/49; its single failure is a separate, pre-existing one.

A blacklist entry could only target a USB device until now, so add an
optional interface number to the table: -1 keeps the existing entries
applying to the whole device, and 0 restricts this one to the RGB video
control interface.  Removing the control for the whole device would also
delete the IR control that works.

Measured on 3443:930d (bcdDevice 0.06): the RGB node keeps its 19
controls and loses the error, the IR node keeps both ROI controls and
their value.

Signed-off-by: <PENDING: your name <you@example.com>>
MSG

git apply "$here/patches/0001-uvcvideo-expose-MS-XU-face-authentication.patch"
git add -A
git commit -q -F - <<'MSG'
media: uvcvideo: expose the MS-XU face authentication control

Microsoft's UVC 1.5 extensions define a Face Authentication control
(MS-XU selector 0x06) that selects, per streaming interface, whether the
IR illuminator runs in general-purpose (D0), alternating-frame (D1) or
continuous (D2) mode.  Windows Hello uses D1; without it the IR stream is
unlit and no liveness or face authentication is possible.

uvcvideo only instantiates controls present in its static table, so the
control is unreachable from V4L2, libcamera, PipeWire and browsers.
Expose it as a menu over the entry for the camera's single IR streaming
interface, with a read-modify-write of the flags byte so the interface
entry is preserved.

The control id is private (V4L2_CID_USER_BASE + 0x1000) because this is
an RFC: the payload is a per-interface array rather than a scalar, so the
public API is the open question, not the plumbing.  v4l2-compliance
reports "expected N private controls, got 0" on the IR node with this
control present, which has to be resolved before it is proposed.

Measured on a NexiGo N930W (3443:930d): the control appears as a
three-entry menu, writing D1 gives per-frame IR means alternating 0.9 and
222.7 while D0 stays flat, and the previous value is restored.

Signed-off-by: <PENDING: your name <you@example.com>>
MSG

rm -f "$out"/*.patch
git format-patch -2 --no-signature --zero-commit --no-numbered -o "$out" >/dev/null
ls -1 "$out"/*.patch | while read -r p; do echo "$(basename "$p")"; done
