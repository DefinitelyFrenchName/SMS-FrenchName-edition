#!/usr/bin/env python3
"""spc700dis.py — SPC700 disassembler for the SMS sound driver.

The driver is uploaded to ARAM at boot, so the thing to disassemble is a 64 KB
ARAM dump (traces/saturn/aram_*.bin, written by probe_aramdump.lua) or a raw
slice of ROM.  Nothing else in the tree can read SPC code; Dispel is 65816 only.

    tools/saturn/spc700dis.py <aram.bin> --at 0x1300 --len 0x80
    tools/saturn/spc700dis.py <aram.bin> --refs 0x02B0      # who touches this addr
    tools/saturn/spc700dis.py <aram.bin> --trace 0x1300     # follow flow from here

Operand syntax follows the usual SPC700 convention: d = direct page, !a =
absolute, #i = immediate, (X)/(Y) indirect, [d+X]/[d]+Y indexed indirect.
Note the two-operand forms store SOURCE first in the encoding and are printed
destination-first (e.g. `FA ss dd` -> `MOV dd, ss`), which is the assembler
order and the one that matches every published table.
"""
import argparse
import sys

# (mnemonic, format) — format placeholders consumed left to right from the
# operand bytes.  Sizes are derived from the format string.
IMP, REL, DP, DPX, DPY, ABS, IMM = "imp", "rel", "d", "dx", "dy", "a", "i"

OPS = {}


def _d(op, mnem, fmt=IMP):
    OPS[op] = (mnem, fmt)


