#!/usr/bin/env python3
"""Patch 18: no ACS in 2P VS.

The **A.C.S.** (Ability Customize System) screen lets a player redistribute a
character's stats before the fight — 攻撃 / 防御 / 体力 / 必殺技 / おちゃめ.
Fine in single player, not something you want available in a versus match, for
the same reason patch 15 removes AUTO: it is not part of the game two people
sit down to play.

**Where the door is** (measured, `tools/probe_acs_select.lua`): the VS config
screen — the one that says `PRESS "SELECT" TO ACS` — hands off through a
per-game-mode dispatcher at `$C3:BB60` (`lda $8D / asl / tax /
jmp ($BB6D,x)`, five entries for modes 0-4). Modes **1 (2P VS) and 2 (vs COM)
share one handler** at `$C3:BB93`, which reads `$1C02` and picks the next menu
state: `2` (SELECT was pressed) → state `$05` = ACS, anything else → state `$00`
= start the match. Menu state `$05` has exactly **two** writers in the whole ROM
(`$C3:BB8E` in the story handler, `$C3:BBAA` here), so blocking that branch for
mode 1 closes the only versus door; story and vs-COM keep theirs.

**The edit** — 12 bytes, in place, no bank, no stub. Since modes 1 and 2 share
the handler, the mode has to be re-tested inside it:

| | vanilla `$C3:BB9E` | patched |
|---|---|---|
| | `lda $1C02` | `lda $8D` |
| | `cmp #$02` | `dec a`  ; Z iff mode 1 |
| | `beq $BBAA` | `beq $BBB5` ; 2P VS -> start the match |
| | `lda #$00` | `lda $1C02` |
| | `sta $8A` | `cmp #$02` |
| | `rts` | `bne $BBB5` ; not SELECT -> start the match |

and `$BBAA` (`lda #$05 / sta $8A / rts`, the ACS branch) is left alone, reached
now by falling through. The replaced tail was the handler's own
`lda #$00 / sta $8A / rts`; the patched code branches to the **identical** tail
at `$C3:BBB5` inside the mode-3 handler instead — same instructions, same 8-bit
A, and nothing else in the bank jumps into the bytes being replaced (checked).

Modes other than 1 behave exactly as before, instruction for instruction.

⚠ The screen still *says* `PRESS "SELECT" TO ACS`, because that strip is part of
its compressed tilemap. Same shape as patch 15, where the モード row still reads
マニュアル: the option is inert, not erased.
"""
import sys
from hashlib import sha1

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
CLEAN = clean_rom()

# Detection fingerprint (p18) — consumed by tools/mksigs.py for the regression
# suite's SIGS table. A fixed-address byte write in the base region, no stub
# layout or bank dependency.
SIG = [(0x03BB9E, 0xA5), (0x03BBA0, 0x3A)]

SITE = 0x03BB9E                                    # $C3:BB9E
OLD = bytes.fromhex("ad021cc902f005a90085 8a60".replace(" ", ""))
NEW = bytes.fromhex("a58d3af012ad021cc902d00b")
assert len(OLD) == len(NEW) == 12


def build(src_path, out_path):
    data = bytearray(open(src_path, "rb").read())
    got = bytes(data[SITE:SITE + len(OLD)])
    if got != OLD:
        if got == NEW:
            raise ValueError("ACS-in-VS branch already patched in the input ROM")
        raise ValueError(f"config-screen mode dispatcher @ {SITE:#08x}: found "
                         f"{got.hex()}, expected {OLD.hex()}")
    data[SITE:SITE + len(NEW)] = NEW
    fix_checksum(data)
    open(out_path, "wb").write(data)
    print(f"wrote {out_path} from {src_path}: ACS unreachable in 2P VS "
          f"(story/vs-COM unchanged), sha1={sha1(bytes(data)).hexdigest()}")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Remove ACS access from 2P VS.")
    ap.add_argument("src", nargs="?", default=CLEAN, help="input ROM (clean or a combined build)")
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_noacs_vs.sfc"), help="output ROM path")
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out)
