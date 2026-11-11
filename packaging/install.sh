#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Install hellocamctl so it survives reboots and system updates.
#
#   ./packaging/install.sh --user     # ~/.local/bin, no root needed
#   sudo ./packaging/install.sh       # /usr/local/bin + the udev rule
#   sudo ./packaging/install.sh --remove
#
# The tool itself is a single self-contained Python 3 file (stdlib only), so an
# "update" is just copying a new version over the old one: nothing it depends on
# lives outside the standard library, and no state is written at run time.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
rule=72-hellocamctl.rules
tool=hellocamctl

usage() {
	sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
}

remove_files() {
	for f in "$@"; do
		[ -e "$f" ] && rm -f "$f" && echo "removed $f"
	done
}

case "${1:-}" in
--user)
	bindir="${XDG_BIN_HOME:-$HOME/.local/bin}"
	mkdir -p "$bindir"
	install -m 0755 "$root/$tool" "$bindir/$tool"
	echo "installed $bindir/$tool"
	case ":$PATH:" in
	*":$bindir:"*) ;;
	*) echo "warning: $bindir is not in PATH" >&2 ;;
	esac
	exit 0
	;;
--remove)
	[ "$(id -u)" = 0 ] || { echo "removal needs root" >&2; exit 1; }
	remove_files /usr/local/bin/$tool /etc/udev/rules.d/$rule \
		/etc/udev/rules.d/99-hellocamctl.rules
	udevadm control --reload
	udevadm trigger --subsystem-match=usb --attr-match=idVendor=3443 --action=add
	exit 0
	;;
"") ;;
*) usage ;;
esac

[ "$(id -u)" = 0 ] || { echo "system install needs root; try --user" >&2; exit 2; }

install -m 0755 "$root/$tool" /usr/local/bin/$tool
echo "installed /usr/local/bin/$tool"

# The udev rule is only needed for the --usbfs fallback and for USBDEVFS_RESET
# helpers; the normal V4L2 path needs no privileges.  It must sort before
# 73-seat-late.rules, which is what turns TAG+="uaccess" into a device ACL.
rm -f /etc/udev/rules.d/99-hellocamctl.rules
install -m 0644 "$here/$rule" /etc/udev/rules.d/$rule
udevadm control --reload
udevadm trigger --subsystem-match=usb --attr-match=idVendor=3443 --action=add
sleep 1

for node in /dev/bus/usb/*/*; do
	case "$(udevadm info -q property -n "$node" 2>/dev/null || true)" in
	*ID_VENDOR_ID=3443*)
		printf '%s: ' "$node"
		getfacl -p "$node" 2>/dev/null | grep '^user:' ||
			echo "no uaccess ACL yet (replug the camera)"
		;;
	esac
done