# fmt is a tuple describing operand bytes in encoding order and how to print.
# We spell each entry explicitly rather than deriving it — a wrong size here
# desynchronises the whole listing, so it is worth being boring.
TABLE = {
    0x00: ("NOP", ""), 0x01: ("TCALL 0", ""), 0x02: ("SET1", "d.0"), 0x03: ("BBS", "d.0,r"),
    0x04: ("OR", "A,d"), 0x05: ("OR", "A,!a"), 0x06: ("OR", "A,(X)"), 0x07: ("OR", "A,[d+X]"),
    0x08: ("OR", "A,#i"), 0x09: ("OR", "dd,ds"), 0x0A: ("OR1", "C,m.b"), 0x0B: ("ASL", "d"),
    0x0C: ("ASL", "!a"), 0x0D: ("PUSH", "PSW"), 0x0E: ("TSET1", "!a"), 0x0F: ("BRK", ""),
    0x10: ("BPL", "r"), 0x11: ("TCALL 1", ""), 0x12: ("CLR1", "d.0"), 0x13: ("BBC", "d.0,r"),
    0x14: ("OR", "A,d+X"), 0x15: ("OR", "A,!a+X"), 0x16: ("OR", "A,!a+Y"), 0x17: ("OR", "A,[d]+Y"),
    0x18: ("OR", "d,#i"), 0x19: ("OR", "(X),(Y)"), 0x1A: ("DECW", "d"), 0x1B: ("ASL", "d+X"),
    0x1C: ("ASL", "A"), 0x1D: ("DEC", "X"), 0x1E: ("CMP", "X,!a"), 0x1F: ("JMP", "[!a+X]"),
    0x20: ("CLRP", ""), 0x21: ("TCALL 2", ""), 0x22: ("SET1", "d.1"), 0x23: ("BBS", "d.1,r"),
    0x24: ("AND", "A,d"), 0x25: ("AND", "A,!a"), 0x26: ("AND", "A,(X)"), 0x27: ("AND", "A,[d+X]"),
    0x28: ("AND", "A,#i"), 0x29: ("AND", "dd,ds"), 0x2A: ("OR1", "C,/m.b"), 0x2B: ("ROL", "d"),
    0x2C: ("ROL", "!a"), 0x2D: ("PUSH", "A"), 0x2E: ("CBNE", "d,r"), 0x2F: ("BRA", "r"),
    0x30: ("BMI", "r"), 0x31: ("TCALL 3", ""), 0x32: ("CLR1", "d.1"), 0x33: ("BBC", "d.1,r"),
    0x34: ("AND", "A,d+X"), 0x35: ("AND", "A,!a+X"), 0x36: ("AND", "A,!a+Y"),
    0x37: ("AND", "A,[d]+Y"), 0x38: ("AND", "d,#i"), 0x39: ("AND", "(X),(Y)"),
    0x3A: ("INCW", "d"), 0x3B: ("ROL", "d+X"), 0x3C: ("ROL", "A"), 0x3D: ("INC", "X"),
    0x3E: ("CMP", "X,d"), 0x3F: ("CALL", "!a"),
    0x40: ("SETP", ""), 0x41: ("TCALL 4", ""), 0x42: ("SET1", "d.2"), 0x43: ("BBS", "d.2,r"),
    0x44: ("EOR", "A,d"), 0x45: ("EOR", "A,!a"), 0x46: ("EOR", "A,(X)"), 0x47: ("EOR", "A,[d+X]"),
    0x48: ("EOR", "A,#i"), 0x49: ("EOR", "dd,ds"), 0x4A: ("AND1", "C,m.b"), 0x4B: ("LSR", "d"),
    0x4C: ("LSR", "!a"), 0x4D: ("PUSH", "X"), 0x4E: ("TCLR1", "!a"), 0x4F: ("PCALL", "u"),
    0x50: ("BVC", "r"), 0x51: ("TCALL 5", ""), 0x52: ("CLR1", "d.2"), 0x53: ("BBC", "d.2,r"),
    0x54: ("EOR", "A,d+X"), 0x55: ("EOR", "A,!a+X"), 0x56: ("EOR", "A,!a+Y"),
    0x57: ("EOR", "A,[d]+Y"), 0x58: ("EOR", "d,#i"), 0x59: ("EOR", "(X),(Y)"),
    0x5A: ("CMPW", "YA,d"), 0x5B: ("LSR", "d+X"), 0x5C: ("LSR", "A"), 0x5D: ("MOV", "X,A"),
    0x5E: ("CMP", "Y,!a"), 0x5F: ("JMP", "!a"),
    0x60: ("CLRC", ""), 0x61: ("TCALL 6", ""), 0x62: ("SET1", "d.3"), 0x63: ("BBS", "d.3,r"),
    0x64: ("CMP", "A,d"), 0x65: ("CMP", "A,!a"), 0x66: ("CMP", "A,(X)"), 0x67: ("CMP", "A,[d+X]"),
    0x68: ("CMP", "A,#i"), 0x69: ("CMP", "dd,ds"), 0x6A: ("AND1", "C,/m.b"), 0x6B: ("ROR", "d"),
    0x6C: ("ROR", "!a"), 0x6D: ("PUSH", "Y"), 0x6E: ("DBNZ", "d,r"), 0x6F: ("RET", ""),
    0x70: ("BVS", "r"), 0x71: ("TCALL 7", ""), 0x72: ("CLR1", "d.3"), 0x73: ("BBC", "d.3,r"),
    0x74: ("CMP", "A,d+X"), 0x75: ("CMP", "A,!a+X"), 0x76: ("CMP", "A,!a+Y"),
    0x77: ("CMP", "A,[d]+Y"), 0x78: ("CMP", "d,#i"), 0x79: ("CMP", "(X),(Y)"),
    0x7A: ("ADDW", "YA,d"), 0x7B: ("ROR", "d+X"), 0x7C: ("ROR", "A"), 0x7D: ("MOV", "A,X"),
    0x7E: ("CMP", "Y,d"), 0x7F: ("RETI", ""),
    0x80: ("SETC", ""), 0x81: ("TCALL 8", ""), 0x82: ("SET1", "d.4"), 0x83: ("BBS", "d.4,r"),
    0x84: ("ADC", "A,d"), 0x85: ("ADC", "A,!a"), 0x86: ("ADC", "A,(X)"), 0x87: ("ADC", "A,[d+X]"),
    0x88: ("ADC", "A,#i"), 0x89: ("ADC", "dd,ds"), 0x8A: ("EOR1", "C,m.b"), 0x8B: ("DEC", "d"),
    0x8C: ("DEC", "!a"), 0x8D: ("MOV", "Y,#i"), 0x8E: ("POP", "PSW"), 0x8F: ("MOV", "d,#i"),
    0x90: ("BCC", "r"), 0x91: ("TCALL 9", ""), 0x92: ("CLR1", "d.4"), 0x93: ("BBC", "d.4,r"),
    0x94: ("ADC", "A,d+X"), 0x95: ("ADC", "A,!a+X"), 0x96: ("ADC", "A,!a+Y"),
    0x97: ("ADC", "A,[d]+Y"), 0x98: ("ADC", "d,#i"), 0x99: ("ADC", "(X),(Y)"),
    0x9A: ("SUBW", "YA,d"), 0x9B: ("DEC", "d+X"), 0x9C: ("DEC", "A"), 0x9D: ("MOV", "X,SP"),
    0x9E: ("DIV", "YA,X"), 0x9F: ("XCN", "A"),
    0xA0: ("EI", ""), 0xA1: ("TCALL 10", ""), 0xA2: ("SET1", "d.5"), 0xA3: ("BBS", "d.5,r"),
    0xA4: ("SBC", "A,d"), 0xA5: ("SBC", "A,!a"), 0xA6: ("SBC", "A,(X)"), 0xA7: ("SBC", "A,[d+X]"),
    0xA8: ("SBC", "A,#i"), 0xA9: ("SBC", "dd,ds"), 0xAA: ("MOV1", "C,m.b"), 0xAB: ("INC", "d"),
    0xAC: ("INC", "!a"), 0xAD: ("CMP", "Y,#i"), 0xAE: ("POP", "A"), 0xAF: ("MOV", "(X)+,A"),
    0xB0: ("BCS", "r"), 0xB1: ("TCALL 11", ""), 0xB2: ("CLR1", "d.5"), 0xB3: ("BBC", "d.5,r"),
    0xB4: ("SBC", "A,d+X"), 0xB5: ("SBC", "A,!a+X"), 0xB6: ("SBC", "A,!a+Y"),
    0xB7: ("SBC", "A,[d]+Y"), 0xB8: ("SBC", "d,#i"), 0xB9: ("SBC", "(X),(Y)"),
    0xBA: ("MOVW", "YA,d"), 0xBB: ("INC", "d+X"), 0xBC: ("INC", "A"), 0xBD: ("MOV", "SP,X"),
    0xBE: ("DAS", "A"), 0xBF: ("MOV", "A,(X)+"),
    0xC0: ("DI", ""), 0xC1: ("TCALL 12", ""), 0xC2: ("SET1", "d.6"), 0xC3: ("BBS", "d.6,r"),
    0xC4: ("MOV", "d,A"), 0xC5: ("MOV", "!a,A"), 0xC6: ("MOV", "(X),A"), 0xC7: ("MOV", "[d+X],A"),
    0xC8: ("CMP", "X,#i"), 0xC9: ("MOV", "!a,X"), 0xCA: ("MOV1", "m.b,C"), 0xCB: ("MOV", "d,Y"),
    0xCC: ("MOV", "!a,Y"), 0xCD: ("MOV", "X,#i"), 0xCE: ("POP", "X"), 0xCF: ("MUL", "YA"),
    0xD0: ("BNE", "r"), 0xD1: ("TCALL 13", ""), 0xD2: ("CLR1", "d.6"), 0xD3: ("BBC", "d.6,r"),
    0xD4: ("MOV", "d+X,A"), 0xD5: ("MOV", "!a+X,A"), 0xD6: ("MOV", "!a+Y,A"),
    0xD7: ("MOV", "[d]+Y,A"), 0xD8: ("MOV", "d,X"), 0xD9: ("MOV", "d+Y,X"), 0xDA: ("MOVW", "d,YA"),
    0xDB: ("MOV", "d+X,Y"), 0xDC: ("DEC", "Y"), 0xDD: ("MOV", "A,Y"), 0xDE: ("CBNE", "d+X,r"),
    0xDF: ("DAA", "A"),
    0xE0: ("CLRV", ""), 0xE1: ("TCALL 14", ""), 0xE2: ("SET1", "d.7"), 0xE3: ("BBS", "d.7,r"),
    0xE4: ("MOV", "A,d"), 0xE5: ("MOV", "A,!a"), 0xE6: ("MOV", "A,(X)"), 0xE7: ("MOV", "A,[d+X]"),
    0xE8: ("MOV", "A,#i"), 0xE9: ("MOV", "X,!a"), 0xEA: ("NOT1", "m.b"), 0xEB: ("MOV", "Y,d"),
    0xEC: ("MOV", "Y,!a"), 0xED: ("NOTC", ""), 0xEE: ("POP", "Y"), 0xEF: ("SLEEP", ""),
    0xF0: ("BEQ", "r"), 0xF1: ("TCALL 15", ""), 0xF2: ("CLR1", "d.7"), 0xF3: ("BBC", "d.7,r"),
    0xF4: ("MOV", "A,d+X"), 0xF5: ("MOV", "A,!a+X"), 0xF6: ("MOV", "A,!a+Y"),
    0xF7: ("MOV", "A,[d]+Y"), 0xF8: ("MOV", "X,d"), 0xF9: ("MOV", "X,d+Y"), 0xFA: ("MOV", "dd,ds"),
    0xFB: ("MOV", "Y,d+X"), 0xFC: ("INC", "Y"), 0xFD: ("MOV", "Y,A"), 0xFE: ("DBNZ", "Y,r"),
    0xFF: ("STOP", ""),
}

