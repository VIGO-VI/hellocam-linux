<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
The LED not activating is very likely the `known_control` table, not the camera: `3443:930d` was deliberately left fail-closed in `ir_emitter.rs` because nobody had produced descriptor/write/read-back/optical/restore evidence for that exact identity. I have that hardware and ran it end to end, so it is now in the table: #1311.

What it answers for this camera:

- IR chain is VC interface 2 + VS interface 3; the Microsoft XU is **unit 4** with `bmControls` bit 5 set → selector **0x06**.
- `GET_LEN` 9, `GET_MAX` `01 03 03` (D0 and D1 supported, **D2 not**), `GET_DEF` `01 03 01`.
- `SET_CUR 01 03 02 00 00 00 00 00 00` (interface 3, D1) reads back identically, the LEDs visibly strobe, and captured IR frames alternate dark/lit (per-frame means 0.9 / 222.7) while D0 stays flat.
- Afterwards `GET_CUR` is `01 03 01 …` again, so the pre-existing value is restored.

So the same nine bytes the `c803` sibling uses are correct here too, and a firmware that ignores debounce is not needed — no vendor-XU poking either.

Two things that may matter for your machine specifically:

1. If the camera sits on a **monitor's USB hub**, move it to a root port. On mine the microphone streamed pure zeros behind a Realtek RTS5411 hub and worked immediately on a rear port; video was unaffected either way.
2. `3443:930d` also advertises a vendor XU whose selector 8 the firmware does not implement at all (`GET_INFO` fails), and Region-of-Interest controls that answer `-EIO`. Neither is needed for the emitter, but they explain unrelated `uvcvideo` noise in `dmesg`.

Until #1311 lands, `sudo irlume ir-setup` should be able to find the same control on your unit; if it picks unit 4 / selector 0x06 with payload `01 03 02 00 00 00 00 00 00`, that is the one.
