#!/usr/bin/env python3
"""docaddrs.py — the address census the documentation checks are built on.

  python3 tools/docaddrs.py             # the coverage report
  python3 tools/docaddrs.py --uncovered # ...and every ROM address no check re-derives

WHY THIS EXISTS. `checkdocs.py` re-derives documented claims from the cartridge,
which is only as good as the claims someone thought to write a check for. This
module answers the prior question: **what is there to check?** It censuses every
`$BB:AAAA` token in `docs/`, classifies each by whether the clean cartridge can
decide anything about it at all, and reports what fraction is actually covered.
The number that matters is the UNCOVERED one, and it is meant to be looked at.

Three classifications, and the distinction is the whole point:

  ROM       banks `$C0-$E7`, or `$80-$BF` at `$8000+` — in the image, decidable.
  RAM       `$7E`/`$7F` and the low banks — a claim about a running machine.
            The emulator suites own those; no amount of ROM reading settles one.
  OUTSIDE   `$E8+` — the appended banks this project's patches ADD. Not in the
            clean image by definition; a check would be asserting our own build.

It also extracts three families of claim that need no hand-written check at all,
because the doc states them mechanically:

  * **file-offset transcriptions** — `$C1:88E9 (file 0x188E9)`. HiROM makes this
    pure arithmetic (`snes & 0x3FFFFF`), so every one of them is decidable, and
    a transcription slip is exactly the kind of rot nobody re-reads for.
  * **quoted byte runs** — ``$C1:0AF5` = `00 01 02 02 …`` . The bytes are in the
    cartridge; compare them.
  * **quoted instructions** — ``$C0:9CCD` (`sta $41,X`)`. Encoded by the small
    65816 subset below and looked for at the address, or inside the routine that
    starts there. Finding one two bytes late is how `stz $47,X at $C1:0E51` was
    caught: it is at `$C1:0E4F`, in two documents, carried forward for weeks.

Association rule for both, deliberately strict: the claim binds to the NEAREST
PRECEDING address token ON THE SAME LINE, and for file offsets only when the
parenthetical is attached to the token (≤6 characters of `` `*( `` between).
Anything looser guesses, and a check that tests a claim nobody made is worse
than no check — it goes green for the wrong reason.
"""
import argparse
import re
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
DOCS = REPO / "docs"

TOKEN = re.compile(r"\$([0-9A-F]{2}):([0-9A-F]{4})")
# `(file 0x…)` / `(files 0x…)`, attached to the token it belongs to
FILE_CLAIM = re.compile(r"files?\s*`?0x([0-9A-Fa-f]{4,6})`?")
# a backticked run of >=4 hex bytes
RUN_CLAIM = re.compile(r"`((?:[0-9A-Fa-f]{2} ){3,}[0-9A-Fa-f]{2})`")

# docs/game/characters/ is written by tools/mkcharmap.py, which reads every
# address it prints out of the cartridge and is `--check`-gated in health.sh.
# Those addresses are derived by construction; a checkdocs check would be
# re-deriving the same read from the same ROM.
GENERATED = ("characters/",)


def is_rom(snes):
    """True if the clean image contains this address.

    HiROM maps the cartridge three ways and the docs use all three: `$C0-$E7`
    (the plain window), `$80-$BF` above `$8000` (the FastROM mirror the code
    executes from — below `$8000` those banks are hardware and WRAM), and
    `$40-$7D`, which the address-model example uses to show the mask at work.
    """
    bank, addr = snes >> 16, snes & 0xFFFF
    if 0x80 <= bank <= 0xBF:
        return addr >= 0x8000
    return 0xC0 <= bank <= 0xE7 or 0x40 <= bank <= 0x7D


def is_outside(snes):
    """True for the appended banks this project's own patches add ($E8+)."""
    return (snes >> 16) >= 0xE8


def f(snes):
    return snes & 0x3FFFFF


def token(snes):
    return f"${snes >> 16:02X}:{snes & 0xFFFF:04X}"


