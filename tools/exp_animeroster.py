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
    0x20, not 0xA0) — GLOBAL [SMS-4], the total-conversion policy;
  * the CLASH (--clash N): two hitboxes meeting inside their first N active
    frames cancel both attacks. --clash-mode backdash is the v9 answer (both
    fighters backdash); --clash-mode mash, the DEFAULT, opens the
    Samurai-Shodown MASH CONTEST on a GROUND clash — both fighters loop their
    own standing-LP animation (act 0x31, no boxes at all), each mashed press
    is counted, and after --clash-frames the higher count wins: the winner
    returns to neutral and the loser is launched with the Hercules wall-fly,
    juggle-soft, so the winner converts. A tie backdashes both. An AIR clash
    keeps the backdash on either mode (maintainer ruling 2026-08-24).

STRUCT CELLS this build claims, all measured free on both player slots by
tools/census_struct_cell.py (static, decoded) and tools/probe_exp_cells.lua
(the [SMS-33] full-session watch): +0x7B air-blockstun timer / contest timer,
+0x7C mash count (bit7 = press latch), +0x7D hitbox age, +0x7E juggle count,
+0x7F air budget. ⚠ +0x79/+0x7A is NOT free — it is a 16-bit engine counter
capped at 999 ($C0:C050), which every doc in this project still calls unmapped.

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
        cstance = word(rom, gsites[3] - 2)       # crouch stance table (act 3's ldy)
        c2hp_act = rom[C1 + cstance + 7]         # record 3 (HP), far act
        lp_act = rom[C1 + gstance + 1]           # record 1 (LP), far act — the
        # mash contest's animation. Measured 2026-08-24: 0x40 on ALL NINE (the
        # close variants differ, 0x40/0x41/0x42, which is why the FAR column is
        # the one read). Asserted rather than hardcoded — a per-character
        # constant typed into a builder is the thing this generator exists to
        # avoid.
        assert lp_act == 0x40, f"{NAMES[cid]}: standing-LP far act is {lp_act:#04x}, not 0x40"
        # ...and how long its animation runs, so the struggle can LOOP it. The
        # script is the documented byte stream (data_architecture §"Animation"):
        # d&0xC0==0 -> STEP [d][pose] for d+1 frames, 0x40 LOOP, 0x80 HOLD. All
        # nine standing jabs end in HOLD, so a loop has to be made, not found.
        sp = word(rom, word(rom, cid * 2) + lp_act * 2)
        lp_len, o = 0, C1 - C1 + sp              # scripts live in bank $C0
        while rom[o] & 0xC0 == 0:
            lp_len += rom[o] + 1
            o += 2
            assert lp_len < 200, f"{NAMES[cid]}: LP script has no terminator"
        assert rom[o] & 0xC0 in (0x40, 0x80), f"{NAMES[cid]}: bad LP script terminator"

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
            gsites=gsites, hk_act=hk_act, c2hp_act=c2hp_act,
            lp_act=lp_act, lp_len=lp_len,
            frontid=4 if has66 else 2 * ins + 2)
        if not has66:
            assert len(ents) == 2 * len(motions), \
                f"{NAMES[cid]}: {len(ents)} entries != 2x{len(motions)} motions"
    return chars


