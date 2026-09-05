#!/usr/bin/env python3
"""Print the image names inside a .wim, by parsing the WIM header's XML resource.

The autounattend.xml <MetaData> key /IMAGE/NAME must match one of these exactly.
Guessing it is how an unattended install stops on the edition-selection screen.
"""
import struct, sys, xml.etree.ElementTree as ET

def resource_entry(buf, off):
    # 8 bytes: 7-byte size + 1-byte flags; 8-byte offset; 8-byte original size
    size = int.from_bytes(buf[off:off + 7], "little")
    flags = buf[off + 7]
    offset = struct.unpack_from("<Q", buf, off + 8)[0]
    original = struct.unpack_from("<Q", buf, off + 16)[0]
    return size, flags, offset, original

with open(sys.argv[1], "rb") as f:
    hdr = f.read(208)
    if hdr[:8] != b"MSWIM\x00\x00\x00":
        sys.exit(f"not a WIM (magic={hdr[:8]!r})")
    image_count = struct.unpack_from("<I", hdr, 44)[0]
    # offset_table entry at 48, xml_data entry at 72
    size, flags, offset, original = resource_entry(hdr, 72)
    f.seek(offset)
    raw = f.read(size)

print(f"WIM reports image_count={image_count}")
text = raw.decode("utf-16-le", errors="replace").lstrip("﻿")
start = text.find("<WIM>")
root = ET.fromstring(text[start:]) if start >= 0 else ET.fromstring(text)
for img in root.findall("IMAGE"):
    name = (img.findtext("NAME") or "").strip()
    disp = (img.findtext("DISPLAYNAME") or "").strip()
    ed = (img.findtext("WINDOWS/EDITIONID") or "").strip()
    print(f"  INDEX={img.get('INDEX')}  NAME={name!r}  EDITIONID={ed!r}  DISPLAYNAME={disp!r}")
