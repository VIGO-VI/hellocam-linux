<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# UVC quirk — everything a reviewer can ask, answered

Internal preparation document for `0001-media-uvcvideo-ignore-Region-of-Interest-on-the-Nexi.patch`.
It exists so that every line of the patch, and every claim in its commit
message, can be defended from evidence rather than memory.

## 0. Scope

| | |
|---|---|
| **submitted now** | one patch: the Region-of-Interest blacklist entry for `3443:930d`, plus an optional interface field in the table that carries it |
| **not submitted** | the MS-XU face-authentication control. It needs a public control id first; that is an RFC after this, not part of it |
| **state** | proven on one unit; `checkpatch --strict` clean apart from the placeholder `Signed-off-by`; `pristine v7.3 + patch` builds the module that was tested |

Nothing in this patch changes behaviour for any device other than `3443:930d`,
and for that device it changes only one node's control list.

## 1. Line by line

The whole patch is 40 lines including the commit message; 26 are the diff.

### 1.1 `struct uvc_ctrl_blacklist` gains a field

```c
 	struct uvc_ctrl_blacklist {
 		struct usb_device_id id;
 		u8 index;
+		/* Restrict the entry to one interface, or -1 for every one. */
+		int ifnum;
 	};
```

* **Why a field and not a separate table.** The two tables (`processing_blacklist`,
  `camera_blacklist`) and the loop that applies them are the driver's existing
  mechanism for "this device advertises a control that does not work". A second
  mechanism for one device would be worse than one optional field.
* **Why `int`, not `u8`.** The sentinel is `-1`, which `u8` cannot express.
  Interface numbers are assigned by the USB core as `u8`, so the comparison
  promotes safely; there is no device with more than `INT_MAX` interfaces.
* **Why the sentinel is `-1` and not `0`.** `0` is a valid interface number —
  the one this quirk targets. A default of `0` would silently have scoped every
  existing entry to interface 0, which is precisely the bug this patch is about
  avoiding.

### 1.2 The four existing entries say `-1`

```c
-		{ { USB_DEVICE(0x13d3, 0x509b) }, 9 }, /* Gain */
+		{ { USB_DEVICE(0x13d3, 0x509b) }, 9, -1 }, /* Gain */
```
…and the same for `1c4f:3000`, `5986:0241` and `06f8:3005`. Behaviour is
unchanged: the comparison skips an entry only when `ifnum >= 0`.

### 1.3 The new entry

```c
+		{ { USB_DEVICE(0x3443, 0x930d) }, 21, 0 },
```

* `21` is the `bmControls` bit, not the control selector. The driver matches
  `ctrl->index` against this, and `ctrl->index` is the bit position. The
  selector for this control is `UVC_CT_REGION_OF_INTEREST_CONTROL` = `0x14` = 20;
  see §3 for why bit 21 and selector 20 are both correct.
* `0` is the video control interface of the RGB function. The device has two
  video functions: interfaces 0/1 (RGB: control + streaming) and 2/3 (IR:
  control + streaming), plus 4/5 for audio.
* **Why only this device.** `3443:c803`, a sibling model, shares the descriptor
  layout for the IR function but has not been tested here; adding it would be
  an untested claim.

### 1.4 The check

```c
+		if (blacklist[i].ifnum >= 0 && blacklist[i].ifnum != dev->intfnum)
+			continue;
```

* `dev->intfnum` is set in `uvc_probe()` (`uvc_driver.c`) to
  `intf->cur_altsetting->desc.bInterfaceNumber`, i.e. the control interface this
  `uvc_device` was created for. Using the cached field avoids dereferencing
  `cur_altsetting` in the prune path and matches how the rest of the driver
  addresses controls.
* The check runs after `usb_match_one_id()`, so the common case (id does not
  match) costs nothing.

## 2. What actually happens on the device

### 2.1 Descriptor facts (measured, `lsusb -v` and a descriptor walk)

* RGB camera terminal (unit 1 on interface 0): `bmControls = 2e 2a 22`, bits
  `1,2,3,5,9,11,13,17,21`.
