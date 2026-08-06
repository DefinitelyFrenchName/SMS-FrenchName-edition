"""boxlib.py — the box-extractor core, in ONE place (#85).

Three extractors (extract_sms_hitboxes, extract_proj_boxes,
saturn/extract_supers_boxes) each carried private copies of the same four
primitives; the #38 copier-header bug had to be fixed in more than one of
them, which is what this module ends. Argument plumbing and output shapes
stay per-tool — only the primitives live here (maintainer's dedup rule,
smspaths.py).

Box format (docs/sms_uranus_rom_map.md): 8 bytes
  [x_off_r, w_r, x_off_l, w_l, y_off, h, flags, ?]
y_off negative = above the feet (origin at feet, +y down).
"""
import hashlib
import struct
import sys


def s8(b):
    """Signed 8-bit."""
    return b - 256 if b > 127 else b


def parse_box_dict(e):
    """8-byte box entry -> labelled dict (the JSON extractors' shape)."""
    return {"x_off_r": s8(e[0]), "w_r": e[1], "x_off_l": s8(e[2]), "w_l": e[3],
            "y_off": s8(e[4]), "h": e[5], "flags": e[6]}


def parse_box_tuple(e):
    """8-byte box entry -> 8-tuple incl. the unknown last byte (the listing shape)."""
    return (s8(e[0]), e[1], s8(e[2]), e[3], s8(e[4]), e[5], e[6], e[7])


def strip_copier_header(rom):
    """Drop a 512-byte copier header if present (issue #38: the old per-file copies
    tested % 0x100000, which never matched)."""
    if len(rom) % 0x8000 == 0x200:
        rom = rom[0x200:]
    return rom


def sha_gate(rom, expected, force, what):
    """Print the SHA-1 to stderr and refuse to run on the wrong ROM unless forced."""
    h = hashlib.sha1(rom).hexdigest()
    print("SHA-1:", h, file=sys.stderr)
    if h != expected and not force:
        raise SystemExit(f"error: not the {what} (expected {expected}); "
                         "pass --force to extract anyway")


def word(rom, fo):
    """Little-endian u16 at file offset fo."""
    return struct.unpack("<H", rom[fo:fo + 2])[0]