class Mention:
    __slots__ = ("doc", "line_no", "text", "snes")

    def __init__(self, doc, line_no, text, snes):
        self.doc, self.line_no, self.text, self.snes = doc, line_no, text, snes

    @property
    def generated(self):
        return any(g in self.doc for g in GENERATED)

    @property
    def area(self):
        """`game` = analysis of the retail cartridge (what checkdocs gates);
        `project` = this edition's own record, which also describes PATCHED
        images and so cannot be asserted against the clean ROM wholesale."""
        return "game" if self.doc.startswith("game/") else "project"

    def __repr__(self):
        return f"{self.doc}:{self.line_no} {token(self.snes)}"


def docs_files():
    """Every markdown file under docs/, repo-relative, sorted."""
    return sorted(p for p in DOCS.rglob("*.md"))


def census(paths=None):
    """Every address token in the docs, with the line it was written on."""
    out = []
    for p in paths or docs_files():
        doc = str(p.relative_to(DOCS))
        for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            for m in TOKEN.finditer(line):
                snes = (int(m.group(1), 16) << 16) | int(m.group(2), 16)
                out.append(Mention(doc, n, line, snes))
    return out


def _nearest_token(line, before):
    """The address token ending at or before `before` on this line, or None."""
    prev = [m for m in TOKEN.finditer(line) if m.end() <= before]
    if not prev:
        return None, None
    m = prev[-1]
    return (int(m.group(1), 16) << 16) | int(m.group(2), 16), m.end()


def file_offset_claims_in(doc, text):
    """(doc, line_no, snes, file_off) for every `$BB:AAAA (file 0x…)` in `text`.

    Only the ATTACHED form counts: at most six characters of `` `*( `` may sit
    between the token and the word `file`. The loose form ("Pluto's hit table
    …, height byte at file 0xAF0DE") names an offset INSIDE the structure rather
    than the structure's own address, and reading it as the token's offset
    invents a claim the doc never made.
    """
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        for m in FILE_CLAIM.finditer(line):
            snes, end = _nearest_token(line, m.start())
            if snes is None:
                continue
            gap = line[end:m.start()]
            if len(gap) > 6 or gap.strip(" `*(") != "":
                continue
            out.append((doc, n, snes, int(m.group(1), 16)))
    return out


def byte_run_claims_in(doc, text):
    """(doc, line_no, snes, bytes) for backticked byte runs bound to an address.

    Scoped to `docs/game/` by the caller: those documents describe the RETAIL
    cartridge, so a quoted run is a claim about bytes that are in it. The same
    pattern in `docs/project/` quotes bytes a PATCH writes, which are not in the
    clean ROM and never should be.
    """
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        for m in RUN_CLAIM.finditer(line):
            snes, _ = _nearest_token(line, m.start())
            if snes is None or not is_rom(snes):
                continue
            out.append((doc, n, snes, bytes.fromhex(m.group(1))))
    return out


# --------------------------------------------------------------- 65816 --
# Just enough of the instruction set to encode what the documents actually
# quote. It is deliberately not an assembler: it answers one question — "could
# these bytes be this instruction?" — and where the width of an immediate is
# ambiguous (the docs write `and #$0F` without saying which flag state they mean)
# it returns BOTH encodings and the caller accepts either.
_IMPLIED = {"sec": 0x38, "clc": 0x18, "phb": 0x8B, "plb": 0xAB, "pha": 0x48,
            "pla": 0x68, "php": 0x08, "plp": 0x28, "phk": 0x4B, "rtl": 0x6B,
            "rts": 0x60, "tax": 0xAA, "txa": 0x8A, "tay": 0xA8, "tya": 0x98,
            "xba": 0xEB, "nop": 0xEA, "inx": 0xE8, "dex": 0xCA, "iny": 0xC8,
            "dey": 0x88, "asl": 0x0A, "lsr": 0x4A, "rol": 0x2A, "ror": 0x6A}