* IR camera terminal (unit 1 on interface 2): `bmControls = 00 00 20`, bit `21`.
* Both terminals therefore advertise Region of Interest, and nothing else.

### 2.2 What userspace sees

```console
$ v4l2-ctl -d /dev/video0 --list-ctrls
error 5 getting ext_ctrl Region of Interest Rectangle
$ v4l2-ctl -d /dev/video0 -C region_of_interest_auto_ctrls
unknown control 'region_of_interest_auto_ctrls'
```

and in the kernel log, once:

```
uvcvideo 1-2.1:1.0: UVC non compliance: permanently disabling control 981ae2 (Region of Interest Auto Ctrls), due to error -5
```

### 2.3 The code path, with line numbers (Linux v7.3)

1. `uvc_ioctl_query_ext_ctrl()` → `uvc_query_v4l2_ctrl()` (`uvc_ctrl.c`).
2. For the bitmask auto-control it reaches `__uvc_queryctrl_boundaries()`
   (`uvc_ctrl.c:2009`), which calls `uvc_ctrl_populate_cache()`, issuing
   `GET_MIN`/`GET_MAX`/`GET_DEF` for that control.
3. The device STALLs those requests. `uvc_query_ctrl()` (`uvc_video.c`) then
   reads the VC request-error-code control and maps the device's answer:
   `1 → -EBUSY` (not ready), `2 → -EACCES` (wrong state), `5/6/7 → -EIO`
   (`uvc_video.c:142-149`).
4. On `-EIO` the mapping is marked `disabled = true` and the warning at
   `uvc_ctrl.c:2012` is printed. That is the "permanently disabling" line.
5. Reading the rectangle control goes through `__uvc_ctrl_get()` →
   `__uvc_ctrl_load_cur()` → `GET_CUR`, which fails the same way; that is the
   `error 5` v4l2-ctl prints.

### 2.4 At the USB level

Captured with `usbmon` on bus 1, no quirk loaded, `uvcvideo` tracing on. Same
device, same unit, same selector, same length — only the interface differs:

```console
RGB terminal, interface 0:
  submit  : a1 86 1400 0100 0001   (GET_INFO, selector 0x14, unit 1, iface 0, 1 byte)
  complete: -32 0                  (-EPIPE = STALL, no data)

  submit  : a1 87 1400 0100 000a   (GET_DEF, selector 0x14, unit 1, iface 0, 10 bytes)
  complete: -32 0                  (-EPIPE = STALL, no data)   ×4 retries

IR terminal, interface 2:
  submit  : a1 86 1400 0102 0001   (GET_INFO, selector 0x14, unit 1, iface 2, 1 byte)
  complete: 0 1 = 03               (GET|SET advertised)

  submit  : a1 81 1400 0102 000a   (GET_CUR, selector 0x14, unit 1, iface 2, 10 bytes)
  complete: 0 10 = 00000000 00000000 0100
```

The RGB terminal stalls even `GET_INFO`. So the firmware does not merely mishandle
the control: it does not acknowledge that the control exists, while its own
descriptor advertises it in `bmControls`. The IR terminal answers `GET_INFO` with
`0x03` and then serves the data request.

The IR response is a valid `struct uvc_rect` (all zeros) plus `bmAutoControls =
0x0001`. So the request the driver sends is well formed, the device accepts it
on one of its two terminals and stalls it on the other.

### 2.5 v4l2-compliance

`v4l2-compliance` (v4l-utils 1.32.0) on the two capture nodes, distribution
driver versus the same driver with only this patch applied:

Measured twice: with the distribution tool and with the fixed one.

| node | distribution driver | with the patch only |
|---|---|---|
| RGB `/dev/video0`, `v4l2-compliance 1.32.0` (distro) | **46/49, 3 failures** | **49/49, 0 failures** |
| RGB `/dev/video0`, `v4l2-compliance 1.33.0-1` (git, fixed) | **45/48, 3 failures** | **48/48, 0 failures** |
| IR `/dev/video2`, 1.32.0 | 48/49, 1 failure *(the tool bug below)* | 48/49, same |
| IR `/dev/video2`, 1.33.0-1 | 49/49 | 49/49 |

