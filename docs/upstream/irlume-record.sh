#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Collect the evidence archledger asked for in irlume PR #1311, in the order
# requested, into one file.  Needs the owner's password twice at most (once for
# the package install, once for `irlume ir-setup`; sudo caches in between).
#
#   bash docs/upstream/irlume-record.sh
#
# It installs the packaged irlume (AUR), which also starts irlumed and installs
# the PAM module.  It does NOT touch login configuration: that only happens with
# `sudo irlume login enable --apply`, which this script never runs.
set -u

out="${1:-$HOME/irlume-3443-930d-record.txt}"

step() { printf '\n=== %s ===\n' "$*"; }

{
	step "0. install irlume (AUR) if missing"
	if command -v irlume >/dev/null 2>&1; then
		echo "already installed: $(command -v irlume)"
	else
		paru -S --needed --noconfirm irlume || {
			echo "install failed; stopping" >&2
			exit 1
		}
	fi

	step "1. irlume version"
	irlume version

	step "2. USB descriptor (3443:930d)"
	for d in /sys/bus/usb/devices/*; do
		[ "$(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null)" = 3443:930d ] && {
			echo "$d bcdDevice $(cat "$d/bcdDevice")"
			base64 -w0 "$d/descriptors"
			echo
		}
	done

	step "3. current control state before setup (should be D0)"
	hellocamctl ir status 2>/dev/null || true

	step "4. irlume ir-setup --dry-run"
	sudo irlume ir-setup --dry-run

	step "5. irlume ir-setup"
	sudo irlume ir-setup

	step "6. control state after setup"
	hellocamctl ir status 2>/dev/null || true
} 2>&1 | tee "$out"

echo
echo "record saved to $out"
echo "paste it into https://github.com/archledger/irlume/pull/1311"