_MODES = {                       # mnemonic -> {mode: opcode}
    "lda": {"imm": 0xA9, "dp": 0xA5, "dpx": 0xB5, "abs": 0xAD, "absx": 0xBD, "absy": 0xB9},
    "sta": {"dp": 0x85, "dpx": 0x95, "abs": 0x8D, "absx": 0x9D, "absy": 0x99},
    "stz": {"dp": 0x64, "dpx": 0x74, "abs": 0x9C, "absx": 0x9E},
    "ldx": {"imm": 0xA2, "dp": 0xA6, "abs": 0xAE},
    "ldy": {"imm": 0xA0, "dp": 0xA4, "abs": 0xAC},
    "cmp": {"imm": 0xC9, "dp": 0xC5, "abs": 0xCD, "absy": 0xD9},
    "sbc": {"imm": 0xE9, "dp": 0xE5}, "adc": {"imm": 0x69, "dp": 0x65},
    "and": {"imm": 0x29, "dp": 0x25, "dpx": 0x35, "abs": 0x2D},
    "ora": {"imm": 0x09, "dp": 0x05}, "eor": {"imm": 0x49, "dp": 0x45},
    "jsr": {"abs": 0x20, "iabsx": 0xFC}, "jmp": {"abs": 0x4C, "iabsx": 0x7C},
    "jsl": {"long": 0x22}, "jml": {"long": 0x5C},
    "rep": {"imm8": 0xC2}, "sep": {"imm8": 0xE2},
}


def encode(text):
    """`lda $0049,Y / sec / sbc $05` -> the byte strings that could be it.

    Returns [] for anything outside the subset above — the caller reports those
    as unencodable rather than passing them, because a claim nobody checked must
    not look like a claim that held.
    """
    out = [b""]
    for part in text.split("/"):
        bits = part.strip().split(None, 1)
        mn = bits[0].lower()
        op = bits[1].strip().lower() if len(bits) > 1 else ""
        if mn in _IMPLIED and not op:
            out = [o + bytes([_IMPLIED[mn]]) for o in out]
            continue
        if mn == "lsr" and op == "a":
            out = [o + b"\x4a" for o in out]
            continue
        table = _MODES.get(mn)
        if not table:
            return []
        cand = []
        m = re.fullmatch(r"#\$([0-9a-f]{2}(?:[0-9a-f]{2})?)", op)
        if m and ("imm" in table or "imm8" in table):
            v = int(m.group(1), 16)
            if "imm8" in table:
                cand = [bytes([table["imm8"], v & 0xFF])]
            else:                                   # width is not stated — allow both
                cand = [bytes([table["imm"], v & 0xFF])]
                if v <= 0xFF:
                    cand.append(bytes([table["imm"], v, 0]))
                else:
                    cand = [bytes([table["imm"], v & 0xFF, v >> 8])]
        m = re.fullmatch(r"\(\$([0-9a-f]{4}),x\)", op)
        if m and "iabsx" in table:
            v = int(m.group(1), 16)
            cand = [bytes([table["iabsx"], v & 0xFF, v >> 8])]
        m = re.fullmatch(r"\$([0-9a-f]{2}):?([0-9a-f]{4})", op)
        if m and "long" in table:
            bank, v = int(m.group(1), 16), int(m.group(2), 16)
            cand = [bytes([table["long"], v & 0xFF, v >> 8, bank])]
        m = re.fullmatch(r"\$([0-9a-f]{2,4})(,[xy])?", op)
        if m and not cand:
            v, idx = int(m.group(1), 16), (m.group(2) or "")[1:]
            wide = len(m.group(1)) > 2
            mode = ("abs" if wide else "dp") + idx
            if mode in table:
                cand = [bytes([table[mode], v & 0xFF] + ([v >> 8] if wide else []))]
        if not cand:
            return []
        out = [o + c for o in out for c in cand]
    return out


def instruction_claims_in(doc, text):
    """(doc, line_no, snes, quoted, bytes-candidates) for `$BB:AAAA` (`lda …`).

    Binds only when the quote is ATTACHED to the token — punctuation between,
    no words — or follows it as "… at `$BB:AAAA`". Two shapes are deliberately
    NOT bound: an instruction sitting in a later cell of a table row (the row
    for `$C0:9EA6` also quotes what a PATCH puts there), and an instruction that
    contains the address rather than living at it (`JSL $C1:0000` is a call TO
    the token, not the byte AT it) — the latter falls out for free, since a
    token inside the backticks is not a token beside them.
    """
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        for m in re.finditer(r"`([a-zA-Z]{3}[^`]{0,40})`", line):
            pre = [t for t in TOKEN.finditer(line) if t.end() <= m.start()]
            post = [t for t in TOKEN.finditer(line) if t.start() >= m.end()]
            snes = None
            if pre and not re.search(r"[A-Za-z0-9]", line[pre[-1].end():m.start()]) \
                    and m.start() - pre[-1].end() <= 6:
                snes = (int(pre[-1].group(1), 16) << 16) | int(pre[-1].group(2), 16)
            elif post and line[m.end():post[0].start()].strip(" `*") in ("at", "is at"):
                snes = (int(post[0].group(1), 16) << 16) | int(post[0].group(2), 16)
            if snes is None or not is_rom(snes):
                continue
            out.append((doc, n, snes, m.group(1).strip(), encode(m.group(1).strip())))
    return out


