<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Findings — NexiGo HelloCam Pro (3443:930d)

Everything below is measured on this machine (CachyOS, Linux 7.3.3) unless
marked otherwise. Commands are quoted so each claim can be re-checked.

## 1. What the hardware is

`lsusb -v -d 3443:930d` (the descriptor walk is also reproduced by
`hellocamctl info`):

```
Device: 3443:930d  "N930W 60fps" / NexiGo HelloCam Pr, bcdDevice 0.06
  Interface Association 0: Video   -> interfaces 0 (VC) + 1 (VS)
  Interface Association 2: Video   -> interfaces 2 (VC) + 3 (VS)
  Interface Association 4: Audio   -> interfaces 4 (AC) + 5 (AS)
```

Both video functions are **UVC 1.0** (`bcdUVC 0x0100`).

| Function | Interfaces | Stream | Nodes |
|---|---|---|---|
| RGB | VC 0, VS 1 | MJPG 1920x1080@60 … 640x480@60; YUYV up to 1080p@5 | `/dev/video0` (capture), `/dev/video1` (metadata) |
| IR | VC 2, VS 3 | GREY 640x360@30 only | `/dev/video2` (capture), `/dev/video3` (metadata) |
| Audio | AC 4, AS 5 | UAC1, 2 ch, S16_LE, 48 kHz, EP `0x84` async | ALSA card `N930W 60fps` |

Units per video function:

| Unit | GUID | Controls declared | Advertised (`bmControls`) |
|---|---|---|---|
| Extension 3 (RGB) | `{28f03370-6311-4a2e-ba2c-6890eb334016}` | 8 | 1,2,3,4,5,6,8 |
| Extension 4 (RGB) | `{0f3f95dc-2632-4c4e-92c9-a04782f43bc8}` = MS-XU | 16 | none |
| Extension 3 (IR) | `{28f03370-…}` | 8 | none |
| Extension 4 (IR) | MS-XU | 16 | **6 (FACE_AUTHENTICATION), 9 (METADATA)** |

The camera sits behind the monitor's USB hub: `usb-0000:02:00.0-2.1`, i.e. the
RTS5411 hub `0bda:5411` at `1-2`, not a root port.
| Camera terminal (RGB) | — | — | 2,3,4,6,10,12,14,18,22 |
| Camera terminal (IR) | — | — | 22 |

