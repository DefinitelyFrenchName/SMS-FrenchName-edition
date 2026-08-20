#!/usr/bin/env python3
"""EXPERIMENT (not a numbered patch): the FULL-ROSTER anime-fighter PoC.

    python3 tools/exp_animeroster.py <out.sfc> [--budget N]

Every mechanism the phase experiments proved, generated for ALL NINE
characters from the ROM itself (no per-character hand constants):

  * air backdash (act 0x2B -> the char's OWN backdash handler) and air front
    dash (act 0x2C -> Uranus's Shadow Dash handler $C1:88C8, proven generic),
    animated by the char's own jump-back/jump-fwd scripts;
  * input: 44 in the air = back dash; 66 in the air = front dash. Moon and
    Uranus already own a 66 motion; the other SEVEN get one appended (their
    motion lists are relocated into the measured-dead recognizer region
    $C1:15C4+, and their special-start tables are relocated + extended with
    air-only [flags 02 -> act 2C] entries at the new ids, because the
    positional starter has no bounds check and would otherwise read past the
    sentinel on a grounded 66);
  * dash-cancels: acts 2B/2C share ONE wrapper handler (per-char backdash
    handler via a $C1 jump table, per-char directional-jump stance table via
    an $E8 table) offering the air normals after the vanilla dash frame;
  * the gatling: EVERY air-normal handler tail is hooked — on hit (+0x43),
    airborne, with 44/66 pending, the normal cancels into the air dash;
  * air budget on struct +0x7F (measured free), spent by the jump-stub and
    gatling commits, reset by a landing-handler hook. ⚠ KNOWN PoC LEAK:
    Venus/Jupiter/ChibiMoon's jump handlers natively offer the special table,
    so their FRONT dash also starts through the vanilla starter, uncounted —
    with the budget exhausted these three can still front-dash via that path.
    Leak-free wiring is rollout engineering, not feasibility;
  * air specials: every flags==0x05 (ground+projectile) special-start entry
    is flipped to 0x04 — each character's projectile specials work airborne
    (self-guarding against re-fire via the projectile-slot gate);
  * juggles: the two exp_juggle bytes (launch/air-hitstun reactions write
    0x20, not 0xA0) — GLOBAL [SMS-4], the total-conversion policy.

ARCHITECTURE. Bank $C1 cannot hold nine of everything, so all logic lives in
an APPENDED BANK and $C1 keeps only what its data-bank contract requires:
relocated motion lists and special tables (the interpreter and starter read
them with DB=$C1), a 10-entry backdash-handler jump table, four call gates
(jsr <engine routine> / rtl) and four tiny shims. Handlers must BE in $C1
(the act dispatch is `jmp (tbl,X)` with PB=$C1), so acts 2B/2C point at a
5-byte shim that JSLs into the bank and rts's home. Free $C1 space used: the
documented holes at $BE09/$BE85/$BF00/$BF80 and the measured-dead recognizer
region $15C4-$16ED (exec-hook measured never executed; its 7-byte records at
$169B are read only by that dead code — sms_engine_internals.md §7.y).

Everything is derived from the src ROM at build time and asserted: 27 jump
route hooks, one tail hook per distinct air-normal handler, 9 landing hooks,
null act/script slots, motion counts, table sentinels, ldy repoint counts.

Verify: tools/probe_exp_roster.lua per character + tools/demo_airrush.lua +
the regression suite (its 9-character desperation compendium is the motion-
relocation gate).
"""
import argparse
import hashlib
import sys
from collections import Counter
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import (clean_rom, require_source, check_not_inplace, fix_checksum,
                      next_bank, write_bank, pad_to_size_multiple)

C1 = 0x010000
DISPATCH = C1 + 0x00A6
MOTION_PTRS = C1 + 0x13C7
SCRIPT_66 = 0x1535                    # Uranus's 66 motion script, shared verbatim
SHADOW_DASH = 0x88C8                  # the generic front-dash handler
NAMES = {1: "Moon", 2: "Mercury", 3: "Mars", 4: "Jupiter", 5: "Venus",
         6: "Uranus", 7: "Neptune", 8: "Pluto", 9: "ChibiMoon"}