def instruction_claims(paths=None):
    return _over_files(instruction_claims_in, paths)


def _over_files(fn, paths):
    out = []
    for p in paths or docs_files():
        out += fn(str(p.relative_to(DOCS)), p.read_text(encoding="utf-8"))
    return out


def file_offset_claims(paths=None):
    return _over_files(file_offset_claims_in, paths)


def byte_run_claims(paths=None):
    return _over_files(byte_run_claims_in, paths)


def classify(mentions):
    """{class: {snes: [mention, …]}} — the census, bucketed by decidability."""
    buckets = {"rom": {}, "generated": {}, "ram": {}, "outside": {}}
    for m in mentions:
        if is_outside(m.snes):
            key = "outside"
        elif not is_rom(m.snes):
            key = "ram"
        elif m.generated:
            key = "generated"
        else:
            key = "rom"
        buckets[key].setdefault(m.snes, []).append(m)
    return buckets


def report(covered=None, show_uncovered=False, out=print):
    """Print the coverage report, scoped to `docs/game/` — the documents that
    describe the retail cartridge and are therefore decidable against it.

    `covered` = the set of SNES addresses some check re-derives; pass None to
    report the census alone. Returns the uncovered addresses.
    """
    all_m = census()
    game = classify([m for m in all_m if m.area == "game"])
    proj = classify([m for m in all_m if m.area == "project"])
    rom, covered = game["rom"], covered or set()
    # a check may name an address either way round — `$C0:9CCD` or `0x9CCD`
    seen = lambda a: a in covered or f(a) in covered
    hit = {a for a in rom if seen(a)}
    miss = sorted(a for a in rom if not seen(a))
    out(f"  docs/game/: {len(rom)} distinct ROM addresses in hand-written pages, "
        f"{len(hit)} re-derived from the cartridge")
    # "RAM" is a statement about DECIDABILITY, not about coverage: those
    # addresses are claims about a running machine, and while most are exercised
    # by the emulator suites, this tool has not checked that and must not imply
    # it. The one thing it can say is that the cartridge cannot settle them.
    out(f"    + {len(game['generated'])} in ROM-generated pages (mkcharmap --check)"
        f" · {len(game['ram'])} RAM, not decidable from the cartridge"
        f" · {len(game['outside'])} in appended banks")
    out(f"  docs/project/ names {len(proj['rom'])} more — this edition's record, "
        f"which also describes patched images; not gated here")
    if show_uncovered:
        for a in miss:
            where = rom[a][0]
            out(f"      {token(a)}  {where.doc}:{where.line_no}")
    return miss


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--uncovered", action="store_true",
                    help="list every ROM address in the docs (no check set is loaded here)")
    ap.add_argument("--claims", action="store_true",
                    help="list the file-offset and byte-run claims the extractors find")
    args = ap.parse_args()

    print("address census — docs/")
    report(show_uncovered=args.uncovered)
    if args.claims:
        print("\n  file-offset transcriptions:")
        for doc, n, snes, fo in file_offset_claims():
            flag = "ok " if f(snes) == fo else "BAD"
            print(f"    {flag} {token(snes)} -> 0x{fo:05X}   {doc}:{n}")
        print("\n  byte runs (docs/game only):")
        game = [p for p in docs_files() if p.parent.name == "game"]
        for doc, n, snes, want in byte_run_claims(game):
            print(f"    {token(snes)}  {want.hex(' ')}   {doc}:{n}")
    print("\nThis is a census, not a gate: run tools/checkdocs.py for the checks.")


if __name__ == "__main__":
    main()
