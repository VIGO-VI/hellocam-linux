<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Submission-ready series

`git format-patch` output, generated from the bare diffs in `../patches/` by
reconstructing them as commits on a Linux v7.3 baseline. Use these for mailing
list submission; the files in `../patches/` exist for the local build harness.

| file | status | risk |
|---|---|---|
| `0001-…-ignore-Region-of-Interest-…` | proposed for submission now | low: a blacklist entry plus an optional interface field, no UAPI |
| `0002-…-expose-the-MS-XU-face-authentication-…` | **RFC only** | needs a public control id first; keep local until that is decided |

## Before sending 0001

1. **Identity.** Both files carry a placeholder,
   `Signed-off-by: <PENDING: your name <you@example.com>>`, and the author is
   `Your Name <you@example.com>`. A real name and a mailbox that receives list
   mail are required; `Signed-off-by` must be the author's. Replace both
   (`git commit --amend -s` in the reconstruction, or edit the file) — checkpatch
   currently reports exactly this mismatch and nothing else.
2. **Rebase.** The patch is made against v7.3. Rebase onto the media tree
   (`media_stage` or `linux-next`), which is what maintainers apply to.
3. **Rebuild and retest** on that tree, then repeat the two-node check:
   `/dev/video0` keeps 19 controls with no `error 5` line and no
   `permanently disabling 981ae2`; `/dev/video2` keeps both ROI controls.
4. `checkpatch.pl --strict` clean (already true apart from the placeholder).
5. Send with `git send-email` to `linux-media@vger.kernel.org`, cc the UVC
   maintainers from `MAINTAINERS` (`Laurent Pinchart`, `Hans Verkuil`) and
   `linux-kernel@vger.kernel.org`.

## Why 0002 waits

It adds a V4L2 control whose payload is a per-streaming-interface array, not a
scalar, and gives it a private id (`V4L2_CID_USER_BASE + 0x1000`). The API shape
is the question, so it belongs in an RFC thread — after the CID discussion, not
before it. Its evidence is already in `../../docs/FINDINGS.md` and
`../../docs/SETUP-irlume.md`.
