#!/usr/bin/env python3
"""port_saturn_proc.py — port Sailor Saturn's per-char proc block (Super S
$C1:C6F7..) into SMS coordinates, by recursive-descent disassembly + operand fixup.

The block is grafted (by mksaturn_smoke.py) into an appended SMS bank that holds a
full copy of SMS bank $C1, at its original in-bank offsets — so INTERNAL absolute
refs (act jump table $C706, intra-block jsr/jmp) stay verbatim, and EXTERNAL
bank-local refs must be rewritten from Super S offsets to SMS offsets (the two
banks' engine routines are identical code at slightly shifted addresses; map
verified per-target by byte/skeleton signature match, docs/project/saturn/supers_map.md
§per-char proc blocks).

Recursive descent starts at the dispatch entry + all act-table targets, tracks
M/X via REP/SEP (entry M=1,X=1 per the sep #$30 at the dispatch site), follows
branches/jsr/jmp fallthrough within the block, and only patches operands of
REACHED instructions — data pockets between procs are preserved byte-exact.

Outputs (as a library for mksaturn_smoke; runnable standalone for the report):
  patched_block() -> (bytes, report dict)
"""
import sys
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "tools"))

BANK = 0x010000                  # file base of bank $C1 (both games)
BLOCK_LO, BLOCK_HI = 0xC6F7, 0xDC00   # generous block window (in-bank)
DISPATCH = 0xC6F7
ACT_TABLE = 0xC706
N_ACTS = 128

# ---- 65816 decode tables: shared, see tools/dis65816.py ----
# These lived here as five hand-written sets until 2026-08-10, and two of them
# were WRONG: `00` (BRK) was listed as 1 byte when it carries a signature byte
# and is 2, and `02 08 0B 2B 42 C4 E4` (COP PHP PHD PLD WDM CPY-dp CPX-dp) were
# in no table at all, so a descent meeting a `php` died on "unknown opcode".
# Saturn's block reaches none of the eight — measured, and that is why the port
# was never affected — but the tables are shared now and validated against an
# independent disassembler (tools/dis65816_oracle.py).
from dis65816 import IMM_M, IMM_X, BRANCH, length as _oplen

# ---- external target map: Super S bank-$C1 offset -> SMS bank-$C1 offset ----
# Built by signature match (exact or skeleton at regional delta), verified
# 2026-07-30. Regional deltas: -2 (< $0700), -25 ($0960-$0A9D), -5 ($0AAE-$1141).
EXT_MAP = {
    0x0138: 0x0136, 0x0155: 0x0153, 0x0200: 0x01FE, 0x0206: 0x0204, 0x0226: 0x0224,
    0x024D: 0x024B, 0x0231: 0x022F,
    0x02E1: 0x02DF, 0x02F5: 0x02F3, 0x0309: 0x0307, 0x0313: 0x0311, 0x0321: 0x031F,
    0x0338: 0x0336, 0x034A: 0x0348, 0x035E: 0x035C, 0x0370: 0x036E, 0x038B: 0x0389,
    0x03A6: 0x03A4, 0x03B4: 0x03B2, 0x03DE: 0x03DC, 0x03ED: 0x03EB, 0x0418: 0x0416,
    0x044D: 0x044B, 0x045B: 0x0459, 0x04DC: 0x04DA, 0x0503: 0x0501, 0x051C: 0x051A,
    0x052A: 0x0528, 0x0538: 0x0536, 0x055C: 0x055A, 0x06E7: 0x06E5, 0x096B: 0x0952,
    0x0971: 0x0958, 0x09EC: 0x09D3, 0x09FA: 0x09E1, 0x0A08: 0x09EF, 0x0A22: 0x0A09,
    0x0A4C: 0x0A33, 0x0A9D: 0x0A84, 0x0AAE: 0x0AA9, 0x0ABE: 0x0AB9, 0x0B0A: 0x0B05,
    0x0B4E: 0x0B49, 0x0C14: 0x0C0F, 0x10BB: 0x10B6, 0x1141: 0x113C,
}
# long-call targets (bank $80): mapped separately by the caller (verified sigs)
JSL_MAP = {}   # filled by resolve_jsl_map()


def resolve_jsl_map(sup, sms):
    """The block's two JSL targets, mapped + verified 2026-07-30:
    $80:C115 -> $80:BFBB — the box-data helper (char-proc flavor; 218 SuperS /
      192 SMS call sites in the char-proc regions; 96-byte compare differs only
      in operands incl. the box bank lda #$AF -> #$8A).
    $80:FBB0 -> $80:9FB7 (bare RTL) — FBB0 springboards to $FBB4, the Super S
      sound/command handler with NO SMS twin (the CMD extension). Stubbed to a
      bare RTL here; SMS's real sfx API was mapped in v0.7.0 and her commands are
      re-pointed to the $EF:DB50 translator (see SND_MAP in mksaturn_smoke.py),
      with her own voice added in v0.13.0. The remaining id->sfx mapping is
      approximate — parked, not open: docs/project/saturn/PROJECT.md "Parked"."""
    if not (sup[0xC115:0xC115 + 11] == sms[0xBFBB:0xBFBB + 11]):
        raise ValueError("C115/BFBB drift")
    if not (sup[0xC494:0xC494 + 11] == sms[0xC352:0xC352 + 11]):
        raise ValueError("C494/C352 drift")
    if not (sms[0x9FB7] == 0x6B):
        raise ValueError(f"$80:9FB7 is not RTL (got {sms[0x9FB7]:#04x})")
    return {0x80C115: 0x80BFBB, 0x80FBB0: 0x809FB7,
            0x80C494: 0x80C352}   # projectile-flavor box helper (verified twin)


