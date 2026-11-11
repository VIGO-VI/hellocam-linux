Published the tool and the rest of the work, since it makes the numbers above checkable without my machine: **https://github.com/VIGO-VI/hellocam-linux** (GPL-2.0-or-later).

What is in it, in case any of it is useful for the record:

- `hellocamctl` — the tool that produced the measurements (single file, Python standard library only, no root, no udev rule). `hellocamctl doctor`, `xu`, `ir status|on|off`, `capture`, `mic`, `selftest` (11 checks, writes D1, captures, writes D0, captures, restores), `v4l2test`.
- `docs/FINDINGS.md` — the descriptor model, and the three-way split between "works out of the box / works only with help / firmware does not implement it".
- `kernel/` — an out-of-tree `uvcvideo` proof of concept in two patches (the face-authentication menu control, and a quirk dropping this camera's broken Region-of-Interest bits). `kernel/fetch-sources.sh` pulls the v7.3 sources rather than vendoring them; `pristine + patches` reproduces the tree that built. Those patches have not been sent anywhere.

*Correction, same day:* this comment originally described a "silent microphone behind a monitor hub" as a finding. That was wrong — the camera went back on the same hub and records audio after a physical replug. What differs between the silent and working states is a bus-power cycle, not the port, and `USBDEVFS_RESET` does not cut VBUS. The repo's `docs/FINDINGS.md` now says that.

Two small things in the non-irlume part that may interest you as a uvcvideo maintainer-adjacent finding, since they are generic rather than NexiGo-specific:

1. `uvc_ctrls[]`'s Region of Interest entry matches `bmControls` bit 21 but carries `.selector = UVC_CT_REGION_OF_INTEREST_CONTROL` (20), so the driver talks to a control number the device does not implement: `-EIO`, then "permanently disabling control 981ae2". Either the index or the selector looks wrong.
2. This camera returns only the count byte for `GET_MIN`/`GET_RES` on the MS-XU face-authentication control, as the Microsoft document says it should, while `uvc_query_ctrl()` asks for the full 9 bytes and logs "returned 1 bytes when we expected 9". Harmless, but it is noise a driver-sized control cannot avoid today.
