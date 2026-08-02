#!/usr/bin/env python3
"""Extract Saturn's voice samples from the Super S ROM, trimmed to fit SMS.

Produces the BRR bank that SMS would upload to ARAM $B700 for whichever player
is using her, plus the directory entries describing it.

WHY IT IS TRIMMED. SMS gives each fighter $B700-$DB00 = 9216 bytes (the ceiling
is the other player's bank at $DB00). Her four sounds come to 9900. The
maintainer chose, after A/B listening, to take the 684-byte overflow off the
three PROJECTILE samples only — 26 BRR blocks (52 ms) each — leaving the win
laugh untouched:

  * the laugh is the shortest of the four, so an equal-bytes cut costs it the
    largest PROPORTION (13% vs 5%), and it audibly turned a three-part laugh
    into a two-part one;
  * at 52 ms the projectiles were judged "indistinguishable" (j.632K), "barely
    different" (214P) and "audibly shorter but doesn't feel cut" (236P).

Sample identity was established by ear by the maintainer (entries 30-33 of
Super S's directory at ARAM $1E00); the ARAM->ROM mapping is linear, file
offset = ARAM + 0x2EE17F, verified on all four.

Each sample is a one-shot (end=1, loop=0), so truncation only requires moving
the END FLAG to the new last block — without it the DSP runs on into whatever
follows in ARAM, which is a loud failure rather than a subtle one.
"""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
ARAM_TO_ROM = 0x2EE17F        # file offset = ARAM address + this
DEST = 0xB700                 # ARAM destination of a fighter's voice bank
BUDGET = 0xDB00 - 0xB700      # 9216 — the other player's bank caps it

#   entry: (name, ARAM start, size, blocks to trim)
SAMPLES = [
    (30, "win_laugh", 0x7BFF, 0x546, 0),
    (31, "236P",      0x8145, 0xB49, 26),
    (32, "214P",      0x8C8E, 0xE07, 26),
    (33, "j632K",     0x9A95, 0x816, 26),
]


def supers_rom():
    import glob, os
    for d in (os.environ.get("SMS_ROM_DIR"), str(REPO / "roms"), str(REPO.parent / "roms")):
        if not d:
            continue
        for f in sorted(glob.glob(os.path.join(d, "*.sfc"))):
            if "SuperS" in f:
                return f
    raise SystemExit("error: Super S ROM not found ($SMS_ROM_DIR, roms/, ../roms/)")


def build():
    rom = open(supers_rom(), "rb").read()
    bank = bytearray()
    entries = []
    for num, name, aram, size, trim in SAMPLES:
        off = aram + ARAM_TO_ROM
        raw = bytearray(rom[off:off + size])
        if len(raw) != size or len(raw) % 9:
            raise SystemExit(f"{name}: bad extraction ({len(raw)} bytes)")
        if raw[-9] & 1 != 1:
            raise SystemExit(f"{name}: source's last block has no end flag — not a one-shot?")
        if trim:
            raw = raw[:len(raw) - trim * 9]
            raw[-9] |= 0x01          # end flag on the new last block
            raw[-9] &= ~0x02         # and definitely not a loop
        start = DEST + len(bank)
        entries.append((num, name, start, len(raw)))
        bank += raw
    if len(bank) > BUDGET:
        raise SystemExit(f"bank is {len(bank)} bytes, over the {BUDGET} budget by {len(bank)-BUDGET}")

    out = REPO / "build" / "saturn"
    out.mkdir(parents=True, exist_ok=True)
    (out / "saturn_voice.brr").write_bytes(bytes(bank))
    dirblob = bytearray()
    for _n, _nm, start, size in entries:
        loop = start + size          # one-shots: the loop pointer is never reached
        dirblob += bytes((start & 0xFF, start >> 8, loop & 0xFF, loop >> 8))
    (out / "saturn_voice.dir").write_bytes(bytes(dirblob))

    print(f"wrote {out/'saturn_voice.brr'}: {len(bank)} bytes "
          f"({BUDGET - len(bank)} spare of {BUDGET})")
    for num, name, start, size in entries:
        print(f"    entry {num} {name:10s} ARAM ${start:04X} +{size:#06x}")
    print(f"wrote {out/'saturn_voice.dir'}: {len(dirblob)} bytes "
          f"({len(entries)} directory entries, for ARAM $3500)")


if __name__ == "__main__":
    build()
