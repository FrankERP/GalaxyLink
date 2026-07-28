#!/usr/bin/env python3
"""Generate solid-color PNG icons for the PWA manifest. Stdlib only."""
import struct, zlib, os

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + \
        struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

def solid_png(size, rgb):
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    row = b"\x00" + bytes(rgb) * size
    idat = zlib.compress(row * size)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", idat) + chunk(b"IEND", b""))

out_dir = os.path.join(os.path.dirname(__file__), "..",
                       "Sources", "GalaxyLink", "Resources", "web")
for size in (192, 512):
    path = os.path.join(out_dir, f"icon-{size}.png")
    with open(path, "wb") as f:
        f.write(solid_png(size, (76, 91, 175)))
    print("wrote", path)
