#!/usr/bin/env python3
"""Decode SNES BRR samples to WAV.

Used to identify Saturn's voice samples by ear: Super S keeps 7 per character
(directory entries 28-34 at ARAM $1E00), and which one is the throw shout, the
laugh or the select "Yoroshiku" is a question for a listener, not a disassembler.

  brr.py <aram.bin> <start_hex> <end_hex> <out.wav>

BRR is 9-byte blocks: a header (range<<4 | filter<<2 | loop<<1 | end) then 8
bytes holding 16 signed nibbles. Four filters predict from the previous two
samples; the standard coefficients are below.
"""
import struct
import sys
from pathlib import Path

FILTERS = [(0, 0), (15 / 16, 0), (61 / 32, -15 / 16), (115 / 64, -13 / 16)]


def decode(data):
    """-> list of 16-bit signed samples, and whether an end flag was seen."""
    out = []
    p1 = p2 = 0
    ended = False
    for o in range(0, len(data) - 8, 9):
        hdr = data[o]
        rng, filt = hdr >> 4, (hdr >> 2) & 3
        end, loop = hdr & 1, (hdr >> 1) & 1
        for i in range(16):
            b = data[o + 1 + i // 2]
            nib = (b >> 4) if i % 2 == 0 else (b & 0xF)
            if nib > 7:
                nib -= 16
            s = (nib << rng) >> 1 if rng <= 12 else (nib >> 3) << 12
            a, b_ = FILTERS[filt]
            s += int(p1 * a + p2 * b_)
            s = max(-32768, min(32767, s))
            p2, p1 = p1, s
            out.append(s)
        if end:
            ended = True
            break
    return out, ended


def write_wav(path, samples, rate=32000):
    n = len(samples)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + n * 2) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16))
        f.write(b"data" + struct.pack("<I", n * 2))
        f.write(struct.pack(f"<{n}h", *samples))


if __name__ == "__main__":
    aram = Path(sys.argv[1]).read_bytes()
    start = int(sys.argv[2], 16)
    end = int(sys.argv[3], 16)
    pcm, ended = decode(aram[start:end])
    write_wav(sys.argv[4], pcm)
    print(f"{sys.argv[4]}: {len(pcm)} samples, {len(pcm)/32000:.2f}s"
          f"{'' if ended else ' (no end flag — range may be wrong)'}")
