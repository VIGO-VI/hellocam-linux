The LED not activating is very likely the `known_control` table, not the camera: `3443:930d` was deliberately left fail-closed in `ir_emitter.rs` because nobody had produced descriptor/write/read-back/optical/restore evidence for that exact identity. I have that hardware and ran it end to end, so it is proposed in #1311 — not merged as of writing.

What it answers for this camera:

- IR chain is VC interface 2 + VS interface 3; the Microsoft XU is **unit 4** with `bmControls` bit 5 set → selector **0x06**.
- `GET_LEN` 9, `GET_MAX` `01 03 03` (D0 and D1 supported, **D2 not**), `GET_DEF` `01 03 01`.
- `SET_CUR 01 03 02 00 00 00 00 00 00` (interface 3, D1) reads back identically, the LEDs visibly strobe, and captured IR frames alternate dark/lit (per-frame means 0.9 / 222.7) while D0 stays flat.
- Afterwards `GET_CUR` is `01 03 01 …` again, so the pre-existing value is restored.

So the same nine bytes the `c803` sibling uses are correct here too, and no vendor-XU poking is needed.

Two things that may matter for your machine specifically:

1. If the microphone ever streams pure digital silence, **replug the camera**. It is not the port: mine was silent on a monitor hub, recorded fine on a root port, and then recorded fine again on the same hub after a replug. `USBDEVFS_RESET` resets the USB state but does not cut VBUS, and did not help here.
2. `3443:930d` also advertises a vendor XU whose selector 8 the firmware does not implement at all (`GET_INFO` fails), and Region-of-Interest controls that are broken on its RGB terminal (`GET_CUR` answers `-EIO`; the IR terminal implements them). Neither is needed for the emitter, but they explain unrelated `uvcvideo` noise in `dmesg`.

Until #1311 lands, `sudo irlume ir-setup` should be able to find the same control on your unit; if it picks unit 4 / selector 0x06 with payload `01 03 02 00 00 00 00 00 00`, that is the one.

*(Corrected: this comment first said the entry was already in the table, blamed a monitor hub for the microphone, and attributed the ROI failure to the whole device. The measurements are unchanged; the conclusions are as above, and the later comment in this thread has the details.)*