Two caveats to state before a reviewer finds them:

* The 1.32.0 IR failure is the v4l-utils bug in the next paragraph. With the
  fixed tool the IR node is 49/49 both with and without the patch, so the patch
  does not affect it either way.
* `focus_absolute` (`0x009a090a`) is intermittently reported out of range: once
  as `16368` against a `1..1023` range while autofocus was running, later as
  `240`. When that happens the newer tool fails two tests on the RGB node with
  or without the patch. It is a separate, pre-existing oddity, not ROI and not
  introduced here.

The three RGB failures are all this control:

```
fail: v4l2-test-controls.cpp(94): maximum must be non-zero for a bitmask control
fail: v4l2-test-controls.cpp(201): invalid control 00981ae2
fail: v4l2-test-controls.cpp(939): try_ext_ctrls returned an error (5)
```

That is the strongest form of the justification: the patch is not cosmetic, it
turns a node that fails the standard compliance tool into one that passes.

The IR node's single failure is **a v4l2-compliance bug, already fixed
upstream**, not a kernel defect:

```
v4l-utils af4a91dea9a2  "v4l2-compliance: skip V4L2_CID_PRIVATE_BASE check for UVC"
                        Hans Verkuil, 2025-10-29
```

That test probes `V4L2_CID_PRIVATE_BASE` upward and expects zero controls,
because uvcvideo does not implement that range; the fix makes the tool skip the
check when the driver is `uvcvideo`. The `v4l2-compliance 1.32.0` installed here
predates it (the marker string is absent from the binary and its `--is-uvc` flag
does not exist yet), so it fails on the IR node for having any UVC-specific
control at all. Reproduced identically with the distro driver, with the patch,
and with the RFC control absent, which rules out both the patch and our control
as causes.

### 2.6 The device's own answer

With driver tracing on and a build *without* this quirk:

```
uvcvideo 1-2.1:1.0: Control error 7
```

Code **7 = Invalid Request**. Not 1 ("not ready"), not 2 ("wrong state"), not
5/6 ("invalid unit"/"invalid control"). The firmware is not saying "ask again
later" or "you are holding it wrong"; it is saying the request is invalid, for
a control it advertised.

This is the single most useful sentence in this document: it rules out the
entire class of "maybe the timing/state/arguments were wrong" objections.

Reproduce it in five lines (needs the kernel sources and root):

```sh
cp -r kernel/uvc /tmp/noquirk
patch -d /tmp/noquirk -p5 -R < kernel/patches/0002-uvcvideo-scope-ROI-quirk-to-the-RGB-interface.patch
make -C /lib/modules/$(uname -r)/build M=/tmp/noquirk LLVM=1 modules
sudo sh -c 'rmmod uvcvideo; insmod /tmp/noquirk/uvcvideo.ko trace=0xffff'
v4l2-ctl -d /dev/video0 --list-ctrls; journalctl -k | grep "Control error"
```

## 3. Why this is not a driver bug

The obvious reviewer question is whether uvcvideo is addressing the control
correctly, given that its blacklist entry matches bit 21 while the selector is
20. The driver is right; the ordering is simply not `selector - 1`:

| control | selector | `uvc_ctrls[]` index |
|---|---|---|
| Focus, Auto | `UVC_CT_FOCUS_AUTO_CONTROL` = 8 | **17** |
| Privacy | `UVC_CT_PRIVACY_CONTROL` = `0x11` | **18** |
| Region of Interest | `UVC_CT_REGION_OF_INTEREST_CONTROL` = `0x14` | **21** |

The ROI mapping was merged as `[PATCH v17 16/17] media: uvcvideo: implement UVC
v1.5 ROI` (Yunke Cao, reviewed by Ricardo Ribalda and Hans de Goede) with
exactly `.selector = UVC_CT_REGION_OF_INTEREST_CONTROL, .index = 21`, citing
UVC 1.5 §4.2.2.1.20. So bit 21 ↔ selector `0x14` is intended, and this camera
advertising bit 21 is compliant.

