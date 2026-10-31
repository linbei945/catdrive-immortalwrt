#!/usr/bin/env python3
"""Strip the sysupgrade metadata trailer that ImmortalWrt's image builder
appends after the gzip stream of *.img.gz files.

U-Boot's gzwrite needs a clean gzip stream: a trailing trailer makes the
decompressor bail out. The stripped bytes are exactly the metadata; the
gzip payload itself is untouched.
"""
import glob
import zlib

for f in sorted(glob.glob("*catdrive*sdcard*.img.gz")):
    d = open(f, "rb").read()
    o = zlib.decompressobj(16 + zlib.MAX_WBITS)
    o.decompress(d)
    n = len(o.unused_data)
    if n:
        open(f, "wb").write(d[: len(d) - n])
        print(f"{f}: stripped {n} bytes of sysupgrade trailer")
    else:
        print(f"{f}: clean, no trailer")
