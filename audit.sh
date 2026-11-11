#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Self-check for this repository.  Exits non-zero if any check fails, so
# "audit waves until a wave finds nothing" is one command.
#
#   ./audit.sh            checks the tree as committed
#   ./audit.sh --build    also clones HEAD to a temp dir, fetches the kernel
#                         sources, applies the patches and builds the module
set -eu

cd "$(dirname "$0")"
fail=0
note() { printf '%-46s %s\n' "$1" "$2"; }
bad()  { printf '%-46s %s\n' "$1" "FAIL: $2"; fail=1; }

# 1. nothing generated is tracked
tracked=$(git ls-files | grep -E '\.(o|ko|cmd|mod)$|checkpatch|__pycache__' || true)
[ -n "$tracked" ] && bad "no build artifacts tracked" "$(echo "$tracked" | tr '\n' ' ')" ||
	note "no build artifacts tracked" ok

# 2. SPDX coverage, with the documented exceptions
missing=""
for f in $(git ls-files); do
	case "$f" in
	LICENSE|docs/upstream/*|*.patch) continue ;;
	esac
	head -5 "$f" | grep -q "SPDX-License-Identifier" || missing="$missing $f"
done
[ -n "$missing" ] && bad "SPDX tags" "$missing" ||
	note "SPDX tags (LICENSE, upstream, patches exempt)" ok

# 3. shell scripts: syntax, and no bashisms in files declaring /bin/sh
bashism=""
for f in $(git ls-files '*.sh'); do
	if ! sh -n "$f"; then bad "sh -n" "$f"; fi
	if head -1 "$f" | grep -q '/bin/sh$' &&
	   grep -qE '\[\[|function [a-z]|local [a-z_]+=|declare -|<<<' "$f"; then
		bashism="$bashism $f"
	fi
done
[ -n "$bashism" ] && bad "no bashisms in /bin/sh scripts" "$bashism" ||
	note "shell syntax and portability" ok

# 4. the tool compiles
if python3 -m py_compile hellocamctl 2>/dev/null; then
	rm -rf __pycache__
	note "hellocamctl compiles" ok
else
	bad "hellocamctl compiles" "py_compile failed"
fi

# 5. internal paths referenced from the docs exist
missing=""
for p in $(grep -rhoE '(docs|kernel|packaging)/[A-Za-z0-9_./-]+\.(md|sh|patch|rules)' \
		--include='*.md' . | sort -u); do
	case "$p" in
	docs/HARDWARE.md) continue ;;	# irlume's file, cited as such
	esac
	[ -e "$p" ] || missing="$missing $p"
done
[ -n "$missing" ] && bad "doc references resolve" "$missing" ||
	note "doc references resolve" ok

# 6. history: signatures are informative (U = signer's key not in this keyring),
# oversized blobs are not
sig=$(git log --format=%G? | sort | uniq -c | tr -s ' ' | tr '\n' ' ')
note "commit signatures (G=verified, U=no key)" "${sig:-none}"
big=$(git rev-list --objects --all |
	git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' |
	awk '$1 == "blob" && $2 > 200000 { print $3 }')
[ -n "$big" ] && bad "no oversized blobs in history" "$big" ||
	note "no oversized blobs in history" ok

# 7. the working tree matches what the commit says
[ -n "$(git status --porcelain)" ] && note "working tree" "dirty (auditing HEAD)" ||
	note "working tree clean" ok

# 8. optional: build from a fresh clone of HEAD
if [ "${1:-}" = "--build" ]; then
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	git clone -q . "$tmp/repo"
	cd "$tmp/repo"
	./kernel/fetch-sources.sh >/dev/null
	./kernel/patches/apply.sh >/dev/null
	out=$(make -C "/lib/modules/$(uname -r)/build" M="$PWD/kernel/uvc" LLVM=1 modules 2>&1) || {
		printf '%s\n' "$out" | tail -5
		bad "kernel module builds from a fresh clone" "make failed"
	}
	case "$out" in
	*" warning"*|*" error"*)
		bad "kernel module builds from a fresh clone" "warnings or errors" ;;
	*)
		note "kernel module builds from a fresh clone" \
			"srcversion $(modinfo -F srcversion kernel/uvc/uvcvideo.ko)" ;;
	esac
fi

[ "$fail" = 0 ] && echo "audit: clean" || { echo "audit: FAILED"; exit 1; }