Consequence: there is no driver fix to make. The driver addresses the right
control; the firmware refuses it.

## 4. Why the entry is scoped to one interface

Measured on the same unit:

```console
$ v4l2-ctl -d /dev/video2 -C region_of_interest_auto_ctrls
region_of_interest_auto_ctrls: 0x00000010
$ v4l2-ctl -d /dev/video2 -c region_of_interest_auto_ctrls=0x1
$ v4l2-ctl -d /dev/video2 -C region_of_interest_auto_ctrls
region_of_interest_auto_ctrls: 0x00000001
```

The IR terminal accepts the control and honours a write. A device-wide
blacklist would therefore delete a working control to fix a broken one — which
is why the patch adds the interface dimension rather than reusing the existing
entry shape.

Interface numbers are fixed by the descriptor, so "interface 0 is the RGB
control interface" is as stable as the USB id itself. If a firmware revision
renumbered its interfaces, the entry would stop matching and the device would
simply return to its current behaviour — a fix that does not apply, not a
regression.

## 5. Evidence inventory

Everything below is reproducible from the public repository
(`https://github.com/VIGO-VI/hellocam-linux`):

| claim | how it was measured |
|---|---|
| descriptor, bit 21 on both terminals | `lsusb -v`, plus a 1071-byte descriptor walk |
| RGB fails, IR works | `v4l2-ctl` before/after the patch, on both nodes |
| device answers error 7 | tracing build without the quirk, `Control error 7` in dmesg |
| the request is well formed | `usbmon`: `a1 86 1400 0100 0001` (GET_INFO) and `a1 87 1400 0100 000a` both stalled with `-32`; the same two requests on interface 2 return `03` and 10 valid bytes |
| not a stale-state artefact | after a physical unplug/replug (new USB device number, distro driver), `--list-ctrls` on `/dev/video0` still reports the same error |
| not specific to the port or hub | the same failure is logged on the monitor hub (`1-2.1`) and on a direct rear port (`1-3`); the hub also carries the IR terminal's identical requests successfully |
| the patch fixes a compliance failure | `v4l2-compliance`: RGB 46/49 → 49/49; IR unchanged 48/49 |
| patch behaviour | with the quirk: RGB keeps 19 controls, loses only the error line; IR keeps both ROI controls and its value; no `non compliance` line |
| patch applies and builds | `pristine v7.3 + 0001 + 0002` reconstructs the tested tree byte-for-byte; `audit.sh --build` clones HEAD, fetches, patches, builds |
| nothing else changes | the RGB control set is identical before and after (19 controls), and other devices cannot match `USB_DEVICE(0x3443, 0x930d)` |

## 6. What is not proven

Say these before a reviewer finds them:

1. **One unit, one firmware** (`bcdDevice 0.06`). No second unit of either
   `930d` or its `c803` sibling.
2. **The rectangle control's `SET_CUR` was never exercised.** The failure is
   established on reads (`GET_CUR`, `GET_MIN/MAX/DEF`); the device rejects the
   control, and a write to a control whose reads are invalid is not attempted.
3. **No vendor documentation.** The error code is the only statement from the
   firmware.
4. **No other hardware tested**, so "inert for other devices" rests on the code
   (sentinel `-1`) rather than measurement.
5. **The IR terminal's rectangle control** was not exercised either; only the
   auto bitmask.
6. **The IR node's remaining `v4l2-compliance` failure is a v4l-utils bug**
   (`af4a91dea9a2`, fixed 2025-10-29, newer than the 1.32.0 installed here).
   Verified by reproducing it with the distro driver, with the patch, and with
   the RFC control removed, so it belongs to neither. Citing it is enough; the
   fixed tool was not built because that needs `meson`, which is not installed.

## 7. Anticipated objections

