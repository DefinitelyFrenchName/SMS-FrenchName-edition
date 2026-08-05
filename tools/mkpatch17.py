#!/usr/bin/env python3
"""Patch 17: every stage selectable, including the hidden one.

The tenth stage — the Nakayoshi editorial department (中よし編集部) — is real,
finished content that ships in the retail ROM; the game just hides it behind a
button code. Two edits make it ordinary.

**1. The menu bound (always applied, 1 byte).**
The stage row of the VS config screen is handled by `$C3:AA1A`, which sets the
shared list navigator's bound from a flag:

    $C3:AA28  lda $1F59 / and #$00FF / beq +5
              lda #$0010          ; flag SET   -> nine stages
              bra +3
              lda #$0012          ; flag CLEAR -> ten stages
    $C3:AA38  sta $1C1C

`$1C1C` is the navigator's INCLUSIVE max index in WORD units (`$C3:8002` cmp
wraps to 0, `$C3:801A` lda wraps to max), so 16 = stages 0-8 and 18 = 0-9.

The flag has exactly one writer, `$C3:BADE`, which latches `$1C5A >> 1` — and
`$1C5A` is left at 0 only while a button combo is held on the title sequence
(`$C3:B8B4` tests X+L+R). That is the retail unlock. Turning the `sta` into a
`stz` (`8D` -> `9C`, same length, no relocation) makes the flag always clear, so
the tenth stage is always in the list. Same one byte as
`vendor/sms-training-mode/sms_patcher.py PATCH_NAKAYOSHI`.

**2. The random-stage pool (applied when present).**
Patch 3 carries a rider that defaults the stage to a random one at character
select, and that picker bounds itself — it never reads `$1C1C`. It reduces the
RNG byte `$B1` modulo NINE and doubles it into the scene id `$8E`, so a random
default can never land on the tenth stage no matter what the menu allows:

    lda $B1 / and #$00FF
    cmp #$0009 / bcc + / sec / sbc #$0009 / bra -   ; A %= 9
    asl / sta $8E

Both constants become 10. The rider lives in the injected bank-$E8 blob, so it
is located by signature in the image being built rather than at a fixed offset —
and it is simply absent from a clean ROM, where nothing picks a stage at random
at all (the retail game has no random stage picker: `$8E` is written from a
menu selection, a story table at `$C0:E9D9`/`$C0:E9F9`, or `$C2:C009`).

**BGM (optional knob, off).** Ten pointers at `$E0:017A` address the scene
records (`$018E`…`$020D`), and each record's LAST byte is its music track. The
nine normal stages hold the contiguous run `$0A`-`$12`; the hidden stage's `$06`
sits outside it, i.e. it has a tune of its own, and it plays (36 key-ons over 480
frames across all eight DSP voices). `--bgm N` swaps it for any other stage's
track — verified by measurement, not by trusting the vendor patcher: with
`--bgm $10` stage 9 takes on stage 8's voice profile while stage 8 itself
digests byte-identical across the two builds.

    idx 0-9 tracks: $12 $0A $0F $11 $0B $0D $0C $0E $10 $06
"""
import re
import sys
from hashlib import sha1

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
CLEAN = clean_rom()

# Detection fingerprint (p17) — consumed by tools/mksigs.py for the regression
# suite's SIGS table. The menu byte is a fixed-address write in the base region
# with no stub layout or bank dependency; the pool edit is deliberately NOT in
# the signature, since it is conditional on patch 3 being in the image.
SIG = [(0x03BADE, 0x9C)]
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

# --- edit 1: the menu bound -------------------------------------------------
# anchor covers the whole latch so a shifted/rebuilt image cannot match by luck
FLAG_OFF = 0x03BADA
FLAG_OLD = bytes.fromhex("ad5a1c4a8d591f")   # lda $1C5A / lsr / sta $1F59
FLAG_NEW = bytes.fromhex("ad5a1c4a9c591f")   # lda $1C5A / lsr / stz $1F59

