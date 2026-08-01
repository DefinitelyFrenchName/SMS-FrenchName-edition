#!/usr/bin/env python3
"""Patch 15: remove the AUTO option from the VS button-config screen.

The config screen ("PRESS SELECT TO ACS") has eight option rows, dispatched
through a jump table at `$C3:A839`; entry 0 is the **モード row** (マニュアル /
オート). Auto maps the specials onto L and R — which collides with patch 12's
taunt (L press) and is banned in tournament play anyway.

Ground truth: the Big Zam **Tournament Edition** does exactly this, and its
diff against Big Zam isolates the change to three edits inside that handler
(`$C3:A849`). Verified byte-identical in the clean ROM, so it applies to any
point of our lineage:

    $C3:A863  sta $0006,X   -> NOP NOP NOP   (never commit the new mode)
    $C3:A87A  sta $0004,X   -> NOP NOP NOP   (never write it back to the working copy)
    $C3:A880  beq $A8B9     -> bra $A8B9     (skip the "value changed" tail entirely)

Net effect: the mode row is inert and both players stay on マニュアル for the
whole session; every other row (button assignments, 必殺 modes, stage) is
untouched, as is the screen's layout and text.

6 bytes total, byte-disjoint from patches 1-14. Builds from any input ROM so it
stacks into the REF bundle.
"""
import sys
from hashlib import sha1

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
CLEAN = clean_rom()

# Detection fingerprint (p15) — consumed by tools/mksigs.py for the regression
# suite's SIGS table. All three edits are fixed-address byte writes with no
# stub layout or bank dependency, so any of them is a stable signature.
SIG = [(0x03A863, 0xEA), (0x03A880, 0x80)]
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

# (file offset, expected bytes, replacement) — all inside the mode-row handler
EDITS = (
    (0x03A863, bytes.fromhex("9d0600"), bytes.fromhex("eaeaea")),  # sta $0006,X
    (0x03A87A, bytes.fromhex("9d0400"), bytes.fromhex("eaeaea")),  # sta $0004,X
    (0x03A880, bytes.fromhex("f0"),     bytes.fromhex("80")),      # beq -> bra
)


def build(src_path, out_path):
    data = bytearray(open(src_path, "rb").read())
    for off, old, new in EDITS:
        got = bytes(data[off:off + len(old)])
        if got != old:
            raise ValueError(f"mode-row handler @ {off:#08x}: found {got.hex()}, "
                             f"expected {old.hex()}")
        data[off:off + len(new)] = new
    fix_checksum(data)
    open(out_path, "wb").write(data)
    print(f"wrote {out_path} from {src_path}: AUTO option removed "
          f"(config モード row inert), sha1={sha1(bytes(data)).hexdigest()}")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Remove the AUTO option from the button-config screen.")
    ap.add_argument("src", nargs="?", default=CLEAN, help="input ROM (clean or a combined build)")
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_noauto.sfc"), help="output ROM path")
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out)