# $C1 free space (in-bank addresses): the measured-dead recognizer region
# first, then the four documented holes.
C1_REGIONS = [(0x15C4, 0x16EE), (0xBE09, 0xBE48), (0xBE85, 0xBECA),
              (0xBF00, 0xBF40), (0xBF80, 0xBFCA)]


def word(rom, off):
    return rom[off] | rom[off + 1] << 8


def find_first(rom, lo, hi, pat, what, need_ldy=False):
    """First match of pat in [lo,hi) — a handler's first route call / first
    tail belongs to that handler (code runs linearly to its own tail before
    the next handler starts). need_ldy additionally requires an ldy #imm
    immediately before (route calls are always ldy-fed)."""
    i = lo
    while True:
        j = rom.find(pat, i, hi)
        if j < 0:
            raise ValueError(f"{what}: no {pat.hex()} in 0x{lo:06X}-0x{hi:06X}")
        if not need_ldy or rom[j - 3] == 0xA0:
            return j
        i = j + 1


def asm(base, items):
    for _pass in (0, 1):
        out, labels, fixups = bytearray(), {}, []
        pos = base
        for it in items:
            if isinstance(it, tuple) and it[0] == "label":
                labels[it[1]] = pos
            elif isinstance(it, tuple) and it[0] == "b":
                fixups.append((len(out) + 1, pos + 2, it[2]))
                out += bytes([it[1], 0])
                pos += 2
            else:
                out += bytes(it)
                pos += len(it)
        if _pass:
            for at, nxt, lab in fixups:
                d = labels[lab] - nxt
                assert -128 <= d <= 127, f"branch to {lab} out of range ({d})"
                out[at] = d & 0xFF
            return bytes(out)


class Alloc:
    def __init__(self, regions):
        self.regions = [list(r) for r in regions]

    def take(self, n, what):
        for r in self.regions:
            if r[1] - r[0] >= n:
                a = r[0]
                r[0] += n
                return a
        raise ValueError(f"no $C1 space for {what} ({n} B)")


