Both, answered.

**The two broken comments are restored.** The cause was mine: I edited them with `gh api -f body=@file`, and lowercase `-f` sends the string `@/path` literally instead of reading the file (uppercase `-F` reads it). The restored edits landed at 06:10:16 and 06:15:39 UTC — you wrote at 06:15:08, so you caught them mid-repair. The record is back as posted, with the microphone correction intact; the other comment's Region-of-Interest paragraph is now corrected in place, because the claim in it was wrong (below).

**`/var/lib/irlume/ir_emitter.conf`:**

```console
$ sudo cat /var/lib/irlume/ir_emitter.conf
3443:930d 4:6
```

**Which `uvcvideo`:** the distribution one, `7.3.3-1-cachyos`, `srcversion CDCB1BF9973BA71B9F9C978`, from `/lib/modules/7.3.3-1-cachyos/kernel/drivers/media/usb/uvc/uvcvideo.ko.zst`. The timeline from this boot:

```console
$ uptime -s
2026-11-10 23:02:07
$ journalctl -k | grep -m1 "Found UVC"
Nov 10 23:02:18 ... uvcvideo 1-3:1.0: Found UVC 1.00 device N930W 60fps (3443:930d)
```

`ir-setup` ran at 23:28-23:31, so 20 minutes after an ordinary boot with the stock driver. The out-of-tree module I built for the unrelated kernel work was last loaded at 16:39 that afternoon, before this boot. Nothing in the record depends on it.

**A correction to my earlier "second finding", so it does not travel.** I claimed `uvc_ctrls[]`'s Region of Interest entry was internally inconsistent (matching `bmControls` bit 21 while carrying selector `0x14`). That was wrong, and the hardware shows it: the Camera Terminal's `bmControls` ordering is not `selector - 1` for the UVC 1.5 additions — the driver's own table has Focus Auto at bit 17 for selector 8, Privacy at bit 18 for `0x11`, ROI at bit 21 for `0x14`, exactly as merged in `[PATCH v17 16/17]`. This camera advertising bit 21 is compliant; the firmware is what answers ROI requests with `-EIO`, and only on its RGB terminal — the IR terminal's ROI control answers `SET_CUR 1` / `GET_CUR 1` correctly, which is why any quirk for it has to be scoped to one interface rather than the device. So: device quirk, no driver bug. I have withdrawn that paragraph from the published comment.

Understood on the branch: I will not push to `hw/3443-930d-emitter` until you say the rebased head is up. Two commits, your follow-up on top, is exactly what was agreed.