# --- edit 2: patch 3's random-stage rider ----------------------------------
# lda $B1 / and #$00FF / cmp #$0009 / bcc +6 / sec / sbc #$0009 / bra - / asl / sta $8E
POOL_RE = re.compile(re.escape(bytes.fromhex("a5b129ff00c9")) + rb"(.)"
                     + re.escape(bytes.fromhex("00900638e9")) + rb"(.)"
                     + re.escape(bytes.fromhex("0080f50a858e")), re.S)
POOL_CMP, POOL_SBC = 6, 12          # operand offsets within the match

# --- optional: hidden-stage BGM --------------------------------------------
BGM_OFF = 0x200219                  # last byte of scene record 9 ($E0:020D)
BGM_VANILLA = 0x06


def apply_to(data, pool=True, bgm=None):
    """Apply patch 17 to an in-memory image; returns human-readable notes.

    Shared with the Saturn builder (`tools/saturn/mksaturn_smoke.py`), which
    folds this patch in rather than re-implementing it — one copy of the byte
    knowledge, one set of assertions. Does NOT fix the checksum; the caller does
    that once, after its own edits.
    """
    notes = []

    got = bytes(data[FLAG_OFF:FLAG_OFF + len(FLAG_OLD)])
    if got != FLAG_OLD:
        if got == FLAG_NEW:
            raise ValueError("hidden-stage flag already patched in the input ROM")
        raise ValueError(f"hidden-stage flag latch @ {FLAG_OFF:#08x}: found "
                         f"{got.hex()}, expected {FLAG_OLD.hex()}")
    data[FLAG_OFF:FLAG_OFF + len(FLAG_NEW)] = FLAG_NEW
    notes.append("menu bound: 10 stages")

    if pool:
        # Count sites in the IMAGE being shipped, not in the clean ROM: this
        # project has already been burned by "the ROM has exactly N of these".
        hits = list(POOL_RE.finditer(bytes(data)))
        if not hits:
            notes.append("random pool: rider absent (nothing picks at random) — skipped")
        else:
            for m in hits:
                base = m.start()
                for off in (POOL_CMP, POOL_SBC):
                    if data[base + off] != 0x09:
                        raise ValueError(f"random-stage pool @ {base + off:#08x}: "
                                         f"found {data[base + off]:#04x}, expected 0x09")
                    data[base + off] = 0x0A
            notes.append(f"random pool: 9 -> 10 stages at "
                         + ", ".join(f"{m.start():#08x}" for m in hits))

    if bgm is not None:
        if not 0 <= bgm <= 0xFF:
            raise ValueError("--bgm must be a byte")
        if data[BGM_OFF] != BGM_VANILLA:
            raise ValueError(f"hidden-stage BGM @ {BGM_OFF:#08x}: found "
                             f"{data[BGM_OFF]:#04x}, expected {BGM_VANILLA:#04x}")
        data[BGM_OFF] = bgm
        notes.append(f"hidden-stage BGM: ${BGM_VANILLA:02X} -> ${bgm:02X}")

    return notes


def build(src_path, out_path, pool=True, bgm=None):
    data = bytearray(open(src_path, "rb").read())
    notes = apply_to(data, pool=pool, bgm=bgm)
    fix_checksum(data)
    open(out_path, "wb").write(data)
    print(f"wrote {out_path} from {src_path}: " + "; ".join(notes)
          + f", sha1={sha1(bytes(data)).hexdigest()}")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Make every stage selectable, hidden one included.")
    ap.add_argument("src", nargs="?", default=CLEAN, help="input ROM (clean or a combined build)")
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_allstages.sfc"), help="output ROM path")
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    ap.add_argument("--no-pool", dest="pool", action="store_false",
                    help="leave patch 3's random-stage default bounded to the nine normal stages")
    ap.add_argument("--bgm", type=lambda s: int(s, 0), default=None,
                    help="override the hidden stage's music track (vanilla $06)")
    a = ap.parse_args()
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out, pool=a.pool, bgm=a.bgm)
