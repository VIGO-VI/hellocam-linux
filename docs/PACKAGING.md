<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Packaging and policy notes

## Runtime dependencies

| dependency | needed for | kind |
|---|---|---|
| Python >= 3.8 | everything | required, standard library only |
| `v4l2-ctl` (`v4l-utils`) | `capture`, `selftest` | optional |
| `arecord` (`alsa-utils`) | `mic` | optional |

The core commands (`info`, `dump`, `xu`, `ir`, `meta`, `doctor`) use nothing
outside the Python standard library: no PyPI packages, no `ctypes`-wrapped
external libraries, no shell.

`hellocamctl doctor` reports exactly what is present, and `doctor --strict`
treats the optional tools as required. The tool fails with a message naming the
package rather than a traceback when an optional tool is missing.

Corresponding `PKGBUILD` fragments:

```
depends=(python)
optdepends=('v4l-utils: hellocamctl capture / selftest'
            'alsa-utils: hellocamctl mic')
```

## Privileges

* Normal operation needs **no privileges at all**. Control writes go through
  `UVCIOC_CTRL_QUERY` on the video node, which is already reachable by the
  logged-in user through the `video` group / `uaccess` ACL that PipeWire relies
  on.
* Root is needed exactly once, to install files (`install.sh` without
  `--user`). No setuid helper, no daemon, no polkit action.
* The udev rule in `packaging/` is **optional**: it exists for the `--usbfs`
  fallback and for USB-level experiments. Nothing in the default path reads
  `/dev/bus/usb`.

## Install locations

| install | tool | udev rule |
|---|---|---|
| `./packaging/install.sh --user` | `~/.local/bin/hellocamctl` | not installed |
| `sudo ./packaging/install.sh` | `/usr/local/bin/hellocamctl` | `/etc/udev/rules.d/` |
| distro package | `/usr/bin/hellocamctl` | `/usr/lib/udev/rules.d/` |

`install.sh` copies the tool; editing the checkout does not update an installed
copy. After changing `hellocamctl`, re-run `./packaging/install.sh --user`.
Nothing else is versioned against the kernel: the installed tool works on the
stock driver and on the proof-of-concept module alike.

The rule is named `72-…` on purpose: `73-seat-late.rules` is the rule that turns
`TAG+="uaccess"` into a device-node ACL, so anything that sets the tag has to be
processed earlier. A `99-` rule sets the tag after its consumer has run and
silently does nothing. This cost an hour to find; do not renumber it.

## Files written at run time

None that persist. Temporary frame/metadata dumps go through
`tempfile.mkstemp()` (mode 0600, unpredictable name) and are unlinked in a
`finally` block. There is no cache, no config file, and no state directory; the
camera is left in the mode it was found in (`selftest` restores `GET_CUR`).

## Process hygiene

* No `shell=True`, no `os.system`; every external command is an argument list.
* No network access.
* Fixed timeouts on every subprocess call so a wedged device cannot hang a
  session.
* `KeyboardInterrupt` exits 130 without leaving a stream running.

## Licensing

GPL-2.0-or-later, matching the kernel driver this is meant to feed
(`drivers/media/usb/uvc`). Every source and documentation file carries an SPDX
tag; the full text is in `LICENSE`. The files in `kernel/patches/` carry no tag
of their own because a patch becomes part of the GPL-2.0 kernel file it applies
to, and `kernel/README.md` says so.

## Kernel side (stage 2)

The kernel proof of concept is a patch against `drivers/media/usb/uvc/`, so it
must follow kernel rules: SPDX headers, `checkpatch.pl` clean, kernel coding
style, no new UAPI unless the control genuinely needs one (the PoC deliberately
avoids touching `videodev2.h` by using a private control id), and no behaviour
change for devices that do not advertise the control.
