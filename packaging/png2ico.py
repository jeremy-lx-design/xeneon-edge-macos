#!/usr/bin/env python3
"""Pack PNGs into a Windows .ico, storing each entry PNG-compressed.

ImageMagick writes .ico entries as uncompressed BMP, which makes a
256x256 entry 262KB on its own. Windows has accepted PNG-compressed
entries since Vista, so this keeps the whole icon around 20KB.

Usage: png2ico.py out.ico in16.png in32.png ...
"""
import struct
import sys


def png_size(blob):
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    # IHDR width/height live at bytes 16..24.
    return struct.unpack(">II", blob[16:24])


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    out, sources = argv[1], argv[2:]

    blobs = []
    for path in sources:
        with open(path, "rb") as handle:
            blobs.append(handle.read())

    header = struct.pack("<HHH", 0, 1, len(blobs))
    offset = len(header) + 16 * len(blobs)

    entries = bytearray()
    for blob in blobs:
        width, height = png_size(blob)
        if not (0 < width <= 256 and 0 < height <= 256):
            raise ValueError(f"{width}x{height} out of range for .ico")
        # 256 is encoded as 0 in the single-byte dimension fields.
        entries += struct.pack(
            "<BBBBHHII", width % 256, height % 256, 0, 0, 1, 32, len(blob), offset
        )
        offset += len(blob)

    with open(out, "wb") as handle:
        handle.write(header)
        handle.write(entries)
        for blob in blobs:
            handle.write(blob)


if __name__ == "__main__":
    main(sys.argv)
