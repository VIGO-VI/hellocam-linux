<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# hellocam-linux

Linux support work for the **NexiGo HelloCam / HelloCam Pro (N930W family,
USB `3443:930d`)** — a dual-camera USB device (1080p60 RGB + 640x360 IR for
Windows Hello) with a UAC1 microphone.

Goal: find every feature that currently needs Windows, make it work in
userspace first, then in the kernel, then upstream it out of the box.

## Status

| Area | Linux today | Notes |
|---|---|---|
| RGB stream (MJPG 1080p60 / YUYV) | works, `uvcvideo` | `/dev/video0` |
| IR stream (GREY 640x360@30) | works, `uvcvideo` | `/dev/video2`, IR and RGB can run together (RGB drops to 30 fps) |
| Motorised privacy shutter | works | firmware opens it on RGB stream start, closes on stop; IR does not open it |
| Standard controls (exposure, WB, zoom, focus…) | works | `v4l2-ctl -d /dev/video0 --list-ctrls` |
| IR illuminator / face-auth mode | **works** | userspace via `UVCIOC_CTRL_QUERY`, or natively as a V4L2 menu control with `kernel/` (proof of concept); D1 strobing proven optically |
| Per-frame metadata (illumination, stats) | works (kernel 7.x) | MS-XU selector `0x09` is enabled at probe by `uvc_meta_detect_msxu()`; `/dev/video3` offers `UVCM` and streams ~4 KB/frame |
| Vendor XU `{28f03370-6311-4a2e-ba2c-6890eb334016}` | **not exposed** | 7 controls on the RGB chain — the NexiGo Windows software lives here |
| Microphone | works | a stuck-ADC state seen once streamed pure silence until a **physical replug**; port-independent (`hellocamctl mic` checks it) |
| Region-of-interest controls | exposed but broken | device answers `-EIO`; uvcvideo disables them, see dmesg |

## Usage

```sh
./hellocamctl info            # descriptor model, no privileges needed
./hellocamctl xu              # read every advertised extension-unit control
./hellocamctl ir status       # current IR / face-authentication mode
./hellocamctl ir on           # D1: alternating-frame IR illumination (LED flashes)
./hellocamctl ir off          # D0: general purpose (illuminator idle)
./hellocamctl capture --combined   # IR + RGB at the same time
./hellocamctl mic             # record and report the level (peak 0 = silent)
./hellocamctl selftest        # write, read back, measure the IR image, restore
```

Everything runs as a normal user: the tool uses uvcvideo's own
`UVCIOC_CTRL_QUERY` pass-through on the video node, not raw USB.  The udev rule
in `packaging/` is only needed for the `--usbfs` fallback and can be left out.

## Safety

The tool only ever writes controls that the device descriptor advertises in
`bmControls`, builds payloads from the values the device itself reports
(`GET_CUR` / `GET_DEF`), and restores the previous value after a test. Guessing
bytes at an unknown vendor unit has bricked cameras before; there is no
"poke around" mode, and `--probe` is read-only (`GET_INFO` / `GET_LEN`).

## Layout

```
hellocamctl                     the userspace proof of concept
docs/FINDINGS.md                hardware/software audit with evidence
docs/SETUP-irlume.md            face unlock as actually set up, with scores
docs/ROADMAP.md                 userspace -> kernel -> upstream plan
packaging/                      udev rule (optional) and the installer
kernel/                         out-of-tree uvcvideo proof of concept
kernel/submission/              format-patch series with commit messages
```

## Licence

GPL-2.0-or-later, the same terms as the kernel driver this feeds
(`drivers/media/usb/uvc`). The full GPL-2.0 text is in `LICENSE`; the "or later"
part is the SPDX tag at the top of each file. Nothing from the kernel is
vendored: `kernel/fetch-sources.sh` downloads a released `uvcvideo` tree and
`kernel/patches/` is the complete difference against it.