def derive(rom):
    """Per-character facts, all read from the ROM."""
    import dis65816
    procs = {i: word(rom, DISPATCH + i * 2) for i in range(1, 28)}
    bounds = sorted(v for v in procs.values() if v)
    chars = {}
    for cid in range(1, 10):
        lo = C1 + procs[cid]
        later = [v for v in bounds if v > procs[cid]]
        hi = C1 + (min(later) if later else 0xBE09)
        tbl = None
        for a, op, ln, m, x in dis65816.walk(rom, lo, lo + 0x20, m=1, x=0):
            if op == 0x7C:
                tbl = C1 + word(rom, a + 1)
                break
        assert tbl, f"{NAMES[cid]}: no dispatch jmp (tbl,X)"

        def act(n):
            return word(rom, tbl + n * 2)

        # jump handlers + their `ldy #stance / jsr $0459` sites
        jsites, stance = [], {}
        for a_id in (6, 7, 8):
            h = C1 + act(a_id)
            j = find_first(rom, h, h + 0x60, bytes([0x20, 0x59, 0x04]),
                           f"{NAMES[cid]} act{a_id:02X} jsr $0459", need_ldy=True)
            jsites.append(j)
            stance[a_id] = word(rom, j - 2)
        # air-normal acts from both stance tables -> distinct handlers -> tails
        acts = set()
        for st in (stance[6], stance[7]):
            for i in range(4):
                acts.add(rom[C1 + st + i * 3 + 1])
                acts.add(rom[C1 + st + i * 3 + 2])
        handlers = {act(a) for a in acts}
        tails = []
        for h in sorted(handlers):
            tails.append(find_first(rom, C1 + h, C1 + h + 0x40, bytes([0x4C, 0x04, 0x02]),
                                    f"{NAMES[cid]} air-normal ${h:04X} tail"))
        # landing handler's jsr $0459
        h9 = C1 + act(9)
        land = find_first(rom, h9, h9 + 0x60, bytes([0x20, 0x59, 0x04]),
                          f"{NAMES[cid]} landing jsr $0459", need_ldy=True)
        # special table: most common ldy operand before jsr $0958 in the block
        ops = Counter()
        i = lo
        while True:
            j = rom.find(bytes([0x20, 0x58, 0x09]), i, hi)
            if j < 0:
                break
            if rom[j - 3] == 0xA0:
                ops[word(rom, j - 2)] += 1
            i = j + 1
        sptbl = ops.most_common(1)[0][0]
        ents = []
        o = C1 + sptbl
        while not (rom[o] == 0xFF and rom[o + 1] == 0x00):
            ents.append((rom[o], rom[o + 1]))          # (flags, act)
            o += 2
            assert len(ents) <= 16, f"{NAMES[cid]}: special table has no sentinel"
        # motions
        mlist = word(rom, MOTION_PTRS + cid * 2)
        motions = []
        o = C1 + mlist
        while word(rom, o) != 0xFFFF:
            motions.append(word(rom, o))
            o += 2
            assert len(motions) <= 8
        def is66(p):
            s = []
            q = C1 + p
            while rom[q] != 0xFF and len(s) < 12:
                s.append(rom[q + 1] & 0x0F)
                q += 2
            return s == [0, 1, 0, 1]
        has66 = any(is66(p) for p in motions)
        # insertion point for the appended 66: BEFORE any prefix-overlap
        # motion (a pointer q with q+2 == another pointer — Jupiter's m5
        # desperation shares m4's tail; measured: a 66 placed AFTER it never
        # completes, while the same script at any slot up to 6 does)
        ins = len(motions)
        for i, p in enumerate(motions):
            if any(p + 2 == q for q in motions):
                ins = i
                break
        chars[cid] = dict(
            lo=lo, hi=hi, tbl=tbl, backdash=act(0x26),
            slot2B=tbl + 0x2B * 2, slot2C=tbl + 0x2C * 2,
            scripttbl=word(rom, cid * 2), jsites=jsites, stance=stance,
            tails=tails, land=land, sptbl=sptbl, ents=ents,
            mlist=mlist, motions=motions, has66=has66, ins=ins,
            frontid=4 if has66 else 2 * ins + 2)
        if not has66:
            assert len(ents) == 2 * len(motions), \
                f"{NAMES[cid]}: {len(ents)} entries != 2x{len(motions)} motions"
    return chars


