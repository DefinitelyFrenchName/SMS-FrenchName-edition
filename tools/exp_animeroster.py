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
        # ground handlers (idle/walk fwd/walk back/crouch) route sites + the
        # standing stance table (idle's ldy operand) -> the 5HK far act, which
        # the universal launcher wrapper reuses
        gsites = []
        gstance = None
        for a_id in (0, 1, 2, 3):
            h = C1 + act(a_id)
            j = find_first(rom, h, h + 0x80, bytes([0x20, 0x59, 0x04]),
                           f"{NAMES[cid]} act{a_id:02X} jsr $0459", need_ldy=True)
            gsites.append(j)
            if a_id == 0:
                gstance = word(rom, j - 2)
        hk_act = rom[C1 + gstance + 10]          # record 4 (HK), far act
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
            gsites=gsites, hk_act=hk_act,
            frontid=4 if has66 else 2 * ins + 2)
        if not has66:
            assert len(ents) == 2 * len(motions), \
                f"{NAMES[cid]}: {len(ents)} entries != 2x{len(motions)} motions"
    return chars


def build(src, out, budget, juggle, airdash=None, launcher_id=12):
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
    g0958 = alloc.take(4, "gate 0958"); rom[C1 + g0958:C1 + g0958 + 4] = bytes([0x20, 0x58, 0x09, 0x6B])
    # HKTBL: charID*2 -> the char's standing-HK handler (the launcher's inner move)
    hktbl = alloc.take(20, "HKTBL")
    for cid in range(1, 10):
        hk_handler = word(rom, chars[cid]["tbl"] + chars[cid]["hk_act"] * 2)
        rom[C1 + hktbl + cid * 2:C1 + hktbl + cid * 2 + 2] = hk_handler.to_bytes(2, "little")
    ghk = alloc.take(5, "gate hktbl"); rom[C1 + ghk:C1 + ghk + 5] = bytes([0xFC, hktbl & 0xFF, hktbl >> 8, 0x6B, 0x00])
    g10A9 = alloc.take(4, "gate 10A9"); rom[C1 + g10A9:C1 + g10A9 + 4] = bytes([0x20, 0xA9, 0x10, 0x6B])

    # ---- data relocation FIRST (the air-GC route needs the FINAL special
    # table addresses in the appended bank) ---------------------------------
    for cid in range(1, 10):
        c, nm = chars[cid], NAMES[cid]
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

    # $E8 layout (data first, then code assembled below)
    FRONTID_E8 = 0x0000               # 16 bytes
    NTBL_E8 = 0x0010                  # 20 bytes
    SPTBL_E8 = 0x0024                 # 20 bytes: charID -> FINAL special table
    CODE_E8 = 0x0040

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
    ] + ([] if airdash is None else [
        # --airdash-speed: override the front dash's X velocity, matching the
        # sign the inner Shadow Dash handler chose (0x0B00 / -0x0B00 = $F500)
        [0xB5, 0x01], [0xC9, 0x2C], ("b", 0xD0, "nospd"),
        [0xC2, 0x20],
        [0xB5, 0x30], [0xC9, 0x00, 0x0B], ("b", 0xD0, "spdneg"),
        [0xA9, airdash & 0xFF, airdash >> 8], [0x95, 0x30], ("b", 0x80, "spddone"),
        ("label", "spdneg"),
        [0xC9, 0x00, 0xF5], ("b", 0xD0, "spddone"),
        [0xA9, (-airdash) & 0xFF, ((-airdash) >> 8) & 0xFF], [0x95, 0x30],
        ("label", "spddone"),
        [0xE2, 0x20],
        ("label", "nospd"),
    ]) + [
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

    rst_items = [[0xC2, 0x10], [0xA6, 0x88], [0xE2, 0x20], [0x74, 0x7F], [0x74, 0x7E], [0x6B]]

    # --- AIR BLOCK -------------------------------------------------------
    # Fork stub: replaces the 6-byte `lda $08 / and #$03 / and $0A` at BOTH
    # resolution fork sites (the following `beq +3 / jmp <block path>` stays).
    # Returns the verdict in the Z flag: Z=0 -> BLOCKED. Vanilla verdict
    # first; then the air extension — the victim (struct base in Y, a PLAYER
    # slot only) is airborne, holding back, and in a guardable act (a jump
    # act 06-08 or air blockstun 0x2D itself). DB is the caller's $80 mirror,
    # so absolute,Y struct reads land in WRAM.
    fork_items = [
        [0xE2, 0x20],
        [0xA5, 0x08], [0x29, 0x03], [0x25, 0x0A],
        ("b", 0xD0, "blocked"),               # vanilla says blocked
        [0xA5, 0x08], [0x29, 0x03],
        ("b", 0xF0, "clean"),                 # attack carries no H/L class
        [0xC0, 0x00, 0x10],                   # cpy #$1000 (X flag: 16-bit here)
        ("b", 0xF0, "pl"),
        [0xC0, 0x80, 0x10],                   # cpy #$1080
        ("b", 0xD0, "clean"),                 # victim is not a player slot
        ("label", "pl"),
        [0xB9, 0x16, 0x00], [0x29, 0x80],     # grounded -> vanilla only
        ("b", 0xD0, "clean"),
        [0xB9, 0x01, 0x00],                   # victim act
        [0xC9, 0x2D], ("b", 0xF0, "held"),    # re-block from air blockstun
        [0xC9, 0x06], ("b", 0x90, "clean"),
        [0xC9, 0x09], ("b", 0xB0, "clean"),
        ("label", "held"),
        # guard-hold = +0x50 bit0, MEASURED: a grounded victim blocking in the
        # guard pose latches 0x01 (the doc's bit0=fwd/bit1=back mask mapping
        # does not transfer to this latch — the polarity is the other way)
        [0xB9, 0x50, 0x00], [0x29, 0x01],
        ("b", 0xF0, "clean"),
        ("label", "blocked"),
        [0xA9, 0x01], [0x6B],                 # NZ -> the block path
        ("label", "clean"),
        [0xA9, 0x00], [0x6B],                 # Z -> the damage path
    ]

    # Air-block REACTION handler (rows 1/2 of the air sub-table $C1:0EBB):
    # mark in-blockstun (targetable 0x20), arm the +0x7E timer, stage act 0x2D.
    ABLOCK_FRAMES = 14
    react_items = [
        [0xC2, 0x30], [0xA6, 0x88], [0xE2, 0x20],
        [0xA9, 0x20], [0x95, 0x46],
        [0xA9, ABLOCK_FRAMES], [0x95, 0x79],
        [0xA9, 0x2D], jsl(g10A9, 0xC1),
        [0x6B],
    ]

    # Act 0x2D — AIR BLOCKSTUN (all nine act tables): hold the guard pose
    # (script slot 0x2D = the char's stand-guard script), fall under vanilla
    # physics, land into act 09, expire into falling act 07, and offer the
    # specials route every frame — the AIR GUARD CANCEL (the flag byte
    # filters it to air-legal moves: the [02->2C] front dash and the
    # 0x04-flagged air-enabled projectiles).
    ablock_items = [
        [0xC2, 0x30], [0xA6, 0x88], [0xE2, 0x20],
        [0xB5, 0x16], [0x29, 0x80],
        ("b", 0xF0, "airb"),
        [0xA9, 0x09], jsl(g0224, 0xC1),       # grounded: land normally
        ("b", 0x80, "tail"),
        ("label", "airb"),
        [0xD6, 0x79],                          # dec $79,X (blockstun timer)
        ("b", 0xD0, "routes"),
        [0xA9, 0x07], jsl(g0224, 0xC1),       # blockstun over: fall (act 07)
        ("b", 0x80, "tail"),
        ("label", "routes"),
        [0xB5, 0x00], [0xC2, 0x30], [0x29, 0xFF, 0x00], [0x0A], [0xAA],
        [0xBF, SPTBL_E8 & 0xFF, SPTBL_E8 >> 8, eb], [0xA8],
        [0xA6, 0x88], [0xE2, 0x20],
        jsl(g0958, 0xC1),                      # specials-route GC (air fireballs)
        [0xC2, 0x10], [0xA6, 0x88], [0xE2, 0x20],
        # DIRECT dash GC — same gate as the jump stub: 44 -> 2B, 66 -> 2C,
        # budget-checked. This is what makes dash-GC reachable for ALL NINE
        # (Moon/Uranus have no air-legal table entries) and for the 44.
        [0xB5, 0x7F], [0xC9, budget], ("b", 0xB0, "done"),
        [0xB5, 0x51], [0x29, 0x0E], ("b", 0xF0, "done"),
        [0xC9, 0x02], ("b", 0xF0, "goback"),
    ] + frontid_lookup() + [
        ("label", "goback"),
        [0xA9, 0x2B],
        ("label", "commit"),
        [0xC2, 0x10], [0xA6, 0x88],
        [0xF6, 0x7F],
        jsl(g0224, 0xC1),
        ("label", "done"),
        ("label", "tail"),
        [0xC2, 0x10], [0xA6, 0x88],            # X-restore law
        jsl(g0204, 0xC1),
        [0x6B],
    ]

    jstub_e8 = asm(CODE_E8, jstub_items)
    gat_e8 = asm(CODE_E8 + len(jstub_e8), gat_items)
    wrap_e8 = asm(CODE_E8 + len(jstub_e8) + len(gat_e8), wrap_items)
    rst_e8 = asm(CODE_E8 + len(jstub_e8) + len(gat_e8) + len(wrap_e8), rst_items)
    JSTUB = CODE_E8
    GAT = JSTUB + len(jstub_e8)
    WRAP = GAT + len(gat_e8)
    RST = WRAP + len(wrap_e8)
    FORK = RST + len(rst_e8)
    fork_e8 = asm(FORK, fork_items)
    REACT = FORK + len(fork_e8)
    react_e8 = asm(REACT, react_items)
    ABLOCK = REACT + len(react_e8)
    ablock_e8 = asm(ABLOCK, ablock_items)
    # JUGGLE DECAY: replaces the launch/air-hitstun handlers' 4-byte
    # `lda #$A0 / sta $46,X`. Counts airborne reactions in +0x7E (cleared by
    # the landing reset): soft (targetable 0x20) for the first N, untargetable
    # 0xA0 after. juggle=0 keeps vanilla untargetability (no juggles).
    decay_items = [
        [0xF6, 0x7E],                          # inc $7E,X
        [0xB5, 0x7E],
        [0xC9, max(juggle, 0) + 1],            # cmp #N+1
        ("b", 0x90, "soft"),
        [0xA9, 0xA0],
        ("b", 0x80, "st"),
        ("label", "soft"),
        [0xA9, 0x20],
        ("label", "st"),
        [0x95, 0x46],                          # sta $46,X
        [0x6B],
    ]
    DECAY = ABLOCK + len(ablock_e8)
    decay_e8 = asm(DECAY, decay_items)
    # GROUND STUB (idle/walk/crouch route sites): the UNIVERSAL LAUNCHER
    # input — fresh LK+HK together, grounded — commits act 0x2E and SKIPS the
    # normals route (else the vanilla call would also start 5LK); otherwise
    # behaves exactly as the original `jsr $0459`.
    gstub_items = [
        [0xC2, 0x10], [0xA6, 0x88], [0xE2, 0x20],
        [0xB5, 0x16], [0x29, 0x80], ("b", 0xF0, "van"),   # airborne -> vanilla
        [0xB5, 0x50], [0x29, 0xF0], [0xC9, 0xA0],          # fresh LK+HK exactly
        ("b", 0xD0, "van"),
        [0xA9, 0x2E], jsl(g0224, 0xC1),
        [0xC2, 0x10], [0xA6, 0x88], [0x6B],
        ("label", "van"),
        jsl(g0459, 0xC1),
        [0xC2, 0x10], [0xA6, 0x88], [0x6B],
    ]
    GSTUB = DECAY + len(decay_e8)
    gstub_e8 = asm(GSTUB, gstub_items)
    # LAUNCHER wrapper (act 0x2E, all nine): runs the char's OWN standing-HK
    # handler (anim/boxes/timing reused wholesale), then forces the attack
    # class to LAUNCHER_ID — attackID 12 -> on-hit idx 6, whose record byte0
    # is code 0x14 = the STAND sub-table's POP-UP LAUNCH row (act 0x1B,
    # vy -1792 / gravity 96). Safe ordering: attacks process from the frame
    # AFTER start [SMS-8], and the overwrite lands before any hit frame.
    launch_items = [
        [0xC2, 0x30], [0xA6, 0x88], [0xE2, 0x20],
        [0xB5, 0x00], [0xC2, 0x20], [0x29, 0xFF, 0x00], [0x0A], [0xAA],
        jsl(ghk, 0xC1),
        [0xC2, 0x10], [0xA6, 0x88], [0xE2, 0x20],
        [0xA9, launcher_id], [0x95, 0x44],
        # while the launcher's hit is latched: soften ITS victim (the 0x1A
        # stager writes 0xA0 at frame top; the attacker's proc runs after, so
        # this wins — launcher-only juggle-softness), and — Hercules Throw —
        # convert the fresh vanilla pop-up (act 0x1A) into WALLFLY act 0x2F:
        # flat, fast, backwards, still in hitstun; the 0x2F handler does the
        # wall bounce. The act==0x1A edge makes the conversion fire exactly
        # once per connect. The vanilla stage already set the AWAY-facing X
        # velocity sign via $0389, so the flight speed reuses that sign.
        [0xB5, 0x43],
        ("b", 0xF0, "nosoft"),
        [0xC2, 0x30], [0x8A],                  # txa (X = our struct base)
        [0x49, 0x80, 0x00], [0xAA],            # eor #$0080 -> the OTHER player
        [0xE2, 0x20],
        [0xA9, 0x20], [0x95, 0x46],
        [0xB5, 0x01], [0xC9, 0x1A],            # only the fresh vanilla pop-up
        ("b", 0xD0, "conv_done"),
        [0xA9, 0x2F], [0x95, 0x01], [0x95, 0x04],
        [0x74, 0x02], [0x74, 0x07], [0x74, 0x06],
        [0xC2, 0x20],
        [0xB5, 0x30],                          # the stage's away-sign
        ("b", 0x10, "flyr"),
        [0xA9, 0x00, 0xF4],                    # vx = -0x0C00
        ("b", 0x80, "flyw"),
        ("label", "flyr"),
        [0xA9, 0x00, 0x0C],                    # vx = +0x0C00
        ("label", "flyw"),
        [0x95, 0x30],
        [0xA9, 0x80, 0xFE], [0x95, 0x32],      # vy = -0x0180 (shallow lift)
        [0xA9, 0x10, 0x00], [0x95, 0x34],      # gravity 0x0010 (near-flat)
        [0xE2, 0x20],
        ("label", "conv_done"),
        [0xC2, 0x30], [0xA6, 0x88],
        ("label", "nosoft"),
        [0x6B],
    ]
    LAUNCH = GSTUB + len(gstub_e8)
    launch_e8 = asm(LAUNCH, launch_items)
    # WALLFLY (act 0x2F, all nine): fly until the X position stops moving
    # (the wall or camera bound — position-delta detection is mechanism-
    # independent; last x-low remembered in +0x79, free in this state), then
    # BOUNCE: reversed X, upward impulse, real gravity, air hitstun act 0x16
    # (juggle-soft, lands like any juggle). Step doubles as a timeout.
    wallfly_items = [
        [0xC2, 0x30], [0xA6, 0x88], [0xE2, 0x20],
        [0xF6, 0x02],                          # step = frame counter
        [0xB5, 0x02], [0xC9, 70], ("b", 0xB0, "bail"),
        [0xC9, 0x04], ("b", 0x90, "track"),    # let the flight start first
        [0xB5, 0x21], [0xD5, 0x79], ("b", 0xD0, "track"),
        # the wall: reverse X (sign from current), pop up, real gravity
        [0xC2, 0x20],
        [0xB5, 0x30],
        ("b", 0x10, "toleft"),
        [0xA9, 0x80, 0x04],                    # was flying left -> bounce right
        ("b", 0x80, "bset"),
        ("label", "toleft"),
        [0xA9, 0x80, 0xFB],                    # was flying right -> bounce left
        ("label", "bset"),
        [0x95, 0x30],
        [0xA9, 0x00, 0xFB], [0x95, 0x32],      # vy = -0x0500
        [0xA9, 0x60, 0x00], [0x95, 0x34],      # gravity 0x60
        [0xE2, 0x20],
        ("label", "bail"),
        [0xA9, 0x16], jsl(g0224, 0xC1),        # air hitstun: the juggle state
        ("b", 0x80, "tail"),
        ("label", "track"),
        [0xB5, 0x21], [0x95, 0x79],
        ("label", "tail"),
        [0xC2, 0x10], [0xA6, 0x88],
        jsl(g0204, 0xC1),
        [0x6B],
    ]
    WALLFLY = LAUNCH + len(launch_e8)
    wallfly_e8 = asm(WALLFLY, wallfly_items)

    blob = bytearray(0x10000)
    for cid in range(1, 10):
        blob[FRONTID_E8 + cid] = chars[cid]["frontid"]
        blob[NTBL_E8 + cid * 2:NTBL_E8 + cid * 2 + 2] = chars[cid]["stance"][7].to_bytes(2, "little")
        blob[SPTBL_E8 + cid * 2:SPTBL_E8 + cid * 2 + 2] = chars[cid]["sptbl"].to_bytes(2, "little")
    code = jstub_e8 + gat_e8 + wrap_e8 + rst_e8 + fork_e8 + react_e8 + ablock_e8 + decay_e8 + gstub_e8 + launch_e8 + wallfly_e8
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
    reactshim = alloc.take(5, "airblock reaction shim")
    rom[C1 + reactshim:C1 + reactshim + 5] = bytes(jsl(REACT)) + b"\x60"
    abshim = alloc.take(5, "airblock act shim")
    rom[C1 + abshim:C1 + abshim + 5] = bytes(jsl(ABLOCK)) + b"\x60"
    gshim = alloc.take(5, "ground-route shim")
    rom[C1 + gshim:C1 + gshim + 5] = bytes(jsl(GSTUB)) + b"\x60"
    launchshim = alloc.take(5, "launcher act shim")
    rom[C1 + launchshim:C1 + launchshim + 5] = bytes(jsl(LAUNCH)) + b"\x60"
    wfshim = alloc.take(5, "wallfly act shim")
    rom[C1 + wfshim:C1 + wfshim + 5] = bytes(jsl(WALLFLY)) + b"\x60"

    # ---- AIR BLOCK global wiring --------------------------------------
    # the two resolution fork sites ($C0:C06A / $C0:C13D, running from the
    # $80 mirror): 6-byte test -> jsl fork-stub + 2 nops; branch untouched
    for off in (0x00C06A, 0x00C13D):
        if rom[off:off + 6] != bytes([0xA5, 0x08, 0x29, 0x03, 0x25, 0x0A]):
            raise ValueError(f"0x{off:06X}: block-fork test bytes not found")
        rom[off:off + 6] = bytes(jsl(FORK)) + bytes([0xEA, 0xEA])
    # air sub-table rows 1/2 (block codes 02/04) -> the reaction shim
    for off in (0x010EBD, 0x010EBF):
        if word(rom, off) != 0x0F92:
            raise ValueError(f"0x{off:06X}: air sub-table row is not $0F92")
        rom[off:off + 2] = reactshim.to_bytes(2, "little")

    # ---- per-character wiring -----------------------------------------
    n_j = n_t = n_l = 0
    n_flip = sum(1 for cid in range(1, 10) for f, a in chars[cid]["ents"] if f == 0x05)
    for cid in range(1, 10):
        c, nm = chars[cid], NAMES[cid]
        # act slots 2B/2C -> wrapper shim; 2D -> air blockstun
        for slot in (c["slot2B"], c["slot2C"]):
            assert rom[slot:slot + 2] == b"\0\0", f"{nm}: act slot not null"
            rom[slot:slot + 2] = wrapshim.to_bytes(2, "little")
        slot2D = c["tbl"] + 0x2D * 2
        assert rom[slot2D:slot2D + 2] == b"\0\0", f"{nm}: act slot 2D not null"
        rom[slot2D:slot2D + 2] = abshim.to_bytes(2, "little")
        slot2E = c["tbl"] + 0x2E * 2
        assert rom[slot2E:slot2E + 2] == b"\0\0", f"{nm}: act slot 2E not null"
        rom[slot2E:slot2E + 2] = launchshim.to_bytes(2, "little")
        slot2F = c["tbl"] + 0x2F * 2
        assert rom[slot2F:slot2F + 2] == b"\0\0", f"{nm}: act slot 2F not null"
        rom[slot2F:slot2F + 2] = wfshim.to_bytes(2, "little")
        # script slots 2B (jump-back, 8) / 2C (jump-fwd, 7) / 2D (guard pose, 0x0C)
        st = c["scripttbl"]
        for slot, src_slot in ((0x2B, 8), (0x2C, 7), (0x2D, 0x0C), (0x2E, c["hk_act"]), (0x2F, 0x1A)):
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
        # ground-route hooks (the universal-launcher input)
        for j in c["gsites"]:
            rom[j:j + 3] = bytes([0x20, gshim & 0xFF, gshim >> 8])
    # juggle enablement WITH DECAY: hook the launch/air-hitstun handlers'
    # `lda #$A0 / sta $46,X` (4 bytes) -> jsl decay
    for off, name in ((0x010FA8, "launch 0x1B"), (0x0110A0, "air hitstun 0x16")):
        if rom[off:off + 4] != bytes([0xA9, 0xA0, 0x95, 0x46]):
            raise ValueError(f"{name}: lda #$A0/sta $46,X not found at 0x{off:06X}")
        rom[off:off + 4] = bytes(jsl(DECAY))

    write_bank(rom, bankbase, blob)
    pad_to_size_multiple(rom)
    fix_checksum(rom)
    open(out, "wb").write(rom)
    for line in log:
        print(line)
    print(f"  hooks: {n_j} jump sites, {n_t} air-normal tails, {n_l} landing sites, "
          f"{n_flip} air-special flips, juggle decay hooks x2, AIR BLOCK (2 forks + 2 rows + act 2D x9)")
    print(f"  bank ${0xC0 + (bankbase >> 16):02X}: {len(blob)} B "
          f"(jstub {len(jstub_e8)}, gat {len(gat_e8)}, wrap {len(wrap_e8)}, rst {len(rst_e8)}, "
          f"fork {len(fork_e8)}, react {len(react_e8)}, ablock {len(ablock_e8)}, decay {len(decay_e8)})")
    print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}  [budget N={budget}, juggle decay N={juggle}]")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="EXPERIMENT: full-roster anime-fighter PoC.")
    ap.add_argument("out")
    ap.add_argument("src", nargs="?", default=None)
    ap.add_argument("--stacked", action="store_true")
    # defaults are MAINTAINER-RULED (2026-08-20): budget 2, juggle decay 4,
    # air-enable + global rules — see docs/project/anime_fighter_feasibility.md
    ap.add_argument("--budget", type=int, default=2)
    ap.add_argument("--airdash-speed", type=lambda v: int(v, 0), default=None,
                    help="front air dash X speed (subpixels/frame, e.g. 0x0900); default keeps the Shadow Dash 0x0B00")
    ap.add_argument("--launcher-id", type=int, default=12,
                    help="attack class the universal launcher stamps (12 -> on-hit code 0x14, the pop-up row)")
    ap.add_argument("--juggle", type=int, default=4,
                    help="airborne reactions per launch sequence before untargetability returns (0 = no juggles)")
    a = ap.parse_args()
    src = a.src or clean_rom()
    require_source(src, stacked=a.stacked)
    check_not_inplace(src, a.out)
    build(src, a.out, a.budget, a.juggle, a.airdash_speed, a.launcher_id)
