"""supers_lz.py — the SMS/Super S graphics LZSS decompressor, in Python.

Reverse-engineered from Super S $C0:EE30 (v0.11.4 session; SMS carries a twin).
Validated byte-exact against a live $7F:0000 staging dump AND the trajectory of
every control-byte iteration (src/dst/count checkpoints all matched).

Stream format: [token_count:u16le][data]. Data is control-byte driven, LSB
first: a run of K consecutive 1-bits emits K literal bytes (copied from the
stream); a 0-bit emits one backreference — a 2-byte little-endian word w with
distance = w >> 4 (12 bits) and length = (w & 0xF) + 3, copying from
out[-distance-1] forward (MVN semantics: overlap-safe, RLE-capable).
Each literal byte and each backref count as ONE token. A control byte that
spends its 8 bits on literals gets no trailing backref.

The engine runs jobs from a 6-byte-entry table at $80:EEF1
([src16, srcbank, vramlo, vramhi, flags]); decompression always lands at
$7F:0000 (the RAM-resident `MVN $7F,$xx / RTL` gadget at $00:00C8 — its bank
operand at $00:00CA is bumped when the source crosses a bank) and is DMA'd to
the entry's VRAM word address afterwards. Character effect-tile jobs:
P1 = table index 47 + charID (VRAM $6A00), P2 = 57 + charID (VRAM $7300) —
Saturn (id 10) = idx 57/67, source $E3:FA09, output 0x1040 bytes.
"""

JOB_TABLE = 0xEEF1            # file offset, bank $80 ($C0 low half mirror)
SATURN_FX_SRC = 0x23FA09      # file offset of her effect-tile stream header


def lz_decompress(rom, src):
    """Decompress one stream at file offset `src` (header included)."""
    count = rom[src] | rom[src + 1] << 8
    src += 2
    out = bytearray()
    while count > 0:
        ctrl = rom[src]
        src += 1
        bits = 8
        while bits > 0 and count > 0:
            k = 0
            while bits > 0 and (ctrl & 1):
                ctrl >>= 1
                bits -= 1
                k += 1
            if k:
                out += rom[src:src + k]
                src += k
                count -= k
                if count <= 0:
                    break
            if bits == 0:
                break
            ctrl >>= 1
            bits -= 1                      # the 0 bit
            w = rom[src] | rom[src + 1] << 8
            src += 2
            start = len(out) - (w >> 4) - 1
            if start < 0:
                # without this, Python's negative indexing silently copies from
                # the TAIL of the buffer — plausible-looking wrong bytes
                raise ValueError(f"back-reference before start at out+{len(out)}")
            for i in range((w & 0xF) + 3):
                out.append(out[start + i])
            count -= 1
    return bytes(out)


def job_entry(rom, idx):
    """Read job-table entry -> (file_src_of_header, vram_word_addr, flags)."""
    e = rom[JOB_TABLE + 6 * idx:JOB_TABLE + 6 * idx + 6]
    src = ((e[2] & 0x3F) << 16) | e[0] | e[1] << 8
    return src, e[3] | e[4] << 8, e[5]
