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

# ---- 65816 decode tables (lengths; imm ops depend on M/X) ----
IMM_M = {0x09, 0x29, 0x49, 0x69, 0x89, 0xA9, 0xC9, 0xE9}
IMM_X = {0xA0, 0xA2, 0xC0, 0xE0}
L1 = set((0x00, 0x0A, 0x18, 0x1A, 0x1B, 0x28, 0x2A, 0x38, 0x3A, 0x3B, 0x40, 0x48,
          0x4A, 0x4B, 0x58, 0x5A, 0x5B, 0x60, 0x68, 0x6A, 0x6B, 0x78, 0x7A, 0x7B,
          0x88, 0x8A, 0x8B, 0x98, 0x9A, 0x9B, 0xA8, 0xAA, 0xAB, 0xB8, 0xBA, 0xBB,
          0xC8, 0xCA, 0xCB, 0xD8, 0xDA, 0xDB, 0xE8, 0xEA, 0xEB, 0xF8, 0xFA, 0xFB))
L2 = set((0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15,
          0x16, 0x17, 0x21, 0x23, 0x24, 0x25, 0x26, 0x27, 0x30, 0x31, 0x32, 0x33,
          0x34, 0x35, 0x36, 0x37, 0x41, 0x43, 0x45, 0x46, 0x47, 0x50, 0x51, 0x52,
          0x53, 0x55, 0x56, 0x57, 0x61, 0x63, 0x64, 0x65, 0x66, 0x67, 0x70, 0x71,
          0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x80, 0x81, 0x83, 0x84, 0x85, 0x86,
          0x87, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0xA1, 0xA3, 0xA4,
          0xA5, 0xA6, 0xA7, 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xC1,
          0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6,
          0xD7, 0xE1, 0xE2, 0xE3, 0xE5, 0xE6, 0xE7, 0xF0, 0xF1, 0xF2, 0xF3, 0xF5,
          0xF6, 0xF7))
L3 = set((0x0C, 0x0D, 0x0E, 0x19, 0x1C, 0x1D, 0x1E, 0x20, 0x2C, 0x2D, 0x2E, 0x39,
          0x3C, 0x3D, 0x3E, 0x4C, 0x4D, 0x4E, 0x59, 0x5D, 0x5E, 0x62, 0x6C, 0x6D,
          0x6E, 0x79, 0x7C, 0x7D, 0x7E, 0x82, 0x8C, 0x8D, 0x8E, 0x99, 0x9C, 0x9D,
          0x9E, 0xAC, 0xAD, 0xAE, 0xB9, 0xBC, 0xBD, 0xBE, 0xCC, 0xCD, 0xCE, 0xD9,
          0xDC, 0xDD, 0xDE, 0xEC, 0xED, 0xEE, 0xF4, 0xF9, 0xFC, 0xFD, 0xFE, 0x44, 0x54))
L4 = set((0x0F, 0x1F, 0x22, 0x2F, 0x3F, 0x4F, 0x5C, 0x5F, 0x6F, 0x7F, 0x8F, 0x9F,
          0xAF, 0xBF, 0xCF, 0xDF, 0xEF, 0xFF))
BRANCH = {0x10, 0x30, 0x50, 0x70, 0x80, 0x90, 0xB0, 0xD0, 0xF0}

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
            if op in IMM_M:
                ln = 2 if m else 3
            elif op in IMM_X:
                ln = 2 if x else 3
            elif op in L1:
                ln = 1
            elif op in L2:
                ln = 2
            elif op in L3:
                ln = 3
            elif op in L4:
                ln = 4
            else:
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


def main():
    from smspaths import supers_rom, clean_rom
    sup = open(supers_rom(), "rb").read()
    if len(sup) % 0x8000 == 0x200:
        sup = sup[0x200:]
    sms = open(clean_rom(), "rb").read()
    blk, rep = patched_block(sup, sms)
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
