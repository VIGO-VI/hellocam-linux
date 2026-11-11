<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Face unlock on this camera, as actually set up

Recorded because the order matters and two of the steps fail if taken in the
"obvious" sequence. irlume 0.15.0, CachyOS, `3443:930d` on a monitor hub.

## Sequence that works

1. **Enrol first.** `irlume enroll --name face` (a polkit dialog approves each
   capture). The template key is created here.
2. **Then wrap the key.** `irlume recovery setup` creates the recovery
   passphrase and seals the template key. Run it *before* enrolling and it
   fails with `policy: no template key sealed for 'greenstar'` — there is
   nothing to wrap yet. Between 1 and 2 the template is plaintext, so the gap
   should be short.
3. `irlume detect` → `ready`.
4. `irlume identify` until it matches. A miss here is nearly always **gaze**,
   not image quality: the checker prints `yaw/pitch` and rejects a face that is
   looking at the screen rather than the lens.
5. `sudo irlume login enable --apply`. On this machine that wires
   `/etc/pam.d/plasmalogin` and `/etc/pam.d/kde` (both materialised as
   overrides of the `/usr/lib/pam.d/` vendor copies) and `/etc/pam.d/sddm`
   (with a `.pre-irlume` backup). Password stays the fallback.
6. Lock screen test: empty password + Enter. The `kde` service runs PAM as the
   user, so it verifies identity but deliberately does not release the keyring
   secret — that is the expected `UnsealPassword refused for uid 1000` line.
7. `irlume keyring arm` only helps the **greeter/boot** (root PAM context),
   not the lock screen.

## What the dark path needed

Measured on this unit with `irlume identify`, lights off, monitor glow only:

| enrolment | dark score | note |
|---|---|---|
| 10 scans, enrolled in room light | 0.679 then 0.647 | bar is `IR_DARK_MATCH_THRESHOLD` 0.635 → passing by ~0.01-0.04 on a score that swings ~0.03 |
| + dark-room scans at the real login distance | **0.743** | margin ~0.11, no longer marginal |

The lesson is not "lower the threshold": a vinyl print of the enrolled user
measures 0.650 in IR, so 0.647 has no business being comfortable. The fix is to
enrol in the condition you log in under — same lighting, same distance, same
glasses — and to fill more of the 640x360 IR frame, which is the strongest
lever on embedding quality.

## Measured facts about the camera that irlume agrees with

* Capture mode: irlume measured and persisted **sequential** —
  "concurrent capture keeps 73% of RGB and 110% of IR brightness". That matches
  the 30/30 fps dual-stream ceiling found by hand (see `FINDINGS.md` 2).
* The emitter control: `irlume ir-setup` derived `4:6:1,3,2,0,0,0,0,0,0`
  (unit 4, selector 0x06, interface 3, D1) from `GET_MAX`/`GET_DEF` alone, the
  same bytes `hellocamctl ir on` writes.

## Undo

```sh
sudo irlume login disable --apply        # PAM wiring only
sudo systemctl disable --now irlumed     # stop the daemon
```

`/etc/pam.d/plasmalogin` and `/etc/pam.d/kde` are generated overrides whose
first lines say so; deleting them restores the vendor copies.
