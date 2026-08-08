#!/usr/bin/env python3
"""Verify docs/project/saturn/'s cross-game claims against BOTH cartridges.

  python3 tools/saturn/checksaturndocs.py        # run every check
  python3 tools/saturn/checksaturndocs.py -v     # ...and print each one that passes

WHY THIS EXISTS. `tools/checkdocs.py` re-derives the game docs from the clean
ROM, and `tools/checkpatchmap.py` re-derives the patch docs from the artifacts.
The Saturn corpus was left out of both, and it is the one body of documentation
this project BUILT ON: every claim in `supers_map.md` — where a table is, which
entry is Saturn's, what is byte-identical across the two games — became a line
in a builder. 552 address tokens, none of them gated.

It needs the Super S donor, so `health.sh` SKIPs it when the donor is absent
rather than pretending; and the checks that matter most are the CROSS-GAME ones,
because those are the claims a port rests on and the ones no single-image check
could ever have caught.

Same discipline as checkdocs, for the same reasons:

    1. the claim is quoted FROM THE DOC and asserted to still be there;
    2. it is re-derived from the cartridge(s);
    3. the two are compared;
    4. and every check is re-run against a WRONG address or the WRONG GAME and
       required to fail — a cross-game check that passes when handed one image
       twice is comparing nothing.

Four claims did not survive being re-derived; they are recorded in the doc with
the measurement, and `git log` has the detail.
"""
import argparse
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "tools"))
sys.path.insert(0, str(REPO / "tools" / "saturn"))
from smspaths import clean_rom, supers_rom  # noqa: E402

DOCS = REPO / "docs" / "project" / "saturn"
SMS = open(clean_rom(), "rb").read()
SUP = open(supers_rom(), "rb").read()


def f(snes):
    return snes & 0x3FFFFF


def r8(R, o):
    return R[o]


def r16(R, o):
    return R[o] | R[o + 1] << 8


def r24(R, o):
    return R[o] | R[o + 1] << 8 | R[o + 2] << 16


class Fail(Exception):
    pass


CHECKS = []


def check(name, *fragments, cross=False, doc="supers_map.md"):
    """Register a check. `fragments` must still appear in `doc`.

    `cross=True` marks a check that COMPARES the games; those get the extra
    negative control of being handed one image twice, which must break them.
    A single-image check legitimately survives that, and demanding otherwise
    would be a self-test that fails for being right.
    """
    def deco(fn):
        CHECKS.append((name, (doc, fragments), fn, cross))
        return fn
    return deco


def says(doc, fragments):
    text = (DOCS / doc).read_text(encoding="utf-8")
    for frag in fragments:
        if frag not in text:
            raise Fail(f"doc no longer says {frag!r} — check is stale, re-read the doc")


def eq(label, doc_value, rom_value):
    if doc_value != rom_value:
        raise Fail(f"{label}: doc says {doc_value!r}, ROM says {rom_value!r}")


# ------------------------------------------------------------ the two games --
@check("the two images are the two games", "`$FFB3`", "| 0x51 | 0x4A |", cross=True)
def _(sms=SMS, sup=SUP):
    eq("SMS game code", 0x51, r8(sms, 0xFFB3))
    eq("Super S game code", 0x4A, r8(sup, 0xFFB3))
    eq("Super S size", 0x300000, len(sup))


# ------------------------------------------------------- Super S structures --
@check("Super S manifest table: null + 10 records, 16 B apart, shared payload field",
       "`$E0:ABC4` (file 0x20ABC4; null+10 recs, 16 B apart — same format)",
       "the final 3-byte field is `$E0:F328` for ALL characters")
def _(sms=SMS, sup=SUP):
    ptrs = [r16(sup, f(0xE0ABC4) + i * 2) for i in range(11)]
    eq("index 0 is null", 0, ptrs[0])
    recs = [f(0xE00000) + p for p in ptrs[1:]]
    eq("stride", [0x10] * 9, [recs[i + 1] - recs[i] for i in range(9)])
    eq("payload field, all ten", {0xE0F328}, {r24(sup, r + 13) for r in recs})


