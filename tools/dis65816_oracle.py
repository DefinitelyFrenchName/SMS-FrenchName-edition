#!/usr/bin/env python3
"""dis65816_oracle.py — validate our decode table against an INDEPENDENT one.

  python3 tools/dis65816_oracle.py           # the standard sample
  python3 tools/dis65816_oracle.py -r C08000-C08800

WHY THIS EXISTS. `tools/dis65816.py` has a self-check, but a table checked
against invariants its own author wrote is a table checked against itself. The
useful question is whether a DIFFERENT implementation, by a different author,
frames the same bytes into the same instructions. pelrun's DisPel is vendored
and built at `tools/Dispel/dispel`, so that comparison is free.

This is an OFFLINE oracle, never a runtime dependency: `checkdocs` must not need
a C binary to run. `health.sh` runs it when the binary is present and SKIPs when
it is not, per this repo's rule that a check which silently passes on a missing
input is worse than no check.

WHAT IS COMPARED: the (address, length) stream only — never mnemonic text.
DisPel prints `jsr` for opcode $22, which is really JSL, and does not punctuate
the bank in a long operand; those are display choices, not decode disagreements,
and comparing text would report them as failures every run.

Four mechanics, each of which produced a wrong answer before it was pinned down:

  * **The ROM is headerless — never pass `-n`.** It shifts everything by $200
    and disassembles garbage that still parses.
  * **The hex column is space-padded before the tab.** A row regex ending
    `([0-9A-F]+)\\t` matches only the 4-byte rows, which silently drops three
    quarters of the stream and then reports agreement on what is left.
  * **DisPel starts in 16-bit M and X.** Our walk must be seeded the same way
    (`-a`/`-x` flip it) or the two disagree on every immediate.
  * **DisPel is linear**, so past a data pocket it is decoding data as code.
    That is not a bug to work around: we compare UP TO the first divergence and
    report where it was, because a long agreed run is the evidence, and demanding
    total agreement over data would just make the oracle unusable.

Data-bearing ranges are deliberately included in the sample. They exercise rare
opcodes that hand-written code never reaches, which is exactly where a length
table is likely to be wrong.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import dis65816 as D

DISPEL = REPO / "tools" / "Dispel" / "dispel"
ROW = re.compile(r"^([0-9A-F]{2})/([0-9A-F]{4}):\t([0-9A-F]+)\s*\t(.*)$")

# start, end (SNES, HiROM), and why the range is in the sample
SAMPLE = [
    (0xC08000, 0xC08800, "boot/init — starts with rep #$30, exercises both widths"),
    (0xC09800, 0xC09C00, "sprite emitter and the box-index writer"),
    (0xC0D000, 0xC0D400, "in-match NMI body and the HUD uploader"),
    (0xC0E200, 0xC0E600, "the frame loops"),
    (0xC10000, 0xC10800, "bank $C1 engine head — throws, damage, dispatch"),
    (0xC1B000, 0xC1B400, "a per-character proc block"),
    (0xC3BA00, 0xC3BE00, "menu dispatcher and the config screen"),
    (0xE00000, 0xE00400, "the in-match asset job table — DATA, on purpose"),
    (0xC0CD00, 0xC0D000, "on-hit tables — DATA, on purpose"),
]


def dispel_rows(rom_path, lo, hi, a8=False, x8=False, dispel=DISPEL):
    """[(snes_addr, length, text)] for `dispel -h -r lo-hi`.

    Raises FileNotFoundError if the binary is absent — the caller decides
    whether that is a SKIP.
    """
    cmd = [str(dispel), "-h"]
    if a8:
        cmd.append("-a")
    if x8:
        cmd.append("-x")
    cmd += ["-r", f"{lo:06X}-{hi:06X}", str(rom_path)]
    txt = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    out = []
    for line in txt.splitlines():
        m = ROW.match(line)
        if m:
            snes = (int(m.group(1), 16) << 16) | int(m.group(2), 16)
            out.append((snes, len(m.group(3)) // 2, m.group(4).strip()))
    return out


def compare(rom, rom_path, lo, hi, a8=False, x8=False, dispel=DISPEL, walker=None):
    """-> (agreed, divergence) where divergence is None or a description.

    `agreed` counts instructions on which both implementations produced the
    same address AND the same length, from `lo` up to the first disagreement.

    ⚠ The two streams are LENGTH-CHECKED before they are zipped. `zip` stops at
    the shorter one, so a parser that had quietly stopped matching would report
    perfect agreement on the handful of rows it still recognised — the same
    vacuous pass `checkdocs`' extractor self-tests exist to catch. One row of
    slack is allowed and no more: our walk refuses an instruction that would run
    past the range end, DisPel emits it, so a trailing partial costs exactly one.
    """
    rows = dispel_rows(rom_path, lo, hi, a8, x8, dispel)
    walk = walker or D.walk
    mine = list(walk(rom, lo & 0x3FFFFF, hi & 0x3FFFFF,
                     m=1 if a8 else 0, x=1 if x8 else 0))
    if not rows:
        return 0, "DisPel produced no parseable rows — check the row regex"
    if not -1 <= len(rows) - len(mine) <= 1:
        return 0, (f"stream lengths differ by {len(rows) - len(mine)} "
                   f"(DisPel {len(rows)}, ours {len(mine)}) — more than the "
                   "one-row tail a range boundary can explain")
    agreed = 0
    for (snes, dlen, text), (addr, op, ln, _m, _x) in zip(rows, mine):
        if (snes & 0x3FFFFF) != addr:
            return agreed, (f"address: DisPel at ${snes:06X}, ours at ${addr | (lo & 0xFF0000):06X}")
        if dlen != ln:
            return agreed, (f"${snes:06X} op {op:02X} ({text}): DisPel {dlen} bytes, ours {ln}")
        agreed += 1
    return agreed, None


def selftest(rom, rom_path, lo=0xC08000, hi=0xC08800, dispel=DISPEL):
    """The oracle's own negative control: CORRUPT our table, demand a divergence.

    A comparison that cannot fail is not a comparison.

    ⚠ The obvious control — seed our walk 8-bit where DisPel is 16-bit — was
    tried first and PASSED VACUOUSLY: every code range worth sampling opens with
    `rep #$30`, which resets both widths on instruction one, so the wrong seed
    corrects itself before it can cause a divergence. It looked like a control
    and tested nothing. Perturbing the length TABLE instead is independent of
    what the ROM happens to contain: pick an opcode this range actually decodes,
    add a byte to its length, and the comparison must notice.
    """
    mine = list(D.walk(rom, lo & 0x3FFFFF, hi & 0x3FFFFF, m=0, x=0))
    victim = next((op for _a, op, _l, _m, _x in mine
                   if op not in D.IMM_M and op not in D.IMM_X), None)
    if victim is None:
        return "negative control could not run: no flag-independent opcode in the range"
    saved = D.LEN[victim]
    D.LEN[victim] = saved + 1
    try:
        agreed, div = compare(rom, rom_path, lo, hi, dispel=dispel)
    finally:
        D.LEN[victim] = saved
    if div is None:
        return (f"negative control FAILED: opcode {victim:02X} lengthened to "
                f"{saved + 1} and DisPel still agreed on all {agreed}")
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-r", "--range", help="LO-HI in SNES hex, e.g. C08000-C08800")
    ap.add_argument("-a", action="store_true", help="start in 8-bit accumulator")
    ap.add_argument("-x", action="store_true", help="start in 8-bit index")
    args = ap.parse_args()

    from smspaths import clean_rom
    rom_path = clean_rom()
    rom = open(rom_path, "rb").read()
    if not DISPEL.exists():
        print(f"SKIP  {DISPEL} not built "
              "(cc -O2 -o dispel main.c 65816.c in tools/Dispel/)")
        sys.exit(0)

    ranges = SAMPLE
    if args.range:
        lo, hi = (int(v, 16) for v in args.range.split("-"))
        ranges = [(lo, hi, "requested")]

    total, bad = 0, []
    for lo, hi, why in ranges:
        agreed, div = compare(rom, rom_path, lo, hi, args.a, args.x)
        total += agreed
        mark = "\033[32mALL AGREE\033[0m" if div is None else f"\033[31m{div}\033[0m"
        print(f"  ${lo:06X}-${hi:06X}  {agreed:5d} instructions  {mark}")
        print(f"      {why}")
        if div is not None:
            bad.append((lo, div))

    fail = selftest(rom, rom_path)
    if fail:
        print(f"  \033[31mFAIL\033[0m  {fail}")
        bad.append((0, fail))
    else:
        print("  negative control: a corrupted length table diverges, as it must")

    if bad:
        print(f"\n\033[31m{len(bad)} range(s) disagree with DisPel\033[0m")
        sys.exit(1)
    print(f"\n\033[32mAGREED\033[0m on {total} consecutive instructions across "
          f"{len(ranges)} ranges, independent implementation")


if __name__ == "__main__":
    main()
