#!/usr/bin/env python3
"""sms_lz.py — SMS's *other* compression codec, the one $C0:916B expands.

This is NOT the LZSS in supers_lz.py (that is the $C0:EE30 / graphics-job codec).
This one carries the per-character MOVELIST tilemaps, and Super S does not have
it — so Saturn's list has to be produced in this format rather than lifted.

Hand-decoded from $C0:919F. Format:

  * a 16-bit control word, LSB first, 16 bits per word, refilled as consumed;
  * **bit 1 = LITERAL**: copy one byte from the stream;
  * **bit 0 = BACK-REFERENCE**, whose form the next control bit selects:
      - next bit 0 = SHORT: two further control bits give L; count = L + 2;
        then one stream byte D gives distance = D - 256   (-256 .. -1)
      - next bit 1 = LONG: one 16-bit stream word w = (hi << 8) | lo:
            count    = (hi & 7) + 2          when (hi & 7) != 0
            distance = ((0xE0 | (hi >> 3)) << 8 | lo)  as a signed 16-bit
                       (-8192 .. -1)
        and when (hi & 7) == 0 an extra byte n follows:
            n == 0  -> END OF STREAM
            n == 1  -> no-op, keep going
            else    -> count = n + 1
  * copies are byte-at-a-time from dest+distance forward, so they are
    overlap-safe and can act as RLE.

`encode_literal` emits an all-literal stream, which the decoder above accepts
verbatim — that is what lets us author Saturn's movelist without writing a
compressor. `encode` adds a cheap RLE pass for the long blank runs a tilemap is
mostly made of.
"""
import sys
from pathlib import Path


def decompress(data, src, limit=0x10000):
    """Expand the stream at `data[src:]`. -> bytes."""
    return decompress_ex(data, src, limit)[0]


def decompress_ex(data, src, limit=0x10000):
    """Expand the stream at `data[src:]`. -> (bytes, compressed length).

    The length matters when patching a block in place: a re-encoded block has to
    fit the space the original occupied."""
    out = bytearray()
    ctrl, nbits = 0, 0

    def bit():
        """Extract a bit, then refill if that emptied the word.

        The refill order matters and is easy to get wrong: the ROM does
        `lsr / dey / bne` — it extracts the bit, and if that was the 16th it
        loads the next control word BEFORE the bit is acted on. So the two
        refill bytes are consumed AHEAD of the literal byte that same bit
        selects. Refilling lazily instead (on the next fetch) reads the control
        word as a literal and desynchronises the whole stream."""
        nonlocal ctrl, nbits, src
        b = ctrl & 1
        ctrl >>= 1
        nbits -= 1
        if nbits == 0:
            ctrl = data[src] | data[src + 1] << 8
            src += 2
            nbits = 16
        return b

    # the routine loads its first control word before the loop
    start = src
    ctrl = data[src] | data[src + 1] << 8
    src += 2
    nbits = 16
    while len(out) < limit:
        if bit():                                   # literal
            out.append(data[src]); src += 1
            continue
        if not bit():                               # short back-reference
            n = (bit() << 1) | bit()                # NOTE: rol order, see below
            count = n + 2
            dist = data[src] - 256; src += 1
        else:                                       # long back-reference
            w = data[src] | data[src + 1] << 8; src += 2
            hi, lo = w >> 8, w & 0xFF
            count = hi & 7
            dist = (((0xE0 | (hi >> 3)) << 8) | lo) - 0x10000
            if count == 0:
                n = data[src]; src += 1
                if n == 0:
                    break                           # end of stream
                if n == 1:
                    continue
                count = n + 1
            else:
                count += 2
        p = len(out) + dist
        if p < 0:
            raise ValueError(f"back-reference before start at out+{len(out)}")
        for i in range(count):
            out.append(out[p + i])
    return bytes(out), src - start


def _emit(ops):
    """ops: list of (control_bits, payload_bytes). -> the byte stream.

    Assembling this is not just "control word then its payloads": because the
    decoder refills mid-fetch (see `bit`), the 16th bit's payload lands AFTER the
    next control word in the byte stream. So the only safe way to lay it out is
    to simulate the decoder — walk the ops, spend their bits, and splice in the
    next control word at the exact moment a word empties.
    """
    bits = []
    for nb, _payload in ops:
        bits.extend(nb)
    # pad the final word with literal-bits; decoding stops at the terminator
    while len(bits) % 16:
        bits.append(1)
    words = []
    for i in range(0, len(bits), 16):
        w = 0
        for j, b in enumerate(bits[i:i + 16]):
            w |= b << j
        words.append(w)

    out = bytearray()
    out.extend((words[0] & 0xFF, words[0] >> 8))
    wi, nb = 1, 16
    for opbits, payload in ops:
        for _ in opbits:
            nb -= 1
            if nb == 0:
                w = words[wi] if wi < len(words) else 0xFFFF
                wi += 1
                out.extend((w & 0xFF, w >> 8))
                nb = 16
        out.extend(payload)
    return bytes(out)


# the terminator: a back-reference (bit 0), long form (bit 1), a word whose
# length field is 0, then the byte 0 that ends the stream
TERMINATOR = ([0, 1], bytes((0x00, 0x00, 0x00)))


def encode_literal(payload):
    """The simplest valid stream: every byte a literal, then the terminator.

    ~9/8 the size of the raw data, which is all we need — appended banks are
    free, and the DMA length comes from how much was written, not from the
    stream. `encode` below adds RLE for the long blank runs of a tilemap.
    """
    return _emit([([1], bytes((b,))) for b in payload] + [TERMINATOR])


def encode(payload):
    """Literals plus a cheap RLE pass, which is most of what the vanilla streams
    do: a tilemap is mostly one repeated blank word, and an overlapping copy at
    distance -2 expands it."""
    ops, i = [], 0
    while i < len(payload):
        run = 0
        if i >= 2:
            while (i + run < len(payload) and run < 254
                   and payload[i + run] == payload[i + run - 2]):
                run += 1
        if run >= 4:                       # long form, escape length, distance -2
            # distance -2 needs high byte $F8: (0xE0 | (0xF8 >> 3)) == 0xFF and
            # low byte $FE, giving $FFFE = -2, while 0xF8 & 7 == 0 selects the
            # escape length. This is the exact word the vanilla streams use.
            w = (0xF8 << 8) | 0xFE
            ops.append(([0, 1], bytes((w & 0xFF, w >> 8, run - 1))))
            i += run
        else:
            ops.append(([1], bytes((payload[i],))))
            i += 1
    ops.append(TERMINATOR)
    return _emit(ops)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("usage: sms_lz.py <rom> <hex src offset> [expected.bin]")
    rom = Path(sys.argv[1]).read_bytes()
    out = decompress(rom, int(sys.argv[2], 16), 0x800)
    print(f"expanded {len(out)} bytes")
    if len(sys.argv) > 3:
        want = Path(sys.argv[3]).read_bytes()
        n = min(len(out), len(want))
        same = out[:n] == want[:n]
        print("matches expected:", same)
        if not same:
            for i in range(n):
                if out[i] != want[i]:
                    print(f"  first difference at {i:#06x}: got {out[i]:02x} want {want[i]:02x}")
                    break
