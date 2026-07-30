#!/usr/bin/env python3
"""Tiny two-pass 65816 assembler — just the opcodes patch 10's stubs need.

Labels: a bare "name:" line. Instructions: "MNEMONIC operand". Operands:
  #$xx / #$xxxx  immediate (width from current M/X flag tracked by rep/sep... but we
                 keep it explicit: use imm8()/imm16 via the mnemonic suffix isn't worth it,
                 so immediates carry their own width by value size — pass 2-hex vs 4-hex).
  $xxxx          absolute (16-bit addr, DBR-relative)
  label          used by branches (rel8) and JML/JMP (given as $long or label→needs bank).
Only the exact forms used by the stubs are implemented; unknown forms raise.
"""

# opcode encoders keyed by (mnemonic, mode)
def assemble(lines, org, bank):
    """org = 16-bit address of first byte; bank = program bank (for JML-to-self labels).
    Returns (bytes, {label: absaddr}).

    Immediate width follows the 65816 M/X processor flags, tracked through rep/sep — NOT
    the hex-string length (so `ldx #$00` in 16-bit X mode correctly emits a 3-byte imm).
    Start state assumes 8-bit A/X (m=x=1); the stubs set width explicitly up front.
    """
    A_IMM = ("lda", "cmp", "adc", "sbc", "and", "ora", "eor", "bit")   # width = M flag
    X_IMM = ("ldx", "ldy", "cpx", "cpy")                          # width = X flag

    def size_of(mn, op, m, x):
        mn = mn.lower()
        if mn in ("php","plp","phb","plb","pha","pla","phx","plx","phy","ply","rtl","rts","inc_a","dec_a","tax","txa","tay","tya","xba","clc","sec","inx","dex","iny","dey","nop"):
            return 1
        if mn in ("sep","rep"):
            return 2
        if mn in ("bra","bcc","bcs","beq","bne","bpl","bmi"):
            return 2
        if mn in ("inc","dec","stz","lda","sta","cmp","ldx","stx","ldy","sty","adc","sbc","and","ora","eor","asl","lsr","cpx","cpy","bit"):
            if op.startswith("#"):
                if mn not in A_IMM and mn not in X_IMM:
                    raise ValueError(f"{mn} has no immediate form: {mn} {op}")
                if mn in A_IMM:
                    if m is None: raise ValueError(f"immediate width unknown after plp — sep/rep before `{mn} {op}`")
                    return 2 if m else 3
                if x is None: raise ValueError(f"immediate width unknown after plp — sep/rep before `{mn} {op}`")
                return 2 if x else 3
            return 3  # absolute
        if mn in ("jml","jmp"):
            return 4 if mn == "jml" else 3
        if mn in ("lda_l","sta_l","cmp_l","sbc_l","adc_l","lda_lx"):
            return 4  # long addressing: opcode + 24-bit address (lda_lx = long,X)
        if mn in ("lda_y","sta_y","adc_y","cmp_y"):
            return 3  # absolute,Y
        if mn == "lsr_a":
            return 1
        raise ValueError(f"size: unknown {mn} {op}")

    def apply_flags(mn, op, m, x):
        ml = mn.lower()
        if ml in ("sep", "rep"):
            bits = int(op[1:].replace("$", ""), 16)
            val = 1 if ml == "sep" else 0
            if bits & 0x20: m = val
            if bits & 0x10: x = val
        elif ml == "plp":
            m, x = None, None   # width unknown until the next sep/rep (issue #11)
        return m, x

    labels = {}
    pc = org
    m, x = 1, 1
    for ln in lines:
        s = ln.split(";")[0].strip()
        if not s:
            continue
        if s.endswith(":"):
            labels[s[:-1]] = pc
            continue
        parts = s.split(None, 1)
        mn = parts[0]
        op = parts[1].strip() if len(parts) > 1 else ""
        pc += size_of(mn, op, m, x)
        m, x = apply_flags(mn, op, m, x)

    # pass 2: emit
    out = bytearray()
    pc = org
    m, x = 1, 1
    def imm_bytes(op, width16):
        v = int(op[1:].replace("$",""), 16)
        return [v & 0xFF, (v >> 8) & 0xFF] if width16 else [v & 0xFF]
    def abs_bytes(op):
        v = int(op.replace("$",""), 16)
        return [v & 0xFF, (v >> 8) & 0xFF]
    SIMPLE = {"php":0x08,"plp":0x28,"phb":0x8B,"plb":0xAB,"pha":0x48,"pla":0x68,"lsr_a":0x4A,
              "phx":0xDA,"plx":0xFA,"phy":0x5A,"ply":0x7A,"rtl":0x6B,"rts":0x60,
              "tax":0xAA,"txa":0x8A,"tay":0xA8,"tya":0x98,"xba":0xEB,"clc":0x18,"sec":0x38,
              "inc_a":0x1A,"dec_a":0x3A,"inx":0xE8,"dex":0xCA,"iny":0xC8,"dey":0x88,"nop":0xEA}
    BR = {"bra":0x80,"bcc":0x90,"bcs":0xB0,"beq":0xF0,"bne":0xD0,"bpl":0x10,"bmi":0x30}
    LONG = {"lda_l":0xAF,"sta_l":0x8F,"cmp_l":0xCF,"sbc_l":0xEF,"adc_l":0x6F,"lda_lx":0xBF}   # absolute-long (lda_lx = long,X)
    ABSY = {"lda_y":0xB9,"sta_y":0x99,"adc_y":0x79,"cmp_y":0xD9}                  # absolute,Y
    # absolute opcodes: (imm, abs)
    OPS = {"lda":(0xA9,0xAD),"sta":(None,0x8D),"cmp":(0xC9,0xCD),"ldx":(0xA2,0xAE),
           "stx":(None,0x8E),"ldy":(0xA0,0xAC),"sty":(None,0x8C),"adc":(0x69,0x6D),
           "sbc":(0xE9,0xED),"and":(0x29,0x2D),"ora":(0x09,0x0D),"eor":(0x49,0x4D),"inc":(None,0xEE),
           "dec":(None,0xCE),"stz":(None,0x9C),"asl":(None,0x0E),"lsr":(None,0x4E),
           "cpx":(0xE0,0xEC),"cpy":(0xC0,0xCC),"bit":(0x89,0x2C)}
    for ln in lines:
        s = ln.split(";")[0].strip()
        if not s or s.endswith(":"):
            continue
        parts = s.split(None, 1)
        mn = parts[0].lower()
        op = parts[1].strip() if len(parts) > 1 else ""
        start = pc
        if mn in SIMPLE:
            out.append(SIMPLE[mn]); pc += 1
        elif mn in ("sep","rep"):
            out += bytes([0xE2 if mn == "sep" else 0xC2, int(op[1:].replace("$",""),16)]); pc += 2
        elif mn in BR:
            if op not in labels:
                raise ValueError(f"branch to undefined label: {mn} {op}")
            target = labels[op]
            rel = target - (pc + 2)
            if not (-128 <= rel <= 127):
                raise ValueError(f"branch out of range: {op} ({rel})")
            out += bytes([BR[mn], rel & 0xFF]); pc += 2
        elif mn in ("jml","jmp"):
            if op in labels:
                addr = labels[op]; bk = bank
            else:
                v = int(op.replace("$",""), 16)
                addr = v & 0xFFFF; bk = (v >> 16) & 0xFF
            if mn == "jml":
                out += bytes([0x5C, addr & 0xFF, (addr >> 8) & 0xFF, bk]); pc += 4
            else:
                out += bytes([0x4C, addr & 0xFF, (addr >> 8) & 0xFF]); pc += 3
        elif mn in LONG:
            v = int(op.replace("$",""), 16)
            out += bytes([LONG[mn], v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF]); pc += 4
        elif mn in ABSY:
            v = int(op.replace("$",""), 16)
            out += bytes([ABSY[mn], v & 0xFF, (v >> 8) & 0xFF]); pc += 3
        elif mn in OPS:
            imm_op, abs_op = OPS[mn]
            if op.startswith("#"):
                if imm_op is None:
                    raise ValueError(f"{mn} has no immediate form")
                if mn in A_IMM: width16 = (m == 0)
                elif mn in X_IMM: width16 = (x == 0)
                else: width16 = False
                if (mn in A_IMM and m is None) or (mn in X_IMM and x is None):
                    raise ValueError(f"immediate width unknown after plp — sep/rep before `{mn} {op}`")
                ib = imm_bytes(op, width16)
                out.append(imm_op); out += bytes(ib); pc += 1 + len(ib)
            else:
                out.append(abs_op); out += bytes(abs_bytes(op)); pc += 3
        else:
            raise ValueError(f"emit: unknown {mn} {op}")
        m, x = apply_flags(mn, op, m, x)
    return bytes(out), labels
