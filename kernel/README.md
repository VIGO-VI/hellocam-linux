<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Kernel proof of concept

Out-of-tree `uvcvideo` with two changes this camera needs. Both are in
`patches/`; nothing here is built into the distro kernel.

| patch | what |
|---|---|
| `0001-uvcvideo-expose-MS-XU-face-authentication.patch` | exposes the Microsoft XU Face Authentication control as a V4L2 menu, so any application can switch the IR illuminator (general purpose / alternating / continuous) |
| `0002-uvcvideo-drop-broken-ROI-controls-for-3443-930d.patch` | drops Region-of-Interest for `3443:930d`, whose firmware answers every ROI request with `-EIO` |

## Build and load

```sh
kernel/fetch-sources.sh              # verbatim drivers/media/usb/uvc at v7.3
kernel/patches/apply.sh
make -C /lib/modules/$(uname -r)/build M=$PWD/kernel/uvc LLVM=1 modules
sudo kernel/load.sh                  # swap it in
sudo kernel/unload.sh                # back to the distro module
```

`load.sh` loads the stock module first (for `uvc`, `videobuf2-*`, `videodev`,
`mc`), then `rmmod`s only `uvcvideo` and `insmod`s the built one — `insmod` does
not resolve dependencies on its own. It also refuses to claim success unless the
loaded `srcversion` is the one it just built, and fails if the control does not
appear. `unload.sh` reports the refcount and the openers instead of pretending
it restored the stock module when something (a browser tab, a meeting app) still
holds the camera.

## Provenance and licence

`kernel/uvc/` is a byte-for-byte copy of `drivers/media/usb/uvc` from Linux
v7.3 (GPL-2.0), fetched by `fetch-sources.sh` rather than vendored here. The
only modified file is `uvc_ctrl.c`, and `patches/` is the complete difference
against that tag. The build products are gitignored.

## Known limits of the proof of concept

* The control id is a private one (`V4L2_CID_USER_BASE + 0x1000`). Upstream
  would need a real `V4L2_CID_*` in `videodev2.h`, which is a maintainer
  decision, not a mechanical change.
* The control is only offered when the camera advertises the MS-XU face
  authentication selector; the payload size is taken from the descriptor's
  declared contract (9 bytes = one entry). A camera that reports a different
  size fails cleanly on the first `GET_CUR` rather than writing something the
  firmware did not ask for.
* Nothing is written at probe time. This camera does not answer UVC class
  requests while the driver is probing it (`GET_LEN` returns `-EAGAIN`).
