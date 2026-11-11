<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Roadmap

End goal: upstream, out-of-the-box Linux support for everything this camera
can do. Order matters — each stage has to be *proven* before the next one is
proposed, and every upstream step needs explicit approval.

## Stage 0 — audit (done)

* Full descriptor model, stream matrix, control inventory: `docs/FINDINGS.md`.
* Established what already works (RGB, IR, both at once, shutter, standard
  controls) and what does not (IR illuminator, metadata, vendor XU, mic).

## Stage 1 — userspace proof of concept (in progress)

`hellocamctl`, no root once the udev rule is installed.

* [x] descriptor parser, IR node discovery, MS-XU discovery
* [x] read-back of every advertised XU control
* [x] `ir on/off` write + read-back
* [x] `selftest`: write D1, capture IR, write D0, capture IR, show the optical
      difference, restore the original value — 11/11 checks, twice, on two
      different USB ports
* [x] metadata control enable — already done by mainline `uvcvideo`
      (`UVCM` on `/dev/video3`); still to do: decode the payload so the
      illuminator can be proven per frame instead of by brightness
* [x] read-only probe of the vendor XU selector map (never a blind write)
* [x] mic: resolved — a stuck ADC that a physical replug clears; the port was
      a red herring (`docs/FINDINGS.md` 3.1a)
* [x] no privileges needed: `UVCIOC_CTRL_QUERY` on the video node replaces usbfs

Acceptance: `hellocamctl selftest` prints all checks PASS on a cold boot and
leaves the camera in its original state.

## Stage 2 — kernel proof of concept (done)

A local uvcvideo build (out-of-tree module against the running kernel) that
exposes the useful controls the way the rest of the stack expects them:

* MS-XU face authentication as a V4L2 control (on/off per IR streaming
  interface). Natural model: a `V4L2_CID_…` boolean/bitmask on the IR node, or
  following whatever upstream prefers once discussed.
* MS-XU metadata switch so `uvcvideo`'s existing metadata support
  (`/dev/video3`) actually produces per-frame illumination records.
* A device quirk for the broken region-of-interest controls.

All of it must be opt-in by USB id + descriptor evidence (advertised selector),
never by product-name string, and must default to the current behaviour.

Acceptance: with the module loaded, `v4l2-ctl` shows the new controls, and the
same `selftest` passes using V4L2 only (no usbfs), from an unprivileged user.

**Met.** `v4l2-ctl -d /dev/video2 --list-ctrls-menus` shows
`face_authentication_mode 0x00981900 (menu) min=0 max=2` with the three modes,
and `hellocamctl v4l2test` passes 5/5 driving it through `VIDIOC_S_CTRL` alone
(delta 35.90 between mode 1 and mode 0, state restored). The module is
out-of-tree and unsigned, so a reboot goes back to the stock driver by itself.

Remaining before it is upstreamable: a real `V4L2_CID_*` instead of the private
id, and a decision on the default mode while the IR node streams.

## Stage 3 — upstream

**Started: irlume PR #1311** (2026-11-10) adds `3443:930d` to irlume's
`known_control` emitter table with the descriptor / write / read-back / optical /
restore evidence that table required, and a comment on irlume#449 (the same
camera, same symptom) points the reporter at it. Texts are kept in
`docs/upstream/`. The kernel patches have not been sent anywhere yet.



In rough order of "cheap and uncontroversial" to "needs discussion":

1. **uvcvideo: expose MS-XU face authentication / IR illumination.** Small,
   self-contained, uses the existing `uvc_ctrls[]` mapping machinery, and
   follows the in-tree precedent of `uvc_meta_detect_msxu()` which already
   drives another MS-XU selector.
3. **uvcvideo: quirk to suppress the non-compliant ROI controls** on
   `3443:930d`.
4. **ALSA: fix / document the silent microphone** — either a new quirk, or a
   bug report with the vendor XU evidence if the ADC needs enabling.
5. **Vendor XU** (`28f03370-…`): only if the selector map can be documented
   from the NexiGo Windows software or vendor documentation. Otherwise leave
   it alone and document it.
6. **udev/packaging**: nothing should be needed once the kernel exposes the
   controls; the udev rule exists only for the userspace PoC.

Each item is a separate patch with its own evidence section, and none of them
is sent anywhere without the user's explicit go-ahead.

## Explicitly out of scope / not possible

* MS-XU torch, digital window, HDR, framerate throttle, FoV2, intrinsics and
  extrinsics: not implemented by this firmware (`bmControls` says no). No
  amount of driver work creates them.
* Microphone noise suppression ("dual noise reduction mics"): firmware DSP,
  no host control exposed.