@check("Super S box pointer tables are 11-entry and Saturn is entry 10",
       "`$AF:B000` (char ptrs B072..F32A", "`$AF:B046` (11 e., Saturn at B05A)",
       "`$AF:B05C` (11 e.)",
       "hit `$AF:EC3A` (30 boxes) / hurt `$AF:ED2A` (93 pairs) / coll `$AF:F2FA` (6)")
def _(sms=SMS, sup=SUP):
    hit = [r16(sup, f(0xAFB000) + i * 2) for i in range(12)]
    hurt = [r16(sup, f(0xAFB046) + i * 2) for i in range(11)]
    coll = [r16(sup, f(0xAFB05C) + i * 2) for i in range(11)]
    eq("first char hit table", 0xB072, hit[1])
    eq("hit entry 11", 0xF32A, hit[11])
    eq("Saturn's hit/hurt/coll", (0xEC3A, 0xED2A, 0xF2FA), (hit[10], hurt[10], coll[10]))
    # counts come from contiguity, exactly as they do in SMS
    eq("Saturn box counts", (30, 93, 6),
       ((hurt[10] - hit[10]) // 8, (coll[10] - hurt[10]) // 16, (hit[11] - coll[10]) // 8))


@check("the widened dispatches: 11 entries where SMS has 10",
       "table `$C1:169B` (10 e.) | code `$C1:1622`, table `$C1:16F9` (**11 e.** — widened for Saturn)",
       cross=True)
def _(sms=SMS, sup=SUP):
    s = [r16(sms, f(0xC1169B) + i * 2) for i in range(11)]
    u = [r16(sup, f(0xC116F9) + i * 2) for i in range(12)]
    eq("SMS: null + 9 button-map records", 0, s[0])
    eq("Super S: null + 10", 0, u[0])
    eq("SMS records are 7 bytes apart", [7] * 8, [s[i + 1] - s[i] for i in range(1, 9)])
    eq("Super S records are 7 bytes apart", [7] * 9, [u[i + 1] - u[i] for i in range(1, 10)])
    # the 10th record is Saturn's, and it is the one the port grafts
    eq("Saturn's button-map record address", 0x174E, u[10])
    eq("Saturn's button-map record", "02 00 04 08 06 00 0a",
       sup[f(0xC10000) + 0x174E:f(0xC10000) + 0x174E + 7].hex(" "))


@check("Saturn's manifest, proc block and OAM blob",
       "`$E0:AC6A` (via ptr table idx 10): **first_hit_defense = 1**",
       "Super S adds **Saturn `$C6F7`**", "Saturn\n  `$87:8000`-`$87:BE5E`, 15.6 KB")
def _(sms=SMS, sup=SUP):
    rec = f(0xE0AC6A)
    eq("Saturn's manifest is entry 10", 0xAC6A, r16(sup, f(0xE0ABC4) + 10 * 2))
    eq("first-hit defense", 1, r8(sup, rec))
    eq("Saturn's proc block", 0xC6F7, r16(sup, f(0xC100A6) + 10 * 2))
    eq("Saturn's OAM blob", 0x878000, r24(sup, f(0x848000) + 10 * 3))
    size = 0xBE5E - 0x8000
    if not 15.0 <= size / 1024 <= 16.0:
        raise Fail(f"the OAM blob spans {size} bytes, not ~15.6 KB")


@check("pose-record arrays: the whole roster's addresses, and Saturn's 126 poses",
       "Moon `80E5`, Mercury `82D1`, Mars `84B1`, Jupiter\n  `86B5`, Venus `88B9`, "
       "Uranus `8A99`, Neptune `8C79`, Pluto `8EB9`, Chibi `9071`,\n  **Saturn `9209` "
       "(126 poses)**, end `9401`.")
def _(sms=SMS, sup=SUP):
    got = [r16(sup, f(0x84809F) + i * 2) for i in range(12)]
    eq("the eleven arrays", [0, 0x80E5, 0x82D1, 0x84B1, 0x86B5, 0x88B9, 0x8A99,
                             0x8C79, 0x8EB9, 0x9071, 0x9209, 0x9401], got)
    eq("Saturn's pose count", 126, (got[11] - got[10]) // 4)


@check("the per-character animation triples, including the unidentified 12th slot",
       "Uranus `1299`/`44DA`/`0CC0`", "**Saturn `2105`/`4892`/`1346`**",
       "plus a 12th slot\n`252B`/`499A`/`00CB`")
def _(sms=SMS, sup=SUP):
    def triple(cid):
        return (r16(sup, f(0xC00000) + cid * 2),
                r16(sup, f(0xCB0000) + cid * 4), r16(sup, f(0xCB0000) + cid * 4 + 2))
    eq("Uranus", (0x1299, 0x44DA, 0x0CC0), triple(6))
    eq("Saturn", (0x2105, 0x4892, 0x1346), triple(10))
    eq("the 12th slot", (0x252B, 0x499A, 0x00CB), triple(11))


@check("the effect-tile job: Saturn's stream, and what it decompresses to",
       "jobs from a\n6-byte-entry table at `$80:EEF1`", "Saturn = idx 57/67 → stream "
       "`$E3:FA09`, 0x1040 bytes")
def _(sms=SMS, sup=SUP):
    import supers_lz
    job = f(0x80EEF1) + 57 * 6
    src = (r8(sup, job + 2) << 16) | r16(sup, job)
    eq("Saturn's P1 effect stream", 0xE3FA09, src)
    eq("its VRAM destination", 0x6A00, r16(sup, job + 3))
    eq("decompressed size", 0x1040, len(supers_lz.lz_decompress(sup, f(src))))


# --------------------------------------------------------------- cross-game --
@check("the relocated SMS structures, at the documented shifts",
       "| Char loader body | 0x87D0 | 0x87E8 | +0x18 | first 48 B identical |",
       "| On-hit tables | 0xCDD5 | 0xCEFF | +0x12A | first 0x40 identical |",
       "| Damage matrix | 0xD081 | 0xD1C9 | +0x148 | rows 10 & 48 identical |",
       "| joy_read tail | 0x8373 | 0x8347 | −0x2C | 4 B identical |", cross=True)
def _(sms=SMS, sup=SUP):
    for label, s, u, shift, n in (("char loader", 0x87D0, 0x87E8, 0x18, 48),
                                  ("on-hit tables", 0xCDD5, 0xCEFF, 0x12A, 0x40),
                                  ("joy_read tail", 0x8373, 0x8347, -0x2C, 4)):
        eq(f"{label}: the shift is the difference", u - s, shift)
        if sms[s:s + n] != sup[u:u + n]:
            raise Fail(f"{label}: the first {n} bytes are NOT identical across the games")
    for row in (10, 48):
        if sms[0xD081 + row * 16:0xD081 + row * 16 + 16] != sup[0xD1C9 + row * 16:0xD1C9 + row * 16 + 16]:
            raise Fail(f"damage matrix row {row} differs across the games")


@check("the box-index writer's 16 identical bytes sit exactly at the documented shift",
       "| Box-index writer | $C0:9CCD ctx | 0x9FF9 ctx | +0x32C | 16 B identical |", cross=True)
def _(sms=SMS, sup=SUP):
    eq("0x9CCD + 0x32C", 0x9FF9, 0x9CCD + 0x32C)
    if sms[0x9CCD:0x9CDD] != sup[0x9FF9:0x9FF9 + 16]:
        raise Fail("the writer's 16 bytes are not identical at the documented offset")


@check("Uranus's content is shared across the games — the port's whole premise",
       "pose-record\narray 100% byte-identical (all 115 SMS poses; Super S appended 5)",
       "pose→cels lists\nidentical", "cel records **97 of 98** the same size", cross=True)
def _(sms=SMS, sup=SUP):
    s_arr = r16(sms, f(0x84809C) + 6 * 2)
    u_arr = r16(sup, f(0x84809F) + 6 * 2)
    n_sms = (r16(sms, f(0x84809C) + 7 * 2) - s_arr) // 4
    n_sup = (r16(sup, f(0x84809F) + 7 * 2) - u_arr) // 4
    eq("SMS pose count", 115, n_sms)
    eq("Super S appended five", 120, n_sup)
    if sms[f(0x840000) + s_arr:f(0x840000) + s_arr + n_sms * 4] != \
            sup[f(0x840000) + u_arr:f(0x840000) + u_arr + n_sms * 4]:
        raise Fail("Uranus's pose records are NOT byte-identical across the games")
    s_p2c, s_cel = r16(sms, f(0xCB0000) + 24), r16(sms, f(0xCB0000) + 26)
    u_p2c, u_cel = r16(sup, f(0xCB0000) + 24), r16(sup, f(0xCB0000) + 26)
    if sms[f(0xCB0000) + s_p2c:f(0xCB0000) + s_p2c + n_sms * 2] != \
            sup[f(0xCB0000) + u_p2c:f(0xCB0000) + u_p2c + n_sms * 2]:
        raise Fail("Uranus's pose→cels list is NOT identical across the games")
    same = [k for k in range(1, 99)
            if r16(sms, f(0xCB0000) + s_cel + k * 5 + 3) == r16(sup, f(0xCB0000) + u_cel + k * 5 + 3)]
    eq("cel records of equal size", 97, len(same))
    eq("the one that differs", [29], [k for k in range(1, 99) if k not in same])


@check("the universal-act scripts are identical once Super S's CMD steps are stripped",
       "identical **once Super S's `0xC0` CMD steps are removed**",
       "**43/43 for five characters\n(Moon, Jupiter, Uranus, Neptune, Pluto)**", cross=True)
def _(sms=SMS, sup=SUP):
    def steps(R, base, act):
        p = r16(R, f(0xC00000) + base + act * 2)
        o, out = f(0xC00000) + p, []
        for _ in range(96):
            d = R[o]
            if d & 0xC0 in (0x40, 0x80):
                out.append((d, None))
                break
            out.append((d, R[o + 1]))
            o += 2
        return out
    exact = []
    for cid in range(1, 10):
        sb, ub = r16(sms, f(0xC00000) + cid * 2), r16(sup, f(0xC00000) + cid * 2)
        n = sum(1 for a in range(0x2B)
                if steps(sms, sb, a) == [s for s in steps(sup, ub, a) if s[0] & 0xC0 != 0xC0])
        if n == 0x2B:
            exact.append(cid)
        elif n < 41:
            raise Fail(f"charID {cid}: only {n}/43 universal scripts match after the CMD strip")
    eq("characters matching 43/43", [1, 4, 6, 7, 8], exact)


@check("the engine object-id shift above 0x31",
       "**Super S id N == SMS id N-1 for N >= 0x31**",
       "35-42/48 bytes:\nSUP 31->SMS 30, 32->31, 33->32, 34->33, 35->34 (both $10C2), 36->35",
       cross=True)
def _(sms=SMS, sup=SUP):
    for n in range(0x31, 0x35):
        u, s = r16(sup, f(0xC100A6) + n * 2), r16(sms, f(0xC100A6) + (n - 1) * 2)
        match = sum(1 for k in range(48)
                    if sup[f(0xC10000) + u + k] == sms[f(0xC10000) + s + k])
        if not 35 <= match <= 42:
            raise Fail(f"Super S id {n:#04x} vs SMS {n - 1:#04x}: {match}/48 bytes, doc says 35-42")
    for n, addr in ((0x35, 0x10C2), (0x36, 0x20E2)):
        eq(f"Super S {n:#04x} / SMS {n - 1:#04x} share a proc address", (addr, addr),
           (r16(sup, f(0xC100A6) + n * 2), r16(sms, f(0xC100A6) + (n - 1) * 2)))


@check("the OAM char table's real extent in both games",
       "**52 entries in SMS (ids 0-0x33)\n  and 53 in Super S**", cross=True)
def _(sms=SMS, sup=SUP):
    def extent(R):
        n = 0
        while r24(R, f(0x848000) + n * 3) == 0 or \
                (0x84 <= r24(R, f(0x848000) + n * 3) >> 16 <= 0x8F
                 and (r24(R, f(0x848000) + n * 3) & 0xFFFF) >= 0x8000):
            n += 1
        return n
    eq("SMS entries", 52, extent(sms))
    eq("Super S entries — one more, the inserted object type", 53, extent(sup))


@check("the two character-select voice samples, walked as BRR",
       "**Saturn's select line is at ROM `$EC:C12F`, 2610 bytes (290 BRR blocks).**",
       "Uranus's, for comparison, is at `$EC:998B`, 1404 bytes",
       doc="sound_scope.md")
def _(sms=SMS, sup=SUP):
    def brr_bytes(off):
        """BRR is 9-byte blocks; bit 0 of a block header ends the stream. Walking
        it is how a sample's LENGTH is a fact rather than a note someone wrote."""
        n = 0
        while n < 0x8000:
            h = sup[off + n]
            n += 9
            if h & 1:
                return n
        raise Fail(f"no BRR end flag within 32 KB of 0x{off:06X}")
    eq("Saturn's select line", 2610, brr_bytes(f(0xECC12F)))
    eq("...in 9-byte blocks", 290, 2610 // 9)
    eq("Uranus's select line", 1404, brr_bytes(f(0xEC998B)))


@check("SMS's char-select voice bank-id table — the one byte the port swaps",
       "lda $AE75,X                <- her audio-bank id (22..30 = 21+charID)",
       doc="sound_scope.md")
def _(sms=SMS, sup=SUP):
    ids = [r8(sms, f(0xC0AE75) + cid) for cid in range(10)]
    eq("index 0 unused, then 21 + charID", [0] + [21 + cid for cid in range(1, 10)], ids)


def negative_controls():
    """Two ways for a check to be worthless, both tested every run.

    * **Address sensitivity** — shift one image by a byte; a check that survives
      BOTH shifts is not reading anything address-specific.
    * **Game sensitivity** — hand a cross-game check the same image twice. If it
      still passes it is not comparing the games, which is the only thing those
      checks exist to do. Single-image checks legitimately survive this, so they
      are not asked to fail it: a self-test that fires for being right gets
      deleted, and then nothing is tested at all.
    """
    bad, off_sms, off_sup = [], b"\0" + SMS, b"\0" + SUP
    for name, _, fn, cross in CHECKS:
        survived = []
        for label, args in (("SMS shifted by one byte", (off_sms, SUP)),
                            ("Super S shifted by one byte", (SMS, off_sup))):
            try:
                fn(*args)
                survived.append(label)
            except Exception:
                pass
        if len(survived) == 2:
            bad.append(f"{name!r} survives both one-byte shifts — it pins no address")
        if cross:
            for label, args in (("both images are SMS", (SMS, SMS)),
                                ("both images are Super S", (SUP, SUP))):
                try:
                    fn(*args)
                except Exception:
                    continue
                bad.append(f"{name!r} still passes with {label} — it is not comparing the games")
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    fails = []
    for name, (doc, fragments), fn, _cross in CHECKS:
        try:
            says(doc, fragments)
            fn(SMS, SUP)
            if args.verbose:
                print(f"  \033[32mPASS\033[0m  {name}")
        except Fail as e:
            print(f"  \033[31mFAIL\033[0m  {name}\n          {e}")
            fails.append(name)
        except Exception as e:
            print(f"  \033[31mERROR\033[0m {name}\n          {type(e).__name__}: {e}")
            fails.append(name)

    for line in negative_controls():
        print(f"  \033[31mFAIL\033[0m  [self-test] {line}")
        fails.append(line)

    if fails:
        print(f"\n\033[31m{len(fails)} of {len(CHECKS)} checks FAILED\033[0m")
        sys.exit(1)
    cross = sum(1 for *_, c in CHECKS if c)
    print(f"\n\033[32mALL PASS\033[0m ({len(CHECKS)} checks against both cartridges — "
          f"{cross} cross-game, each proven to fail when handed one image twice; "
          "all proven to fail on a one-byte shift)")


if __name__ == "__main__":
    main()