The MS-XU GUID is Microsoft's `MS_CAMERA_CONTROL_XU`: the
[Microsoft extensions to UVC 1.5](https://learn.microsoft.com/en-us/windows-hardware/drivers/stream/uvc-extensions-1-5).
Selector `0x06` is the **Face Authentication** control (it selects, per
streaming interface, D0 general-purpose / D1 alternating illumination / D2
continuous illumination) and `0x09` is the **Metadata** control. That is the
whole Windows Hello illumination path.

The other GUID (`28f03370-…`) is a vendor/Sunplus-style unit; the same GUID
appears in other Sonix/Sunplus-based webcams (e.g. `0c45:6366`), so it is a
family control block, not something NexiGo invented. Its selectors are not
documented anywhere public we have found yet — see §5.

## 2. What already works under Linux

* **RGB capture.** `v4l2-ctl -d /dev/video0 --stream-mmap` runs at 1080p60
  (MJPG), and the motorised privacy shutter visibly opens when a stream starts
  and closes when it stops — no host command involved.
* **IR capture.** `v4l2-ctl -d /dev/video2 --set-fmt-video=…pixelformat=GREY
  --stream-mmap --stream-count=30` delivers 30 fps of 640x360 GREY. The first
  frame shows the user lit in IR.
* **Both at once — at 30 fps.** RGB and IR are separate UVC functions on
  separate endpoints (`0x81`, `0x82`) and run concurrently, which is what a
  liveness check needs. But the pair is not free: measured with
  `v4l2-ctl --stream-mmap … --verbose`,

  | stream | alone | with the other one |
  |---|---|---|
  | RGB 1920x1080 MJPG | 59.86 fps | 29.57 fps |
  | RGB 1280x720 MJPG | 59.74 fps | 29.57 fps |
  | IR 640x360 GREY | 29.55 fps | 29.57 fps |

  Both clean 60 fps and 30 fps, not a ragged number, so this is the firmware
  switching to a 30/30 dual mode, not USB starvation: 720p60 MJPEG plus IR is
  far below the 480 Mbit/s link, and the camera hangs off the monitor's
  RTS5411 hub (`1-2.1`, `0bda:5411`) rather than a root port. Expect RGB 30 fps
  whenever the IR stream is open.
* **Standard controls.** Exposure (auto/manual 1…5000), white balance, gain,
  gamma, sharpness, backlight compensation, zoom 0…9, pan/tilt, focus are all
  present on `/dev/video0`.
* **Microphone is enumerated** with the right format, and the ALSA quirk from
  Linux 7.1 *is* applied:

  ```
  $ journalctl -k | grep -i 'resolution quirk'
  usb 1-2.1: set resolution quirk: cval->res = 16
  ```

  (`sound/usb/quirks.c` has `DEVICE_FLG(0x3443, 0x930d, QUIRK_FLAG_GET_SAMPLE_RATE | QUIRK_FLAG_MIC_RES_16)`.)

## 3. What does *not* work

### 3.1 The microphone is silent (open bug)

```
$ arecord -D hw:2,0 -f S16_LE -r 48000 -c 2 -d 3 mic.wav   # works, no error
$ # peak amplitude of the whole recording:
peak 0        # 288000 samples, every one zero
```

Same result through PipeWire (`pw-record --target 56`), for 8 s, and while an
RGB stream was running (so it is not gated on the shutter or on the video
clock). The device delivers full 48 kHz packets of digital silence.

The 7.1 quirk only fixes "cannot get freq at ep 0x84" (it makes the driver skip
the *read-back* of the sample rate); the `SET_CUR` of 48000 still happens. So
this is a second, different failure.

What has been ruled out:

| hypothesis | test | result |
|---|---|---|
| quirk not applied | `journalctl -k` | `set resolution quirk: cval->res = 16` on every probe |
| ADC clock not set | no `cannot set freq` error; `/proc/asound/card2/stream0` during capture | `Momentary freq = 48000 Hz`, `Packet Size = 192`, altset 1 |
| muted in software | `amixer -c 2 contents` | `Mic Capture Switch = on`, volume `1520/1520 (0 dB)` |
| muted state stuck in hardware | toggle mute off/on, re-record | still peak 0 |
| needs the video/IR clock | record while RGB streams, and while IR streams | still peak 0 |
| stale state from the pre-quirk probe | `USBDEVFS_RESET` (cold re-enumeration, quirk re-applied) | still peak 0 |
| host-side rate/packet problem | PCM runs, `delay` advances, exactly 48000 frames/s | host side is correct |

So the device delivers full, correctly paced 48 kHz packets containing digital
silence — but **only when it is plugged into the monitor's USB hub**.

### 3.1a Resolved: a stuck ADC, not the port

The first version of this file blamed the monitor's USB hub. That was wrong, and
the camera owner's replug proved it. The real variable is a **physical unplug**:

| step | port | mic |
|---|---|---|
| as enumerated at boot | monitor hub (`1-2.1`) | `peak 0`, many recordings |
| after `USBDEVFS_RESET` (cold re-enumeration) | monitor hub | `peak 0` |
| after a physical unplug and replug | root port (`1-3`) | `peak 5093`, audio |
| after another physical unplug and replug | monitor hub (`1-2.1`) | `peak 1356`, audio |

So the hub is fine, and so is the driver: `USBDEVFS_RESET` resets the device's
USB state but does not remove bus power, which is why it did not clear the
condition. A replug does. Something in the audio block latches into a state only
a VBUS cycle clears; what triggers it is still unknown, because it was seen once
and is not reproducible on demand.

The ALSA side was verified correct throughout and is not implicated: the
`QUIRK_FLAG_GET_SAMPLE_RATE | QUIRK_FLAG_MIC_RES_16` entry is applied on every
probe, `Momentary freq` reports 48000 Hz with 192-byte packets, and the mixer is
unmuted at 0 dB.

Practical advice for other users, which is all that can be given honestly:
**if the microphone streams digital silence, replug the camera**; no software
reset, port change or mixer change has been observed to help. A real fix would
need either per-port power switching (`uhubctl`-style, which this hub does not
appear to expose) or knowledge of what puts the ADC in that state — neither is
available today.

### 3.2 The Microsoft XU is invisible to V4L2

`uvc_ctrl.c:uvc_ctrl_init_ctrl()` only instantiates controls that appear in the
driver's static `uvc_ctrls[]` table (matched by entity GUID + selector).
Unknown GUIDs are skipped entirely, so:

```
$ v4l2-ctl -d /dev/video2 --list-ctrls
   region_of_interest_rectangle …
   region_of_interest_auto_ctrls …
```

— no `Extension 4:6`. The IR illuminator therefore has **no V4L2, no
libcamera, no PipeWire, no Chrome path** at all. Windows reaches it through the
same control with its own driver.

There is, however, a **documented, unprivileged** path to those controls:
`UVCIOC_CTRL_QUERY`, uvcvideo's own XU pass-through (`uvc_xu_ctrl_query()`).
It addresses a control as (unit id, selector) on the chain behind a video
node, performs the UVC class request for you, and — crucially — the driver
only has controls the descriptor advertises, so an unadvertised selector fails
with `ENOENT` instead of reaching the device. This tool uses it:

```
struct uvc_xu_control_query { u8 unit; u8 selector; u8 query; u16 size; u8 *data; };
#define UVCIOC_CTRL_QUERY _IOWR('u', 0x21, struct uvc_xu_control_query)
```

No root, no udev rule, no claiming the USB interface, and it works while
uvcvideo is streaming. Raw `usbfs` is kept as a fallback (`--usbfs`) but is
worse in every way here: usbfs refuses *any* ioctl on a read-only descriptor,
and class requests to an interface owned by a kernel driver fail with
`EBUSY` unless the driver is detached.

The *metadata* half of the MS-XU is already handled in mainline: since
Ricardo Ribalda's `V4L2_META_FMT_UVC_MSXU_1_5` series, `uvc_meta_detect_msxu()`
finds the MS-XU, sets `MSXU_CONTROL_METADATA` to `GET_MAX` at probe time and
offers the new format. Confirmed here:

```
$ v4l2-ctl -d /dev/video3 --list-formats-meta
  [0]: 'UVCH' (UVC Payload Header Metadata)
  [1]: 'UVCM' (UVC MSXU Metadata)
$ v4l2-ctl -d /dev/video3 --set-fmt-meta 1 --stream-mmap --stream-count=20 …
  4092 bytes per frame at 30 fps
```

So selector `0x09` needs no work; selector `0x06` (face authentication) is the
only missing MS-XU control on this camera.

### 3.2a The IR illuminator now works, and it is proven

`hellocamctl ir on` writes the Face Authentication payload
`01 03 02 00 00 00 00 00 00` (one entry: streaming interface 3, flags D1 =
alternating illumination), reads it back, and `ir off` writes the D0 value.
Measured per-frame brightness of `/dev/video2` at 640x360 GREY:

```
ir on  (D1 strobing): 9.1 100.9   9.0 100.5   9.2  86.2   6.2  85.9   6.2  68.0 ...
ir off (D0):          1.4   1.4   2.5   2.5  31.8  31.8  35.5  35.6  38.1  38.1 ...
```

In D1 consecutive frames differ by an order of magnitude — dark / lit / dark /
lit — which is exactly what the Windows Hello illuminator does. In D0 every
value appears twice (the sensor's own ~15 fps readout delivered at 30 fps) and
there is no alternation at all, just ambient light. The IR LEDs are also
visible as a dim red flash at that cadence, so this is independently confirmed
by eye, not only by the frame statistics.

`GET_MAX` reports `01 03 03 …` — interface 3 supports D0 and D1, not D2 — and
`GET_DEF`/`GET_CUR` were `01 03 01 …` (D0) before the test and are D0 again
after it, so the camera is left exactly as found.

**Independently confirmed by irlume 0.15.0.** `sudo irlume ir-setup`, which
derives the value from `GET_MAX`/`GET_DEF` and refuses to write to units that
advertise nothing, produced byte-for-byte the same control and payload —
`IR emitter enabled: 4:6:1,3,2,0,0,0,0,0,0 … accepted: interface 0x03 set to
D1 (alternative illumination)` — and its dry run listed unit 3 as
vendor-defined with no advertised selectors and unit 4 as the Microsoft unit
advertising `[0x06, 0x09]`. Two independent derivations agreeing is the
strongest evidence available short of the vendor's own document.

### 3.2b Vendor XU (`28f03370-…`) — what is actually in it

Read-only dump of the seven advertised selectors, RGB chain, unprivileged:

| sel | len | GET_CUR | shape |
|---|---|---|---|
| 0x01 | 4 | `00000100` | u32, `GET_DEF` = 1, max 0xffffffff, res 1 |
| 0x02 | 64 | `…4d221c00100b0000` + UTF-16LE `"Cam Pro Audio"` | audio device descriptor + name |
| 0x03 | 11 | `0000300000…` | UTF-16LE `"0"` after two leading bytes |
| 0x04 | 11 | all zero | |
| 0x05 | 11 | `4904010000…` | u32 0x00010449 |
| 0x06 | 64 | `40 00 00 …` | 64 as a single byte |
| 0x08 | — | `GET_INFO` fails, `ENOENT` | advertised in `bmControls` but not implemented |

Selector 8 is the interesting one: the descriptor claims it, but uvcvideo's
delayed control init gets no `GET_INFO` answer and drops it, so it is not even
reachable. That is a device descriptor lie worth knowing about (and a reason
never to poke an unadvertised selector).

None of these looks like a microphone gate; they look like identification and
version strings. Selector 1 (4 bytes, default 1) is the only plausible
feature switch, and it is *not* being written without the owner's say-so.

### 3.3 Region-of-interest controls are broken on this firmware

```
$ journalctl -k | grep -i 'non compliance'
uvcvideo 1-2.1:1.0: UVC non compliance: permanently disabling control 981ae2
  (Region of Interest Auto Ctrls), due to error -5
```

The camera terminal advertises ROI but answers `-EIO`. `v4l2-ctl --list-ctrls`
on `/dev/video0` also prints `error 5 getting ext_ctrl Region of Interest
Rectangle`. Cosmetic, but a clean candidate for a small uvcvideo quirk.

### 3.4 Vendor XU (NexiGo Windows software features)

The Windows "NexiGo Webcam Settings" app exposes zoom (3x digital), "facial
enhancement", 3DNR and low-light correction. The 7 advertised selectors of
unit 3 are presumably those. Nothing is known publicly about their layout, so
they are being probed read-only (`GET_INFO`, `GET_LEN`, `GET_CUR`, `GET_DEF`,
`GET_MIN`, `GET_MAX`, `GET_RES`) before any write.

### 3.5 MS-XU controls the device does *not* implement

The MS-XU advertises only selectors 6 and 9. Everything else in the Microsoft
spec — IR torch (`0x0a`), digital window (`0x0b`/`0x0c`), video HDR (`0x0d`),
framerate throttle (`0x0e`), field of view 2 (`0x0f`/`0x10`), intrinsics and
extrinsics — is **not implemented by this camera's firmware**, on either
function. A `GET_INFO` probe is run read-only to confirm the device stalls on
them; no write is attempted. So there is no hidden HDR control to unlock here,
even though the product page advertises "low light correction" (that is ISP
behaviour, likely behind the vendor XU).

## 3.6 Kernel path: native V4L2 control (proof of concept, proven)

`kernel/patches/0001-uvcvideo-expose-MS-XU-face-authentication.patch` adds a
`Face Authentication Mode` menu control for Microsoft XU cameras. Measured with
the module loaded and nothing else touching the device:

```
$ v4l2-ctl -d /dev/video2 --list-ctrls-menus
  face_authentication_mode 0x00981900 (menu) : min=0 max=2 default=0 value=0
      0: General purpose   1: Alternating illumination   2: Continuous illumination
$ hellocamctl v4l2test
[PASS] native V4L2 control present / VIDIOC_S_CTRL accepted / image changes / restored
5/5 checks passed
```

Frame brightness with the control alone:

```
mode 1:  0.9 222.7   0.9 190.4   0.6 236.3   0.4 77.0 ...
mode 0:  0.1   0.1   0.9   0.9   6.4   6.4   6.4   6.4 ...
```

Final build verified (srcversion 998F94BDB85BFC06F7FD3E): ROI controls gone from
both nodes, zero "non compliance" warnings since load, `UVCM` metadata still
offered on `/dev/video3`, mic still recording, `v4l2test` 5/5.

Three things learned while building it, all worth carrying upstream:

* **The camera does not answer UVC class requests during probe.** `GET_LEN` on
  the MS-XU returns `-EAGAIN` at that point, so a driver that probes the
  control at init will conclude it is unsupported. Anything that needs the
  payload size has to either trust the descriptor or defer the query.
* **`GENMASK()` takes bit positions, not a mask value.** `GENMASK(BIT(2), 0)`
  silently produced a five-entry menu and `QUERYMENU` read two names past the
  array.
* **uvcvideo's Region of Interest entry is internally inconsistent.** This
  camera advertises ROI at `bmControls` bit 21, and `uvc_ctrls[]` matches that
  index — but the same entry carries `.selector = UVC_CT_REGION_OF_INTEREST_CONTROL`
  which is 20, so the driver ends up sending requests for a control number the
  firmware does not implement (`-EIO`, then "permanently disabling control
  981ae2"). Either the `.index` or the selector is wrong; it deserves its own
  bug report rather than being papered over by the blacklist above.

## 4. Side discovery: the monitor's "headset mic"

`lsusb` shows `0bda:4cb6 Realtek "LG Monitor Headset MIC"`. Its full
descriptor has **one HID interface and no audio interface**:

```
bNumInterfaces 1, bInterfaceClass 3 (HID), 1 interrupt endpoint, 96-byte report
descriptor = consumer controls (volume/media keys) + vendor feature report
```

So that device cannot deliver microphone audio to Linux (or to Windows), and
the monitor's 3.5 mm jack is fed from HDMI/DP audio — output only. The
"Headset MIC" name is a generic Realtek string. Nothing to fix in Linux; this
is why the machine's only capture source is the camera (card 2).

## 5. Questions, and what settled them

Three things were open when this file was first written; all three are now
answered, so nothing here waits on more hardware.

1. **Does selector `0x06` D1 really switch the illuminator on this revision
   (`bcdDevice 0.06`)?** Yes. `hellocamctl selftest` writes D1, reads it back,
   captures IR frames, writes D0, captures again, and restores the original:
   11/11 checks, twice, on two different USB ports, with the dark/lit
   alternation and the visible LED flash described in 3.2a.
2. **Is the microphone gate in the vendor XU?** No. The silence was the
   monitor's USB hub (3.1a); the vendor unit's seven selectors are
   identification and version strings, and none of them is written by anything
   here.
3. **Is the mic silence firmware or hardware?** Neither: topology. Same device,
   same driver, real audio on a root port and digital zeros behind the hub.

Genuinely still open, and only answerable with vendor documentation: what the
vendor XU's selectors are *for* (3.2b). They stay read-only.