def disassemble(sup, block_lo=BLOCK_LO, block_hi=BLOCK_HI, entries=None):
    """Recursive descent over a block. Returns {addr: (op, length)} of reached
    instructions, with per-address M/X states validated for consistency.
    entries: list of in-bank start addresses (default: the char-proc dispatch +
    act table). Any `jmp/jsr (abs,X)` table INSIDE the block is auto-walked:
    its word entries that land in-block are pushed as code."""
    code = {}
    flags = {}
    work = []

    def push(addr, m, x):
        if not (block_lo <= addr < block_hi):
            return
        if addr in flags:
            if flags[addr] != (m, x):
                pm, px = flags[addr]
                # only immediate sizes depend on flags; conflicting joins are an
                # error unless the instruction is flag-independent — check lazily
                op = sup[BANK + addr]
                if op in IMM_M and m != pm or op in IMM_X and x != px:
                    raise SystemExit(f"error: M/X conflict at {addr:04X}")
            return
        flags[addr] = (m, x)
        work.append((addr, m, x))

    # entries: dispatch runs with sep #$30 (M=1, X=1) from the main-loop hook
    tables = set()
    if entries is None:
        push(DISPATCH, 1, 1)
        tables.add(ACT_TABLE)
        for i in range(N_ACTS):
            w = sup[BANK + ACT_TABLE + 2 * i] | sup[BANK + ACT_TABLE + 2 * i + 1] << 8
            if w:
                push(w, 1, 1)      # dispatch does not change flags before jmp
    else:
        for e in entries:
            push(e, 1, 1)

    while work:
        addr, m, x = work.pop()
        while True:
            if not (block_lo <= addr < block_hi):
                break
            if addr in code:
                break
            op = sup[BANK + addr]
            ln = _oplen(op, m, x)
            if ln is None:                # cannot happen: the table is complete
                raise SystemExit(f"error: unknown opcode {op:02X} at {addr:04X}")
            code[addr] = (op, ln)
            flags[addr] = (m, x)
            if op == 0xC2:          # rep
                v = sup[BANK + addr + 1]
                if v & 0x20: m = 0
                if v & 0x10: x = 0
            elif op == 0xE2:        # sep
                v = sup[BANK + addr + 1]
                if v & 0x20: m = 1
                if v & 0x10: x = 1
            if op in (0x7C, 0xFC):     # (abs,X) table inside the block: walk it
                tbl = sup[BANK + addr + 1] | sup[BANK + addr + 2] << 8
                if block_lo <= tbl < block_hi and tbl not in tables:
                    tables.add(tbl)
                    for i in range(64):
                        w = sup[BANK + tbl + 2 * i] | sup[BANK + tbl + 2 * i + 1] << 8
                        if not (block_lo <= w < block_hi):
                            break
                        push(w, m, x)
            if op in BRANCH:
                off = sup[BANK + addr + 1]
                if off > 127: off -= 256
                push(addr + 2 + off, m, x)
                if op == 0x80:      # bra: no fallthrough
                    break
            elif op == 0x82:        # brl
                off = sup[BANK + addr + 1] | sup[BANK + addr + 2] << 8
                if off > 32767: off -= 65536
                push(addr + 3 + off, m, x)
                break
            elif op in (0x20, 0x4C):
                t = sup[BANK + addr + 1] | sup[BANK + addr + 2] << 8
                if block_lo <= t < block_hi:
                    push(t, m, x)
                if op == 0x4C:
                    break
            elif op in (0x60, 0x6B, 0x40):
                break
            elif op in (0x5C, 0x6C, 0x7C, 0xDC):
                break
            # 0xFC jsr (abs,X): the dispatched handler RETURNS (via the common
            # tails' rts), so the continuation at +3 is live code — falling
            # through. (v0.11.1 fix: treating it as a stop left the id-0x21
            # projectile's post-dispatch `jmp $024D` unreached and UNFIXED ->
            # entered the SMS twin 2 bytes late, skipping its rep #$30 -> the
            # 16-bit cmp misdecoded as cmp+BRK -> the j.632K black-screen.)
            addr += ln
    return code


