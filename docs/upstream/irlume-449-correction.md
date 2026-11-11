Two corrections to my earlier comment, now that this unit has been tested further. The emitter findings stand; the rest of that comment had two problems.

**The hub advice was wrong.** I said to move the camera off a monitor hub onto a root port because the microphone streamed digital silence behind a Realtek RTS5411 hub. The camera went back on the same hub and records audio after a **physical replug**. What differs between the silent and working states is a bus-power cycle, not the port: `USBDEVFS_RESET` resets the USB state but does not cut VBUS, which is why it never helped. So the accurate advice is: if the microphone is silent, unplug and replug the camera; the port is irrelevant. Sorry for the detour.

**"It is now in the table" was premature.** #1311 proposes the entry and is not merged, so treat `3443:930d` as fail-closed until it lands.

What is unchanged, and now backed by irlume's own derivation rather than only my tool: the IR chain's Microsoft unit is **unit 4**, face authentication is **selector 0x06**, it applies to streaming **interface 3**, and `GET_MAX 01 03 03` / `GET_DEF 01 03 01` yield the payload `01 03 02 00 00 00 00 00 00` (D1, alternating illumination). `sudo irlume ir-setup` on this unit printed exactly that — `4:6:1,3,2,0,0,0,0,0,0 … accepted: interface 0x03 set to D1` — and correctly refused the vendor unit next to it.