def build(src, out, budget):
    rom = bytearray(open(src, "rb").read())
    chars = derive(rom)
    alloc = Alloc(C1_REGIONS)
    log = []

    # ---- appended bank ------------------------------------------------
    bankbase, snesbank = next_bank(rom)
    eb = snesbank  # e.g. 0xE8

    # ---- $C1: data + gates + shims ------------------------------------
    # BDTBL: 10 words, charID*2 -> backdash handler
    bdtbl = alloc.take(20, "BDTBL")
    for cid in range(1, 10):
        rom[C1 + bdtbl + cid * 2:C1 + bdtbl + cid * 2 + 2] = chars[cid]["backdash"].to_bytes(2, "little")
    # gates
    g0459 = alloc.take(4, "gate 0459"); rom[C1 + g0459:C1 + g0459 + 4] = bytes([0x20, 0x59, 0x04, 0x6B])
    g0224 = alloc.take(4, "gate 0224"); rom[C1 + g0224:C1 + g0224 + 4] = bytes([0x20, 0x24, 0x02, 0x6B])
    g0204 = alloc.take(4, "gate 0204"); rom[C1 + g0204:C1 + g0204 + 4] = bytes([0x20, 0x04, 0x02, 0x6B])
    gshad = alloc.take(4, "gate shadow"); rom[C1 + gshad:C1 + gshad + 4] = bytes([0x20, SHADOW_DASH & 0xFF, SHADOW_DASH >> 8, 0x6B])
    gbd = alloc.take(5, "gate bdtbl"); rom[C1 + gbd:C1 + gbd + 5] = bytes([0xFC, bdtbl & 0xFF, bdtbl >> 8, 0x6B, 0x00])

    # $E8 layout (data first, then code assembled below)
    FRONTID_E8 = 0x0000               # 16 bytes
    NTBL_E8 = 0x0010                  # 20 bytes
    CODE_E8 = 0x0030

    def jsl(a, bank=None):
        bank = eb if bank is None else bank
        return [0x22, a & 0xFF, (a >> 8) & 0xFF, bank]

    def frontid_lookup():
        """charID -> FRONTID (in A, 8-bit); clobbers X; expects X=obj on entry."""
        return [
            [0x48],                    # pha             (the masked nibble)
            [0xB5, 0x00],              # lda $00,X       charID
            [0xC2, 0x20],              # rep #$20
            [0x29, 0xFF, 0x00],        # and #$00FF
            [0xAA],                    # tax
            [0xE2, 0x20],              # sep #$20
            [0xBF, FRONTID_E8 & 0xFF, FRONTID_E8 >> 8, eb],   # lda FRONTID,X (long)
            [0xC3, 0x01],              # cmp $01,S
            ("b", 0xF0, "isfront"),
            [0x68],                    # pla
            ("b", 0x80, "done"),
            ("label", "isfront"),
            [0x68],                    # pla
            [0xA9, 0x2C],              # lda #$2C
            ("b", 0x80, "commit"),
        ]

    def commit_tail():
        return [
            ("label", "goback"),
            [0xA9, 0x2B],
            ("label", "commit"),
            [0xC2, 0x10], [0xA6, 0x88],           # restore X = object
            [0xF6, 0x7F],                          # inc $7F,X (the budget)
            jsl(g0224, 0xC1),
            ("label", "done"),
            # EVERY exit restores X = object: the frontid lookup left X=charID,
            # and the handler continuation (double jump, $0336, the $0958
            # starter) indexes the struct through X without reloading — with
            # X=charID the desperation nibble was read from $005A and Chibi's
            # air desperation died (caught by the regression compendium).
            [0xC2, 0x10], [0xA6, 0x88],
            [0x6B],                                # rtl
        ]

    jstub_items = ([jsl(g0459, 0xC1),
                    [0xC2, 0x10], [0xA6, 0x88], [0xE2, 0x20],
                    [0xB5, 0x16], [0x29, 0x80], ("b", 0xD0, "done"),
                    [0xB5, 0x7F], [0xC9, budget], ("b", 0xB0, "done"),
                    [0xB5, 0x51], [0x29, 0x0E], ("b", 0xF0, "done"),
                    [0xC9, 0x02], ("b", 0xF0, "goback")]
                   + frontid_lookup() + commit_tail())

    gat_items = ([[0xC2, 0x10], [0xA6, 0x88], [0xE2, 0x20],
                  [0xB5, 0x43], ("b", 0xF0, "done"),
                  [0xB5, 0x16], [0x29, 0x80], ("b", 0xD0, "done"),
                  [0xB5, 0x7F], [0xC9, budget], ("b", 0xB0, "done"),
                  [0xB5, 0x51], [0x29, 0x0E], ("b", 0xF0, "done"),
                  [0xC9, 0x02], ("b", 0xF0, "goback")]
                 + frontid_lookup() + commit_tail())

    wrap_items = [
        [0xC2, 0x30], [0xA6, 0x88], [0xE2, 0x20],
        [0xB5, 0x01], [0xC9, 0x2B], ("b", 0xF0, "back"),
        jsl(gshad, 0xC1),                       # front: the shared Shadow Dash
        ("b", 0x80, "post"),
        ("label", "back"),
        [0xB5, 0x00], [0xC2, 0x20], [0x29, 0xFF, 0x00], [0x0A], [0xAA],
        jsl(gbd, 0xC1),                         # per-char backdash via (BDTBL,X)
        ("label", "post"),
        [0xC2, 0x30], [0xA6, 0x88], [0xE2, 0x20],
        [0xB5, 0x16], [0x29, 0x80], ("b", 0xD0, "fin"),
        [0xB5, 0x01], [0xC9, 0x2B], ("b", 0xF0, "rt"),
        [0xC9, 0x2C], ("b", 0xD0, "fin"),
        ("label", "rt"),
        [0xB5, 0x00], [0xC2, 0x30], [0x29, 0xFF, 0x00], [0x0A], [0xAA],
        [0xBF, NTBL_E8 & 0xFF, NTBL_E8 >> 8, eb], [0xA8],   # Y = dir stance table
        [0xA6, 0x88], [0xE2, 0x20],
        jsl(g0459, 0xC1),
        [0xC2, 0x10], [0xA6, 0x88], [0xE2, 0x20],
        [0xB5, 0x02], ("b", 0xD0, "fin"),
        jsl(g0204, 0xC1),                       # re-latch: routes ran after the tail
        ("label", "fin"),
        [0x6B],
    ]

    rst_items = [[0xC2, 0x10], [0xA6, 0x88], [0xE2, 0x20], [0x74, 0x7F], [0x6B]]

    jstub_e8 = asm(CODE_E8, jstub_items)
    gat_e8 = asm(CODE_E8 + len(jstub_e8), gat_items)
    wrap_e8 = asm(CODE_E8 + len(jstub_e8) + len(gat_e8), wrap_items)
    rst_e8 = asm(CODE_E8 + len(jstub_e8) + len(gat_e8) + len(wrap_e8), rst_items)
    JSTUB = CODE_E8
    GAT = JSTUB + len(jstub_e8)
    WRAP = GAT + len(gat_e8)
    RST = WRAP + len(wrap_e8)

    blob = bytearray(0x10000)
    for cid in range(1, 10):
        blob[FRONTID_E8 + cid] = chars[cid]["frontid"]
        blob[NTBL_E8 + cid * 2:NTBL_E8 + cid * 2 + 2] = chars[cid]["stance"][7].to_bytes(2, "little")
    code = jstub_e8 + gat_e8 + wrap_e8 + rst_e8
    blob[CODE_E8:CODE_E8 + len(code)] = code
    blob = bytes(blob[:CODE_E8 + len(code)])

    # ---- $C1 shims ----------------------------------------------------
    jshim = alloc.take(5, "jump shim")
    rom[C1 + jshim:C1 + jshim + 5] = bytes(jsl(JSTUB)) + b"\x60"
    gatshim = alloc.take(7, "gatling shim")
    rom[C1 + gatshim:C1 + gatshim + 7] = bytes(jsl(GAT)) + bytes([0x4C, 0x04, 0x02])
    wrapshim = alloc.take(5, "wrapper shim")
    rom[C1 + wrapshim:C1 + wrapshim + 5] = bytes(jsl(WRAP)) + b"\x60"
    rshim = alloc.take(8, "reset shim")
    rom[C1 + rshim:C1 + rshim + 8] = bytes(jsl(RST)) + bytes([0x20, 0x59, 0x04, 0x60])

    # ---- per-character wiring -----------------------------------------
    n_j = n_t = n_l = n_flip = 0
    for cid in range(1, 10):
        c, nm = chars[cid], NAMES[cid]
        # act slots 2B/2C -> wrapper shim
        for slot in (c["slot2B"], c["slot2C"]):
            assert rom[slot:slot + 2] == b"\0\0", f"{nm}: act slot not null"
            rom[slot:slot + 2] = wrapshim.to_bytes(2, "little")
        # script slots 2B (jump-back, slot 8) / 2C (jump-fwd, slot 7)
        st = c["scripttbl"]
        for slot, src_slot in ((0x2B, 8), (0x2C, 7)):
            o = st + slot * 2
            assert rom[o:o + 2] == b"\0\0", f"{nm}: script slot {slot:02X} not null"
            rom[o:o + 2] = word(rom, st + src_slot * 2).to_bytes(2, "little")
        # jump-handler hooks
        for j in c["jsites"]:
            rom[j:j + 3] = bytes([0x20, jshim & 0xFF, jshim >> 8])
            n_j += 1
        # gatling tail hooks
        for tail in c["tails"]:
            rom[tail:tail + 3] = bytes([0x4C, gatshim & 0xFF, gatshim >> 8])
            n_t += 1
        # landing reset hook
        rom[c["land"]:c["land"] + 3] = bytes([0x20, rshim & 0xFF, rshim >> 8])
        n_l += 1
        # motion append + special-table extension for the seven without a 66
        if not c["has66"]:
            ins = c["ins"]
            mo = list(c["motions"])
            mo.insert(ins, SCRIPT_66)
            newlist = b"".join(p.to_bytes(2, "little") for p in mo) + b"\xFF\xFF"
            ml = alloc.take(len(newlist), f"{nm} motion list")
            rom[C1 + ml:C1 + ml + len(newlist)] = newlist
            rom[MOTION_PTRS + cid * 2:MOTION_PTRS + cid * 2 + 2] = ml.to_bytes(2, "little")
            ents = list(c["ents"])
            ents[2 * ins:2 * ins] = [(0x02, 0x2C), (0x02, 0x2C)]
            newtbl = b"".join(bytes([f, a]) for f, a in ents) + b"\xFF\x00"
            tb = alloc.take(len(newtbl), f"{nm} special table")
            rom[C1 + tb:C1 + tb + len(newtbl)] = newtbl
            # repoint every ldy #<old table> in the char's proc block
            oldpat = bytes([0xA0, c["sptbl"] & 0xFF, c["sptbl"] >> 8])
            newpat = bytes([0xA0, tb & 0xFF, tb >> 8])
            n = 0
            i = c["lo"]
            while True:
                j = rom.find(oldpat, i, c["hi"])
                if j < 0:
                    break
                rom[j:j + 3] = newpat
                n += 1
                i = j + 3
            assert n >= 15, f"{nm}: only {n} special-table ldy sites repointed"
            assert rom.find(oldpat, c["lo"], c["hi"]) < 0
            log.append(f"  {nm}: motion+66 -> ids {c['frontid']:02X}/{c['frontid']+1:02X}, "
                       f"special table -> ${tb:04X} ({n} ldy sites), +2 air entries")
            c["sptbl"] = tb
            c["ents"] = ents
        # air-special flips (in the final table location)
        for idx, (f, a) in enumerate(c["ents"]):
            if f == 0x05:
                rom[C1 + c["sptbl"] + idx * 2] = 0x04
                n_flip += 1
    # juggle: the two exp_juggle bytes
    for off, name in ((0x010FA9, "launch 0x1B"), (0x0110A1, "air hitstun 0x16")):
        assert rom[off - 1] == 0xA9 and rom[off] == 0xA0 and rom[off + 1:off + 3] == bytes([0x95, 0x46])
        rom[off] = 0x20

    write_bank(rom, bankbase, blob)
    pad_to_size_multiple(rom)
    fix_checksum(rom)
    open(out, "wb").write(rom)
    for line in log:
        print(line)
    print(f"  hooks: {n_j} jump sites, {n_t} air-normal tails, {n_l} landing sites, "
          f"{n_flip} air-special flips, juggle 2 bytes")
    print(f"  bank ${0xC0 + (bankbase >> 16):02X}: {len(blob)} B "
          f"(jstub {len(jstub_e8)}, gat {len(gat_e8)}, wrap {len(wrap_e8)}, rst {len(rst_e8)})")
    print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}  [budget N={budget}]")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="EXPERIMENT: full-roster anime-fighter PoC.")
    ap.add_argument("out")
    ap.add_argument("src", nargs="?", default=None)
    ap.add_argument("--stacked", action="store_true")
    ap.add_argument("--budget", type=int, default=2)
    a = ap.parse_args()
    src = a.src or clean_rom()
    require_source(src, stacked=a.stacked)
    check_not_inplace(src, a.out)
    build(src, a.out, a.budget)