def build(src, out, budget, juggle, airdash=None, launcher_id=12, bounce=0x0700,
          fly=0x0E60, bback=0x03A0, dust=0x0C00, clash=3, clash_mode="mash",
          clash_frames=90):
    rom = bytearray(open(src, "rb").read())
    chars = derive(rom)
    STRUG_ACT = 0x31                  # the mash contest's act (null on all nine)
    mash = bool(clash) and clash_mode == "mash"
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
    c2tbl = alloc.take(20, "C2HPTBL")
    for cid in range(1, 10):
        h = word(rom, chars[cid]["tbl"] + chars[cid]["c2hp_act"] * 2)
        rom[C1 + c2tbl + cid * 2:C1 + c2tbl + cid * 2 + 2] = h.to_bytes(2, "little")
    gc2 = alloc.take(5, "gate c2hptbl"); rom[C1 + gc2:C1 + gc2 + 5] = bytes([0xFC, c2tbl & 0xFF, c2tbl >> 8, 0x6B, 0x00])
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
    LPLEN_E8 = 0x0038                 # 10 bytes: charID -> standing-LP anim length
    # The table exists only in mash mode, and the code start moves with it, so a
    # --clash-mode backdash build is byte-identical to the build before the
    # contest existed (trap 16: byte-identity is the refactor gate, and it has
    # to cover the variant paths, not just the default).
    CODE_E8 = 0x0050 if mash else 0x0040

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
    # mark in-blockstun (targetable 0x20), arm the blockstun timer, stage 0x2D.
    #
    # ⚠ THE TIMER LIVES IN +0x7B, NOT +0x79. +0x79/+0x7A is an ENGINE cell: a
    # 16-bit per-object counter capped at 999 ($C0:C050 `cmp #$03E7`), bumped at
    # every hit-resolution fork and both throw sites, re-initialised per player
    # at round load ($80:8832 / $80:897F). It reads as free in every doc
    # ("+0x79-0x7F Unmapped") and is not — measured 2026-08-24 by
    # tools/census_struct_cell.py and the [SMS-33] session watch
    # tools/probe_exp_cells.lua, which caught the engine turning a seeded $A5
    # into $A6 mid-match. +0x7B is free by both measurements.
    ABLOCK_FRAMES = 14
    react_items = [
        [0xC2, 0x30], [0xA6, 0x88], [0xE2, 0x20],
        [0xA9, 0x20], [0x95, 0x46],
        [0xA9, ABLOCK_FRAMES], [0x95, 0x7B],
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
        [0xD6, 0x7B],                          # dec $7B,X (blockstun timer)
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
        ("b", 0xF0, "herc"),
        [0xC9, 0xC0],                                       # fresh HP+HK exactly
        ("b", 0xD0, "van"),
        [0xB5, 0x01], [0xC9, 0x03],                         # DUST: from crouch only
        ("b", 0xD0, "van"),
        [0xA9, 0x30], jsl(g0224, 0xC1),
        [0xC2, 0x10], [0xA6, 0x88], [0x6B],
        ("label", "herc"),
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
        # the fresh vanilla pop-up is act 0x1A OR 0x1B — 0x1A appears only
        # when the victim's first-hit-defense absorbs (Jupiter/Neptune); the
        # rest of the roster stages 0x1B (measured on Chibi: field bug, the
        # 0x1A-only edge never converted her)
        [0xB5, 0x01], [0xC9, 0x1A],
        ("b", 0xF0, "doconv"),
        [0xC9, 0x1B],
        ("b", 0xD0, "conv_done"),
        ("label", "doconv"),
        [0xA9, 0x2F], [0x95, 0x01], [0x95, 0x04],
        [0x74, 0x02], [0x74, 0x07], [0x74, 0x06],
        [0xC2, 0x20],
        [0xB5, 0x30],                          # the stage's away-sign
        ("b", 0x10, "flyr"),
        [0xA9, (-fly) & 0xFF, ((-fly) >> 8) & 0xFF],   # vx = -fly
        ("b", 0x80, "flyw"),
        ("label", "flyr"),
        [0xA9, fly & 0xFF, (fly >> 8) & 0xFF],         # vx = +fly
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
    # DUST (act 0x30): the char's own CROUCHING HP, launcher class, and the
    # victim conversion goes VERTICAL — keep the reaction's own (small)
    # horizontal knockback and gravity, override only vy: a Guilty-Gear Dust
    # that carries the victim to the top of the screen, in air hitstun
    # (juggle-soft, lands like any juggle).
    dust_items = [
        [0xC2, 0x30], [0xA6, 0x88], [0xE2, 0x20],
        [0xB5, 0x00], [0xC2, 0x20], [0x29, 0xFF, 0x00], [0x0A], [0xAA],
        jsl(gc2, 0xC1),
        [0xC2, 0x10], [0xA6, 0x88], [0xE2, 0x20],
        [0xA9, launcher_id], [0x95, 0x44],
        [0xB5, 0x43],
        ("b", 0xF0, "nosoft"),
        [0xC2, 0x30], [0x8A],
        [0x49, 0x80, 0x00], [0xAA],
        [0xE2, 0x20],
        [0xA9, 0x20], [0x95, 0x46],
        [0xB5, 0x01], [0xC9, 0x1A],
        ("b", 0xF0, "doconv"),
        [0xC9, 0x1B],
        ("b", 0xD0, "conv_done"),
        ("label", "doconv"),
        [0xA9, 0x16], [0x95, 0x01], [0x95, 0x04],          # air hitstun, straight up
        [0x74, 0x02], [0x74, 0x07], [0x74, 0x06],
        [0xC2, 0x20],
        [0xA9, (-dust) & 0xFF, ((-dust) >> 8) & 0xFF], [0x95, 0x32],   # vy = -dust
        [0xE2, 0x20],
        ("label", "conv_done"),
        [0xC2, 0x30], [0xA6, 0x88],
        ("label", "nosoft"),
        [0x6B],
    ]
    DUST = LAUNCH + len(launch_e8)
    dust_e8 = asm(DUST, dust_items)
    # ---- CLASH ---------------------------------------------------------
    # AGE: the box writer's per-object batch ($C0:9CC0-9CDE) writes +0x40/41/42
    # every frame for every object. Hooking its last pair gives a free
    # per-object per-frame tick: +0x7D = frames this hitbox has been active
    # (0 when there is no hitbox), which is what "first N active frames" needs.
    age_items = [
        [0xB1, 0x10], [0x95, 0x42],            # replayed: lda ($10),Y / sta $42,X
        [0xB5, 0x40],                          # hitbox index
        ("b", 0xF0, "clr"),
        [0xB5, 0x7D], [0xC9, 0x0F],
        ("b", 0xB0, "done"),                   # cap, no wrap
        [0xF6, 0x7D],
        ("b", 0x80, "done"),
        ("label", "clr"),
        [0x74, 0x7D],
        ("label", "done"),
        [0x6B],
    ]
    AGE = DUST + len(dust_e8)
    age_e8 = asm(AGE, age_items)

    def clash_one(sfx):
        return [
            [0xB5, 0x16], [0x29, 0x80],        # grounded?
            ("b", 0xF0, f"air{sfx}"),
            [0xA9, 0x26], ("b", 0x80, f"set{sfx}"),
            ("label", f"air{sfx}"), [0xA9, 0x2B],   # airborne clash -> air backdash
            ("label", f"set{sfx}"),
            [0x95, 0x01], [0x95, 0x04],        # act + anim act
            [0x74, 0x02], [0x74, 0x06], [0x74, 0x07],
            [0x74, 0x40], [0x74, 0x41],        # no boxes for the rest of THIS frame
            [0x74, 0x43], [0x74, 0x7D],        # clear connect latch + age
        ]

    def strug_one():
        """Put the fighter in X into the MASH CONTEST (act 0x31)."""
        return [
            [0xA9, STRUG_ACT], [0x95, 0x01], [0x95, 0x04],
            [0x74, 0x02], [0x74, 0x06], [0x74, 0x07],   # step + anim, from zero
            [0x74, 0x40], [0x74, 0x41],                 # no boxes for the rest of THIS frame
            [0x74, 0x43], [0x74, 0x7D],                 # connect latch + hitbox age
            [0x74, 0x7C],                               # the mash count
            [0xA9, clash_frames], [0x95, 0x7B],         # the contest timer
            [0xC2, 0x20], [0x74, 0x30], [0x74, 0x32], [0xE2, 0x20],   # stop dead
        ]

    # CLASH: replaces the target-selection block at $C0:BFF5-C001, entered with
    # the ATTACKER's hit rect already computed in DP $00-$06 by $C0:C8EA and
    # X = attacker base. If the opponent is ALSO attacking, both hitboxes are
    # within their first `clash` active frames, and the two HITBOXES overlap
    # (the engine's own box-vs-rect test $C0:C9DF, reached through a gate
    # written into the same carved bytes), neither hit resolves: both fighters
    # are set to their backdash act. Otherwise the original target selection is
    # reproduced exactly (incl. the non-player case: anything but P1 -> P1).
    #
    # ⚠ NO PROJECTILE MAY EVER TAKE PART IN A CLASH (maintainer, 2026-08-25),
    # and two properties of this block are what enforce it. Keep both if you
    # touch it:
    #   * the two `cpx` tests below admit ONLY $1000 and $1080 — a projectile
    #     attacker ($1100/$1180, and any other object) falls straight through
    #     to the vanilla target selection, so a fireball's own resolution never
    #     reaches the test;
    #   * the opposing side is derived as `base XOR $80`, which is always the
    #     other PLAYER slot. Widening that to "whatever object is attacking"
    #     would put a fireball on the other side of the test.
    # Measured both ways on 2026-08-25 (`tools/probe_exp_projclash.lua`): a
    # ball meeting a live body hitbox, and two balls meeting each other, both
    # resolve exactly as they do on the clean ROM.
    clash_items = [
        [0xE0, 0x00, 0x10], ("b", 0xF0, "atk_ok"),
        [0xE0, 0x80, 0x10], ("b", 0xD0, "targ_p1"),
        ("label", "atk_ok"),
        [0xDA],                                # phx (attacker base)
        [0xE2, 0x20],
        [0xB5, 0x7D], [0xC9, clash + 1], ("b", 0xB0, "bail"),
        [0xC2, 0x30],
        [0x8A], [0x49, 0x80, 0x00], [0xAA],    # X = the other player
        [0xE2, 0x20],
        [0xB5, 0x40], ("b", 0xF0, "bail"),     # opponent not attacking
        [0xB5, 0x7D], [0xC9, clash + 1], ("b", 0xB0, "bail"),
        [0xC2, 0x30],
        [0xB5, 0x00], [0x29, 0xFF, 0x00], [0x0A], [0xA8],
        [0xB9, 0xF1, 0xC1], [0x85, 0x20],      # their hit table (DB=$8A)
        [0xB5, 0x40], [0x29, 0xFF, 0x00], [0x0A], [0x0A], [0x0A],
        [0x18], [0x65, 0x20], [0x85, 0x20],    # + idx*8 = their hit record
        [0x22, 0xFB, 0xBF, 0xC0],              # jsl $C0:BFFB — the carved gate
        ("b", 0x90, "bail"),                   # no overlap -> ordinary resolution
        ("b", 0x80, "do_clash"),
        ("label", "bail"),
        [0xC2, 0x30], [0xFA],                  # rep #$30 / plx
        [0xE0, 0x00, 0x10], ("b", 0xD0, "targ_p1"),
        [0xA2, 0x80, 0x10], [0x6B],
        ("label", "targ_p1"),
        [0xA2, 0x00, 0x10], [0x6B],
        ("label", "do_clash"),
        [0xE2, 0x20],
    ] + (clash_one("O") + [
        [0xC2, 0x30], [0xFA], [0xE2, 0x20],    # plx -> attacker base
    ] + clash_one("A") if clash_mode == "backdash" else [
        # MASH CONTEST — but only if BOTH fighters are grounded (maintainer
        # ruling 2026-08-24: an air clash keeps the instant backdash; a struggle
        # while both fall reads wrong, and the loser's wall-fly punish makes no
        # sense out of the air). Reading both grounded bits needs one byte of
        # scratch, and the stack is the only scratch a resolution hook owns.
        [0xC2, 0x30], [0xFA], [0xE2, 0x20],    # plx -> attacker base
        [0xB5, 0x16], [0x48],                  # lda $16,X / pha  (attacker's flags)
        [0xC2, 0x30], [0x8A], [0x49, 0x80, 0x00], [0xAA], [0xE2, 0x20],
        [0x68],                                # pla -> attacker's flags
        [0x35, 0x16], [0x29, 0x80],            # and $16,X / and #$80: BOTH grounded?
        ("b", 0xF0, "bdpair"),
    ] + strug_one() + [                        # X = opponent
        [0xC2, 0x30], [0x8A], [0x49, 0x80, 0x00], [0xAA], [0xE2, 0x20],
    ] + strug_one() + [                        # X = attacker
        ("b", 0x80, "cfin"),
        ("label", "bdpair"),                   # someone airborne -> the v9 pair
    ] + clash_one("O") + [
        [0xC2, 0x30], [0x8A], [0x49, 0x80, 0x00], [0xAA], [0xE2, 0x20],
    ] + clash_one("A")) + [
        ("label", "cfin"),
        [0xA9, 0x0B], [0x85, 0x78],            # the guard sfx request (global DP)
        [0xC2, 0x30],
        [0x8A], [0x49, 0x80, 0x00], [0xAA],    # X = opponent (the caller's target)
        [0x6B],
    ]
    CLASH = AGE + len(age_e8)
    clash_e8 = asm(CLASH, clash_items)
    # WALLFLY (act 0x2F, all nine): fly until the victim touches the border
    # of the CURRENTLY DRAWN screen — read from the engine's own per-object
    # screen X at +0x28 (world - camera + 0x2C, computed by $C0:8BCB every
    # frame; +0x16 bit6 is set at the clamp instant and is the trigger). A
    # world-position stall check would instead let the victim DRAG THE
    # CAMERA until it is clamped by the launcher's position (the field
    # report's bug), and a fixed screen-x threshold misses the engine's own
    # clamp value (232, measured). Then BOUNCE: reversed X, upward impulse, real
    # gravity, air hitstun act 0x16 (juggle-soft, lands like any juggle).
    # Step doubles as a timeout.
    wallfly_items = [
        [0xC2, 0x30], [0xA6, 0x88], [0xE2, 0x20],
        [0xF6, 0x02],                          # step = frame counter
        [0xB5, 0x02], [0xC9, 70], ("b", 0xB0, "bail"),
        [0xC9, 0x04], ("b", 0x90, "tail2"),    # let the flight start first
        # the drawn border: the engine CLAMPS the object at the screen edge
        # (measured: screen x pins at 232 and the victim then pushes the
        # camera 1 px/f — the reported drag) and SETS +0x16 bit6 at the exact
        # clamp instant. Bit6 is the native, side-agnostic signal.
        [0xB5, 0x16], [0x29, 0x40],
        ("b", 0xF0, "tail2"),                  # not touching the border yet
        # the border: reverse X (sign from current), pop up, real gravity
        [0xC2, 0x20],
        [0xB5, 0x30],
        ("b", 0x10, "toleft"),
        [0xA9, bback & 0xFF, (bback >> 8) & 0xFF],           # flying left -> bounce right
        ("b", 0x80, "bset"),
        ("label", "toleft"),
        [0xA9, (-bback) & 0xFF, ((-bback) >> 8) & 0xFF],     # flying right -> bounce left
        ("label", "bset"),
        [0x95, 0x30],
        [0xA9, (-bounce) & 0xFF, ((-bounce) >> 8) & 0xFF], [0x95, 0x32],   # vy = -bounce
        [0xA9, 0x60, 0x00], [0x95, 0x34],      # gravity 0x60
        [0xE2, 0x20],
        ("label", "bail"),
        [0xA9, 0x16], jsl(g0224, 0xC1),        # air hitstun: the juggle state
        ("label", "tail2"),
        [0xC2, 0x10], [0xA6, 0x88],
        jsl(g0204, 0xC1),
        [0x6B],
    ]
    WALLFLY = CLASH + len(clash_e8)
    wallfly_e8 = asm(WALLFLY, wallfly_items)

    # ---- THE MASH CONTEST (act 0x31) ------------------------------------
    # A ground clash opens a Samurai-Shodown struggle: both fighters loop their
    # OWN standing-LP animation with no boxes at all, both mash, the higher
    # count wins, the loser is launched with the Hercules wall-fly (juggle-soft,
    # so the winner converts) and a tie falls back to the v9 mutual backdash.
    #
    # Three small routines, because the outcome blocks would otherwise branch
    # further than a relative branch reaches:
    #   STAGE  (A = act, X = object)  the common act change + counter reset
    #   LOSE   (X = loser)            STAGE 0x2F + juggle-soft + the flight
    #   STRUG                         the per-frame handler itself
    stage_items = [
        [0x95, 0x01], [0x95, 0x04],            # act + anim act
        [0x74, 0x02], [0x74, 0x06], [0x74, 0x07],
        [0x74, 0x7C], [0x74, 0x7B],            # mash count + contest timer
        [0x60],
    ]
    STAGE = WALLFLY + len(wallfly_e8)
    stage_e8 = asm(STAGE, stage_items)

    def call(a):
        return [0x20, a & 0xFF, a >> 8]        # jsr, in-bank (PB = the appended bank)

    lose_items = [
        [0xA9, 0x2F], call(STAGE),             # the wall-fly act
        [0xA9, 0x20], [0x95, 0x46],            # juggle-soft: the winner converts
        [0x74, 0x7E],                          # ...with a full juggle allowance
        [0xB5, 0x16], [0x29, 0x7F], [0x95, 0x16],   # airborne, or the flight never leaves the floor
        # AWAY from the winner, and the two fighters face each other in a clash,
        # so "away" is the loser's own back. +0x09 == 0 is facing RIGHT (the
        # training mode's pixel-verified box viewer reads it that way).
        [0xB5, 0x09],
        ("b", 0xF0, "toleft"),
        [0xC2, 0x20], [0xA9, fly & 0xFF, fly >> 8],
        ("b", 0x80, "setvx"),
        ("label", "toleft"),
        [0xC2, 0x20], [0xA9, (-fly) & 0xFF, ((-fly) >> 8) & 0xFF],
        ("label", "setvx"),
        [0x95, 0x30],
        [0xA9, 0x80, 0xFE], [0x95, 0x32],      # vy = -0x0180 (the shallow lift)
        [0xA9, 0x10, 0x00], [0x95, 0x34],      # gravity 0x0010 (near-flat)
        [0xE2, 0x20],
        [0x60],
    ]
    LOSE = STAGE + len(stage_e8)
    lose_e8 = asm(LOSE, lose_items)

    def swapx():
        """X = the other player slot (the two structs are 0x80 apart)."""
        return [[0xC2, 0x30], [0x8A], [0x49, 0x80, 0x00], [0xAA], [0xE2, 0x20]]

    strug_items = [
        [0xC2, 0x30], [0xA6, 0x88], [0xE2, 0x20],
        # No boxes, ever. The handler runs AFTER the box writer's per-object
        # batch ($C0:9CCD), so zeroing here is exact — and an empty hurtbox is
        # the engine's own invulnerability, which is what keeps a stray
        # projectile out of the contest.
        [0x74, 0x40], [0x74, 0x41],
        # Count PRESS EDGES, not latched frames: +0x50's high nibble is the
        # fresh-attack latch the throw-tech sampler reads ($C1:07CF) and it
        # stands for ~2 frames at 30Hz, so counting frames would pay a mash and
        # a hold alike. Bit7 of +0x7C is "this press is already counted", which
        # keeps the whole contest in ONE struct cell.
        [0xB5, 0x50], [0x29, 0xF0],
        ("b", 0xF0, "noedge"),
        [0xB5, 0x7C],
        ("b", 0x30, "anim"),                   # bmi: still holding the same press
        [0xC9, 0x7F], ("b", 0xB0, "latch"),    # saturate at 127
        [0x1A],                                # inc a
        ("label", "latch"),
        [0x09, 0x80], [0x95, 0x7C],
        ("b", 0x80, "anim"),
        ("label", "noedge"),
        [0xB5, 0x7C], [0x29, 0x7F], [0x95, 0x7C],
        # Loop the jab. Every standing-LP script ends in HOLD (0x80), so the
        # loop has to be made: at the cycle boundary zero the STEP, and the
        # handler tail ($C1:0204) rewinds the animation — it fires precisely
        # when the step is 0. The cycle length is the character's own, summed
        # from its script at build time (7 frames; Jupiter 9).
        ("label", "anim"),
        [0xB5, 0x00],                          # charID
        [0xC2, 0x30], [0x29, 0xFF, 0x00], [0xAA], [0xE2, 0x20],
        [0xBF, LPLEN_E8 & 0xFF, LPLEN_E8 >> 8, eb],
        [0x48],                                # pha (the cycle length)
        [0xA6, 0x88],                          # X = object again
        [0xF6, 0x02],
        [0xB5, 0x02],
        [0xC3, 0x01],                          # cmp $01,S
        ("b", 0x90, "nowrap"),
        [0x74, 0x02],
        ("label", "nowrap"),
        [0x68],
        # the contest's own clock
        [0xD6, 0x7B],
        ("b", 0xD0, "tail"),
        # --- resolution: higher count wins ---------------------------------
        # Both timers were armed on the same frame, so they expire together and
        # whichever proc runs first resolves for BOTH fighters.
        [0xB5, 0x7C], [0x29, 0x7F], [0x48],    # push SELF's count
    ] + swapx() + [                            # X = the other fighter
        [0xB5, 0x7C], [0x29, 0x7F],
        [0xC3, 0x01],                          # cmp $01,S  (other - self)
        ("b", 0xD0, "notie"),
        [0x68],
        [0xA9, 0x26], call(STAGE),             # TIE -> both backdash (the v9 answer)
    ] + swapx() + [
        [0xA9, 0x26], call(STAGE),
        ("b", 0x80, "tail"),
        ("label", "notie"),
        ("b", 0xB0, "otherwins"),
        [0x68],
        call(LOSE),                            # other < self: the other one flies
    ] + swapx() + [
        [0xA9, 0x00], call(STAGE),             # ...and self returns to neutral
        ("b", 0x80, "tail"),
        ("label", "otherwins"),
        [0x68],
        [0xA9, 0x00], call(STAGE),
    ] + swapx() + [
        call(LOSE),
        ("label", "tail"),
        [0xC2, 0x10], [0xA6, 0x88],            # the X-restore law, every exit
        jsl(g0204, 0xC1),
        [0x6B],
    ]
    STRUG = LOSE + len(lose_e8)
    strug_e8 = asm(STRUG, strug_items)
    if not mash:                       # backdash mode emits none of it (see CODE_E8)
        stage_e8 = lose_e8 = strug_e8 = b""

    blob = bytearray(0x10000)
    for cid in range(1, 10):
        blob[FRONTID_E8 + cid] = chars[cid]["frontid"]
        blob[NTBL_E8 + cid * 2:NTBL_E8 + cid * 2 + 2] = chars[cid]["stance"][7].to_bytes(2, "little")
        blob[SPTBL_E8 + cid * 2:SPTBL_E8 + cid * 2 + 2] = chars[cid]["sptbl"].to_bytes(2, "little")
        if mash:
            blob[LPLEN_E8 + cid] = chars[cid]["lp_len"]
    code = (jstub_e8 + gat_e8 + wrap_e8 + rst_e8 + fork_e8 + react_e8 + ablock_e8
            + decay_e8 + gstub_e8 + launch_e8 + dust_e8 + age_e8 + clash_e8
            + wallfly_e8 + stage_e8 + lose_e8 + strug_e8)
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
    dustshim = alloc.take(5, "dust act shim")
    rom[C1 + dustshim:C1 + dustshim + 5] = bytes(jsl(DUST)) + b"\x60"
    if mash:
        strugshim = alloc.take(5, "struggle act shim")
        rom[C1 + strugshim:C1 + strugshim + 5] = bytes(jsl(STRUG)) + b"\x60"

    # ---- AIR BLOCK global wiring --------------------------------------
    # the two resolution fork sites ($C0:C06A / $C0:C13D, running from the
    # $80 mirror): 6-byte test -> jsl fork-stub + 2 nops; branch untouched
    for off in (0x00C06A, 0x00C13D):
        if rom[off:off + 6] != bytes([0xA5, 0x08, 0x29, 0x03, 0x25, 0x0A]):
            raise ValueError(f"0x{off:06X}: block-fork test bytes not found")
        rom[off:off + 6] = bytes(jsl(FORK)) + bytes([0xEA, 0xEA])
    if clash:
        # the box writer's per-frame tail -> the age tick (4 bytes replayed)
        if rom[0x009CCF:0x009CD3] != bytes([0xB1, 0x10, 0x95, 0x42]):
            raise ValueError("0x009CCF: box-writer tail bytes not found")
        rom[0x009CCF:0x009CD3] = bytes(jsl(AGE))
        # the resolution's target-selection block -> the clash test, with the
        # $C9DF gate written into the same carved bytes (see clash_items)
        want = bytes([0xE0, 0x00, 0x10, 0xD0, 0x05, 0xA2, 0x80, 0x10,
                      0x80, 0x03, 0xA2, 0x00, 0x10])
        if rom[0x00BFF5:0x00C002] != want:
            raise ValueError("0x00BFF5: resolution target-selection bytes not found")
        rom[0x00BFF5:0x00C002] = (bytes(jsl(CLASH)) + bytes([0x80, 0x07])
                                  + bytes([0x20, 0xDF, 0xC9, 0x6B])
                                  + bytes([0xEA, 0xEA, 0xEA]))
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
        slot30 = c["tbl"] + 0x30 * 2
        assert rom[slot30:slot30 + 2] == b"\0\0", f"{nm}: act slot 30 not null"
        rom[slot30:slot30 + 2] = dustshim.to_bytes(2, "little")
        if mash:
            slot31 = c["tbl"] + STRUG_ACT * 2
            assert rom[slot31:slot31 + 2] == b"\0\0", f"{nm}: act slot 31 not null"
            rom[slot31:slot31 + 2] = strugshim.to_bytes(2, "little")
        # script slots 2B (jump-back, 8) / 2C (jump-fwd, 7) / 2D (guard pose, 0x0C)
        st = c["scripttbl"]
        slots = [(0x2B, 8), (0x2C, 7), (0x2D, 0x0C), (0x2E, c["hk_act"]),
                 (0x2F, 0x1A), (0x30, c["c2hp_act"])]
        if mash:
            slots.append((STRUG_ACT, c["lp_act"]))   # the struggle wears the jab
        for slot, src_slot in slots:
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
    if mash:
        print(f"  MASH CONTEST: act ${STRUG_ACT:02X} x9 (anim = each char's own standing LP, "
              f"{clash_frames}f, window {clash}f), stage {len(stage_e8)} B, lose {len(lose_e8)} B, "
              f"strug {len(strug_e8)} B")
    print(f"  bank ${0xC0 + (bankbase >> 16):02X}: {len(blob)} B "
          f"(jstub {len(jstub_e8)}, gat {len(gat_e8)}, wrap {len(wrap_e8)}, rst {len(rst_e8)}, "
          f"fork {len(fork_e8)}, react {len(react_e8)}, ablock {len(ablock_e8)}, decay {len(decay_e8)})")
    print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}  [budget N={budget}, juggle decay N={juggle}, bounce 0x{bounce:04X}, fly 0x{fly:04X}, bback 0x{bback:04X}, clash {clash}]")


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
    ap.add_argument("--clash", type=int, default=3,
                    help="clash window: hitboxes meeting within N active frames cancel both (0 = off)")
    ap.add_argument("--clash-mode", choices=("mash", "backdash"), default="mash",
                    help="what a GROUND clash does: mash = the Samurai-Shodown contest "
                         "(default, maintainer 2026-08-24), backdash = the v9 instant mutual "
                         "backdash. Air clashes always backdash.")
    ap.add_argument("--clash-frames", type=int, default=90,
                    help="how long the mash contest runs, in frames (~1.5 s at 60)")
    ap.add_argument("--dust-height", type=lambda v: int(v, 0), default=0x0C00,
                    help="crouching-Dust vertical impulse (subpixels/frame; ~192px rise at 0x0C00)")
    ap.add_argument("--fly-speed", type=lambda v: int(v, 0), default=0x0E60,
                    help="launcher horizontal flight speed (was 0x0C00; default +20%%)")
    ap.add_argument("--bounce-back", type=lambda v: int(v, 0), default=0x03A0,
                    help="bounce return horizontal speed (was 0x0480; default -20%%)")
    ap.add_argument("--bounce-height", type=lambda v: int(v, 0), default=0x0700,
                    help="wall-bounce vertical impulse (subpixels/frame; was 0x0500, default 0x0700)")
    ap.add_argument("--launcher-id", type=int, default=12,
                    help="attack class the universal launcher stamps (12 -> on-hit code 0x14, the pop-up row)")
    ap.add_argument("--juggle", type=int, default=4,
                    help="airborne reactions per launch sequence before untargetability returns (0 = no juggles)")
    a = ap.parse_args()
    src = a.src or clean_rom()
    require_source(src, stacked=a.stacked)
    check_not_inplace(src, a.out)
    if not 1 <= a.clash_frames <= 255:
        ap.error("--clash-frames must fit in the one-byte timer (1-255)")
    build(src, a.out, a.budget, a.juggle, a.airdash_speed, a.launcher_id, a.bounce_height,
          a.fly_speed, a.bounce_back, a.dust_height, a.clash, a.clash_mode, a.clash_frames)