# how many operand bytes each format string consumes
def op_size(fmt):
    n = 0
    if "dd,ds" in fmt:
        return 2
    if "m.b" in fmt:
        return 2
    if fmt.count("d.") and ",r" in fmt:      # BBS/BBC d.b, rel
        return 2
    if fmt in ("d,r", "d+X,r"):              # CBNE / DBNZ
        return 2
    if fmt == "d,#i":                        # imm first, then dp
        return 2
    n += fmt.count("!a") * 2
    n += fmt.count("d") - fmt.count("d.") - 2 * fmt.count("dd")
    n += fmt.count("#i")
    n += fmt.count("u")
    n += 1 if fmt.endswith("r") and "," not in fmt else 0
    return max(n, 0)


# names for known SPC hardware / driver locations, filled in as they are proven
LABELS = {
    0x00F0: "TEST", 0x00F1: "CONTROL", 0x00F2: "DSPADDR", 0x00F3: "DSPDATA",
    0x00F4: "PORT0", 0x00F5: "PORT1", 0x00F6: "PORT2", 0x00F7: "PORT3",
    0x00F8: "AUX4", 0x00F9: "AUX5", 0x00FA: "T0TARGET", 0x00FB: "T1TARGET",
    0x00FC: "T2TARGET", 0x00FD: "T0OUT", 0x00FE: "T1OUT", 0x00FF: "T2OUT",
}


