Here is the complete record, in your order. The package install preceded it (`irlume` 0.15.0 from the AUR, source signature verified, `ir-setup` came from that package, not from a build of my own). The camera had been replugged beforehand, and the pre-state line below shows it was in D0, so nothing was inherited from my earlier test.

```console
$ irlume version
irlume 0.15.0

$ bash -c 'for d in /sys/bus/usb/devices/*; do [ "$(cat $d/idVendor 2>/dev/null):$(cat $d/idProduct 2>/dev/null)" = 3443:930d ] && { echo "$d bcdDevice $(cat $d/bcdDevice)"; base64 -w0 $d/descriptors; echo; }; done'
/sys/bus/usb/devices/1-3 bcdDevice 0006
EgEBAu8CAUBDNA2TBgACAQMBCQIdBAYBAID6CAsAAg4DAAUJBAAAAQ4BAAUNJAEAAWgAwOHkAAEBCSQDBQEBAAQAGiQGA3Az8CgRYy5KuixokOszQBYIAQIBvwAbJAYE3JU/DzImTkySyaBHgvQ7yBABAwIAAAASJAIBAQIAAAAAAAAAAAMuKiILJAUCAQAAAn8XAAcFgwNAAAYFJQOAAAkEAQAADgIAAA8kAQJ7AYEABQAAAAEAAAskBgEFAAEAAAAAIiQHAQCABzgEAIBTOwAAp3ZNSj8ACosCAAIKiwIAFRYFACIkBwIAAAXQAgAAXhoAALw0TSIcAAqLAgACCosCABUWBQAiJAcDAMADHAIA4NQOAMCpHU3UDwAKiwIAAgqLAgAVFgUAIiQHBABWA+ABAFi6CwCwdBfNhAwACosCAAIKiwIAFRYFACIkBwUAgALgAQAAyggAAJQRTWIJAAqLAgACCosCABUWBQAbJAQCBVlVWTIAABAAgAAAqgA4m3EQAQAAAAAeJAUBAIAHOAQAQOMJAEDjCQBIPwCAhB4AAYCEHgAeJAUCAAAF0AIAAMoIAADKCAAgHABAQg8AAUBCDwAeJAUDAMADHAIAQOMJAEDjCQDSDwAgoQcAASChBwAeJAUEAFYD4AEAkNEHAJDRB4CCDAAgoQcAASChBwAeJAUFAIAC4AEAAMoIAADKCABgCQAVFgUAARUWBQAGJA0BAQQJBAEBAQ4CAAAHBYEFgAABCQQBAgEOAgAABwWBBQABAQkEAQMBDgIAAAcFgQUgAwEJBAEEAQ4CAAAHBYEFIAsBCQQBBQEOAgAABwWBBbATAQkEAQYBDgIAAAcFgQUAFAEICwICDgMABgkEAgABDgEABg0kAQABaADA4eQAAQMJJAMFAQEABAAaJAYDcDPwKBFjLkq6LGiQ6zNAFggBAgEAABskBgTclT8PMiZOTJLJoEeC9DvIEAEDAiABABIkAgEBAgAAAAAAAAAAAwAAIAskBQIBAAACAAAABwWGA0AABgUlA4AACQQDAAAOAgAADiQBAU0AggAFAAAAAQAbJAQBATIAAAACABAAgAAAqgA4m3EIAQAAAAAeJAUBAIACaAEAwEsDAMBLAwCEAwAVFgUAARUWBQAGJA0BAQQJBAMBAQ4CAAAHBYIFgAABCQQDAgEOAgAABwWCBQABAQkEAwMBDgIAAAcFggUgAwEJBAMEAQ4CAAAHBYIFgAoBCQQDBQEOAgAABwWCBSATAQkEAwYBDgIAAAcFggUAFAEICwQCAQAABAkEBAAAAQEABAkkAQABKwABBQwkAgEBAgACAAAAAA0kBgIBAgEAAgACAAAJJAMDAQEAAgAJBAUAAAECAAQJBAUBAQECAAQHJAEDAQEACyQCAQICEAGAuwAJBYQFwAAEAAAHJQEBAAAA

$ sudo irlume ir-setup --dry-run
[ir-setup] extension units: unit 3 (vendor-defined; irlume will not write to it): advertises []; unit 4 (Microsoft camera control): advertises [0x06, 0x09]

$ sudo irlume ir-setup
[ir-setup] this writes to your camera. It uses only the controls your camera's USB
descriptor documents, and the values it reports for them. A few seconds…
[ir-setup] IR emitter enabled: 4:6:1,3,2,0,0,0,0,0,0 on the camera's Microsoft camera-control unit, using a value built from what the camera reports about that control (saved; future captures rebuild it the same way); accepted: interface 0x03 set to D1 (alternative illumination)
```

Two lines of context around it, both from the same machine, before and after:

```console
$ hellocamctl ir status        # before: what a replug leaves behind
  GET_CUR: 010301000000000000  iface 3: D0:general-purpose

$ hellocamctl ir status        # after: irlume left the emitter on, as designed
  GET_CUR: 010302000000000000  iface 3: D1:alternating-illumination
```

Worth noting: `ir-setup`'s derived value is byte-for-byte the one my tool wrote by hand (`4:6:1,3,2,0,0,0,0,0,0`, interface `0x03`, D1), so the two independent paths agree. It also correctly refused unit 3 — that unit advertises nothing on the IR chain, and on the RGB chain the seven selectors it does advertise read back as identification and version blobs (a UTF-16 `Cam Pro Audio` name, short numeric values). None of those is documented, which is why nothing here writes to it.

The camera is left in D1, which is what "saved" means; if I want it idle again, `hellocamctl ir off` puts it back to D0.

One thing that may be a small upstream nicety while you are in this area: `GET_MIN`/`GET_RES` on this control return only the count byte (as the Microsoft document specifies), while `uvc_query_ctrl()` asks for the full 9 bytes and logs `UVC non compliance: GET_MIN control 6 on unit 4 returned 1 bytes when we expected 9`. Nothing breaks, but a driver-side mapping of this control cannot read those requests without producing that line.
