<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
Adds `3443:930d` to `known_control`, and regenerates `docs/HARDWARE.md`, with the
evidence the existing comment asked for before that identity could be trusted.

## Why

`#449` reported a NexiGo HelloCam N930W (`3443:930d`) whose IR LED stopped
activating during enrollment, while an earlier survey had classified the same
identity as RGB-only. The table kept it fail-closed pending "its descriptor and
on-device write, read-back, optical-output, and restoration evidence". This is
that evidence, from that hardware.

## Measurements

Host: CachyOS, Linux 7.3.3, camera `3443:930d`, `bcdDevice 0.06`. Nothing below is
inferred from the `c803` sibling; the payload was applied to this unit and read
back. The full `ir-setup` transcript you asked for is in the thread, and its
derivation from `GET_MAX`/`GET_DEF` lands on the same control and bytes.

| what | result |
|---|---|
| descriptor | IR chain is VC interface 2 + VS interface 3; Microsoft XU is unit 4 (`{0f3f95dc-2632-4c4e-92c9-a04782f43bc8}`) with `bmControls` bit 5 set, i.e. selector `0x06` |
| payload bounds | `GET_LEN` = 9; `GET_MAX` = `01 03 03` (D0 and D1 supported, D2 not); `GET_DEF` = `01 03 01` |
| write | `SET_CUR 01 03 02 00 00 00 00 00 00` (interface 3, D1) → `GET_CUR` reads the same bytes |
| optical output | captured IR frames alternate dark/lit in D1 (per-frame means `0.9, 222.7, 0.9, 190.4, 0.6, 236.3, …`) and stay flat in D0 (`0.1, 0.1, 0.9, 0.9, 6.4, 6.4, …`); the LEDs are visibly flashing at that cadence |
| restoration | after the run `GET_CUR` reads `01 03 01 00 00 00 00 00 00` again, the value the device reported before the write |

So this identity reaches the same MS-XU unit 4 / selector `0x06` / interface-3
D1 payload that the `c803` arm already carries, and the same nine bytes drive
the illuminator on it.

## Changes

- `crates/irlume-camera/src/ir_emitter.rs`: new `known_control` arm for
  `(0x3443, 0x930d)` reusing `HELLO_FACE_AUTH`; the `c803` comment no longer
  says the identity is unvalidated.
- the `known_control_table_is_keyed_on_usb_identity_not_a_name` test now asserts
  the `930d` arm (unit 4, selector 0x06, that payload) instead of `None`.
- `docs/HARDWARE.md` regenerated with `scripts/generate-hardware-matrix.py`;
  the `c803` row's stale "930d deliberately NOT in the table" note is gone.

## Testing

```
cargo fmt --check
cargo test -p irlume-camera known_control     # 3 passed
python3 scripts/generate-hardware-matrix.py --check
```

`irlume` is now installed here (0.15.0 from the AUR) and `sudo irlume ir-setup`
ran against this unit; that transcript is in the thread. I still did not add a
`fleet-evidence.json` host row myself, because that file's shape is yours and
the evidence it wants is in the comment rather than in my hands as a fixture.
The emitter-table row is generated from the code, as intended.

## AI assistance

The patch, the measurements above and the hardware notes were produced with an
AI coding assistant (opencode) driving the camera on this machine; every number
in this description comes from commands run against `3443:930d` here, and I
reviewed the diff before submitting.

Ref #449.