def decode(mem, pc):
    """Decode one instruction at pc. Returns (size, text, targets)."""
    op = mem[pc]
    mnem, fmt = TABLE[op]
    b = mem[pc + 1:pc + 4]
    targets = []

    def lab(a):
        return LABELS.get(a, "$%04X" % a)

    def rel_from(off, base):
        d = b[off]
        return (base + (d - 256 if d >= 128 else d)) & 0xFFFF

    if fmt == "":
        return 1, mnem, targets
    if fmt == "r":
        t = rel_from(0, pc + 2)
        targets.append(t)
        return 2, "%s $%04X" % (mnem, t), targets
    if fmt in ("d.0,r", "d.1,r", "d.2,r", "d.3,r", "d.4,r", "d.5,r", "d.6,r", "d.7,r"):
        t = rel_from(1, pc + 3)
        targets.append(t)
        return 3, "%s $%02X.%s, $%04X" % (mnem, b[0], fmt[2], t), targets
    if fmt in ("d.0", "d.1", "d.2", "d.3", "d.4", "d.5", "d.6", "d.7"):
        return 2, "%s $%02X.%s" % (mnem, b[0], fmt[2]), targets
    if fmt == "d,r":
        t = rel_from(1, pc + 3)
        targets.append(t)
        return 3, "%s $%02X, $%04X" % (mnem, b[0], t), targets
    if fmt == "d+X,r":
        t = rel_from(1, pc + 3)
        targets.append(t)
        return 3, "%s $%02X+X, $%04X" % (mnem, b[0], t), targets
    if fmt == "Y,r":
        t = rel_from(0, pc + 2)
        targets.append(t)
        return 2, "%s Y, $%04X" % (mnem, t), targets
    if fmt == "dd,ds":
        return 3, "%s $%02X, $%02X" % (mnem, b[1], b[0]), targets
    if fmt == "d,#i":
        return 3, "%s $%02X, #$%02X" % (mnem, b[1], b[0]), targets
    if fmt == "u":
        return 2, "%s $FF%02X" % (mnem, b[0]), targets
    if "m.b" in fmt:
        w = b[0] | (b[1] << 8)
        addr, bit = w & 0x1FFF, w >> 13
        return 3, "%s %s.%d" % (mnem, fmt.replace("m.b", "$%04X" % addr).replace(".b", ""), bit), targets

    text, size = fmt, 1
    if "!a" in fmt:
        a = b[0] | (b[1] << 8)
        text = text.replace("!a", lab(a))
        size += 2
        if mnem in ("CALL", "JMP"):
            targets.append(a)
    if "#i" in fmt:
        # immediate byte position depends on whether an abs already consumed bytes
        text = text.replace("#i", "#$%02X" % b[size - 1])
        size += 1
    if "d" in text and "#" not in fmt and "!a" not in fmt:
        text = text.replace("d", "$%02X" % b[size - 1], 1)
        size += 1
    return size, "%s %s" % (mnem, text), targets