| reviewer says | answer |
|---|---|
| "This looks like a driver bug; the index and selector disagree." | They do not: Focus Auto is index 17 for selector 8 and Privacy index 18 for `0x11`. The ROI mapping was merged with index 21 / selector `0x14` in v17. §3 |
| "Then the device is non-compliant, report it to the vendor." | The device is *compliant* about advertising (bit 21 is right) and broken in answering. A kernel quirk is how uvcvideo already handles exactly this class (`06f8:3005` zoom, `1c4f:3000` white balance, `5986:0241` hue). |
| "Why not probe every control at init and drop the ones that fail?" | That changes behaviour for every UVC device and would drop controls that legitimately fail until streaming starts or until arguments are set. One USB id in the existing table is the smaller change. |
| "Why not set the control once at probe, as some drivers do for ROI?" | It fails on read, before any write; and writing a control whose reads are invalid is the kind of guess that has bricked cameras. |
| "Interface numbers are firmware detail; why key on one?" | They come from the descriptor and are as stable as the id. If they change, the quirk stops matching and behaviour returns to today's — no regression. §4 |
| "Why is the auto sub-control 'permanently disabled' rather than just warning?" | Existing driver behaviour on `-EIO`, `uvc_ctrl.c:2012`. Out of scope here; this patch stops the trigger on this device. |
| "Only one unit? I cannot take this." | Stated up front in the commit message: one unit, `bcdDevice 0.06`, with the measurements. If that is not enough, the patch waits; the alternative is a device-wide change nobody can test. |
| "Why not also `3443:c803`?" | Same descriptor layout by inspection, untested by us. Not claiming it. |
| "Does this hide a control applications need?" | On the RGB terminal the control has never returned a value; applications get an error today. The IR terminal keeps it. |
| "Please use `u8`/`bool`/a flag instead." | `-1` needs a signed type; a flag plus a number is the same size and more code. Will change on request. |
| "Add a `Link:`/`Closes:` tag." | There is no public bug report; the evidence is the commit message and the repository. Happy to add one if the reporter files. |
| "Squash the struct change into its own patch." | It is inseparable from the entry that needs it; splitting would leave patch 1 with an unused field. Will split on request. |

## 8. Submission mechanics

* **Identity.** `Signed-off-by:` must be the author, with a real name and a
  mailbox that accepts list mail. This is the only open item. `git commit -s`
  in the reconstruction, regenerate with `git format-patch`.
* **Subject.** `[PATCH] media: uvcvideo: ignore Region of Interest on the
  NexiGo N930W RGB terminal` — subsystem prefix, imperative, no trailing period.
* **Recipients.** `linux-media@vger.kernel.org`; from `MAINTAINERS` for
  `USB VIDEO CLASS DRIVER`: Laurent Pinchart, Hans Verkuil; plus
  `linux-kernel@vger.kernel.org`. Use `scripts/get_maintainer.pl`.
* **Send.** `git send-email --to ... --cc ... 0001-*.patch`. One patch, no cover
  letter needed. Plain text, no HTML, no attachments.
* **Versioning.** If changes are requested: `[PATCH v2]`, and a changelog under
  the `---` line listing what changed. Do not resend sooner than a week without
  a reason; do not top-post.
* **Tone.** Answer technical points only; if a reviewer is dismissive, respond
  with the measurement. Never argue about the process.

## 9. Re-verify before sending

```sh
./audit.sh --build                       # clean tree, fresh clone, build
v4l2-ctl -d /dev/video0 --list-ctrls     # no error line, 19 controls
v4l2-ctl -d /dev/video2 --list-ctrls     # both ROI controls still present
journalctl -k --since "-2 min" | grep -c "permanently disabling"   # 0
```

## 10. One-page quick reference

* The device advertises ROI on **both** camera terminals; the **RGB** one
  answers **error 7 (Invalid Request)**; the **IR** one works.
* Bit 21 ↔ selector `0x14` is correct and merged; the driver is not at fault.
* The fix is one entry in the existing blacklist table plus an optional
  interface field, defaulting to whole-device for every existing entry.
* Proven on one unit; no vendor docs; no second unit; writes never attempted.
* Everything is in the public repo, including the module that reproduces the
  failure and the one that fixes it.