def patched_block(sup, sms, block_lo=BLOCK_LO, block_hi=BLOCK_HI, entries=None):
    """Return (block bytes with operands fixed, report)."""
    global JSL_MAP
    JSL_MAP = resolve_jsl_map(sup, sms)
    code = disassemble(sup, block_lo, block_hi, entries)
    out = bytearray(sup[BANK + block_lo:BANK + block_hi])
    fixed, internal, data_refs, unresolved = [], 0, [], []
    for addr in sorted(code):
        op, ln = code[addr]
        o = addr - block_lo
        if op in (0x20, 0x4C):
            t = out[o + 1] | out[o + 2] << 8
            if block_lo <= t < block_hi:
                internal += 1
                continue
            if t in EXT_MAP:
                s = EXT_MAP[t]
                out[o + 1] = s & 0xFF
                out[o + 2] = s >> 8
                fixed.append((addr, t, s))
            else:
                unresolved.append((addr, op, t))
        elif op == 0x22:
            t = out[o + 1] | out[o + 2] << 8 | out[o + 3] << 16
            if t in JSL_MAP:
                s = JSL_MAP[t]
                out[o + 1] = s & 0xFF
                out[o + 2] = (s >> 8) & 0xFF
                out[o + 3] = s >> 16
                fixed.append((addr, t, s))
            else:
                unresolved.append((addr, op, t))
        elif op in (0xAD, 0x8D, 0xBD, 0x9D, 0xB9, 0x99, 0xAE, 0x8E, 0xAC, 0x8C,
                    0xBC, 0xBE, 0x0D, 0x2D, 0x4D, 0x6D, 0xCD, 0xED, 0x1D, 0x3D,
                    0x5D, 0x7D, 0xDD, 0xD9, 0x39, 0x19, 0x59, 0x79, 0x0E, 0x2E,
                    0x4E, 0x6E, 0xCE, 0xEE, 0xFE, 0xDE, 0x1E, 0x3E, 0x5E, 0x7E,
                    0x9C, 0x1C, 0x0C, 0x2C):
            t = out[o + 1] | out[o + 2] << 8
            if t >= 0x2000 and not (block_lo <= t < block_hi):
                data_refs.append((addr, op, t))
        elif op in (0xAF, 0xBF, 0x8F, 0x9F, 0x5C, 0x6C, 0xDC):
            t = out[o + 1] | out[o + 2] << 8
            data_refs.append((addr, op, t))
        elif op in (0x7C, 0xFC):
            t = out[o + 1] | out[o + 2] << 8
            if not (block_lo <= t < block_hi):
                data_refs.append((addr, op, t))
    report = {
        "reached": len(code), "fixed": fixed, "internal": internal,
        "data_refs": data_refs, "unresolved": unresolved,
        "jsl_map": JSL_MAP,
    }
    return bytes(out), report


# The block this file produces, as measured on 2026-08-10 immediately BEFORE the
# decode tables were moved to tools/dis65816.py. `--check` re-derives it: this
# file feeds mksaturn_smoke, whose ROMs have recorded hashes, so any change here
# is a change to a published artifact unless these two numbers hold.
GATE_SHA1 = "30fcfdbb839d85044f39f65fb062ceddb88b18c2"
GATE_REACHED = 1788


def main():
    import argparse
    import hashlib
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="byte-identity gate: the ported block must be unchanged")
    args = ap.parse_args()

    from smspaths import supers_rom, clean_rom
    sup = open(supers_rom(), "rb").read()
    if len(sup) % 0x8000 == 0x200:
        sup = sup[0x200:]
    sms = open(clean_rom(), "rb").read()
    blk, rep = patched_block(sup, sms)

    if args.check:
        got = hashlib.sha1(blk).hexdigest()
        bad = []
        if got != GATE_SHA1:
            bad.append(f"block sha1 {got}, expected {GATE_SHA1}")
        if rep["reached"] != GATE_REACHED:
            bad.append(f"reached {rep['reached']}, expected {GATE_REACHED}")
        for line in bad:
            print(f"  \033[31mFAIL\033[0m  {line}")
        if bad:
            sys.exit(1)
        print(f"\033[32mOK\033[0m  ported block byte-identical "
              f"({GATE_REACHED} instructions reached, sha1 {GATE_SHA1[:8]}…)")
        return
    print(f"block {BLOCK_LO:04X}-{BLOCK_HI:04X}: {rep['reached']} instructions reached")
    print(f"fixed {len(rep['fixed'])} external operands, {rep['internal']} internal refs kept")
    print("JSL map:", {f"{k:06X}": f"{v:06X}" for k, v in rep["jsl_map"].items()})
    if rep["unresolved"]:
        print("UNRESOLVED:")
        for a, op, t in rep["unresolved"]:
            print(f"  {a:04X}: op {op:02X} -> {t:04X}")
    if rep["data_refs"]:
        print("DATA/ODD refs to review:")
        for a, op, t in rep["data_refs"]:
            print(f"  {a:04X}: op {op:02X} -> {t:04X}")


if __name__ == "__main__":
    main()