def listing(mem, start, length, out=sys.stdout):
    pc = start
    end = start + length
    while pc < end:
        size, text, _ = decode(mem, pc)
        raw = " ".join("%02X" % x for x in mem[pc:pc + size])
        print("%04X:  %-9s  %s" % (pc, raw, text), file=out)
        pc += size


def trace(mem, start, limit=4000):
    """Follow control flow from start, collecting reachable instruction addrs."""
    seen, work = set(), [start]
    stop = {0x6F, 0x7F, 0x5F, 0xFF, 0x0F}      # RET RETI JMP STOP BRK
    while work and len(seen) < limit:
        pc = work.pop()
        while pc not in seen and 0 <= pc < len(mem):
            seen.add(pc)
            size, _, targets = decode(mem, pc)
            work.extend(t for t in targets if t not in seen)
            op = mem[pc]
            if op in stop or op == 0x2F:        # BRA is unconditional
                if op == 0x2F:
                    pass                        # target already queued
                break
            pc += size
    return sorted(seen)


def refs(mem, addr, lo=0x0200, hi=0x8000):
    """Every instruction in [lo,hi) whose absolute/dp operand names addr."""
    hits = []
    pc = lo
    while pc < hi:
        try:
            size, text, _ = decode(mem, pc)
        except Exception:
            pc += 1
            continue
        if size >= 3:
            a = mem[pc + size - 2] | (mem[pc + size - 1] << 8)
            if a == addr:
                hits.append((pc, text))
        if size >= 2 and addr < 0x100 and mem[pc + 1] == addr:
            hits.append((pc, text))
        pc += 1                                  # unaligned scan: catch every framing
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--at", type=lambda s: int(s, 0))
    ap.add_argument("--len", type=lambda s: int(s, 0), default=0x40)
    ap.add_argument("--trace", type=lambda s: int(s, 0))
    ap.add_argument("--refs", type=lambda s: int(s, 0))
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0,
                    help="ARAM address of image byte 0 (0 for a full ARAM dump)")
    a = ap.parse_args()
    mem = bytearray(0x10000)
    data = open(a.image, "rb").read()
    mem[a.base:a.base + len(data)] = data[:0x10000 - a.base]

    if a.refs is not None:
        for pc, text in refs(mem, a.refs):
            print("%04X:  %s" % (pc, text))
    elif a.trace is not None:
        addrs = trace(mem, a.trace)
        prev = None
        for pc in addrs:
            if prev is not None and pc != prev:
                print("       ...")
            size, text, _ = decode(mem, pc)
            raw = " ".join("%02X" % x for x in mem[pc:pc + size])
            print("%04X:  %-9s  %s" % (pc, raw, text))
            prev = pc + size
    else:
        listing(mem, a.at, a.len)


if __name__ == "__main__":
    main()
