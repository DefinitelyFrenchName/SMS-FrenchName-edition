#!/usr/bin/env python3
"""Stage port PoC: put a Super S stage into SMS, over Sailor Pluto's slot.

Target chosen by the maintainer: **stage 2, the space-time door** — the one
stage tournaments only play by mutual agreement, so it is the cheapest slot to
lose and the best long-term removal candidate.

How SMS loads a stage (all verified live, see docs/saturn/supers_assets.md):

    $7E:008E          scene id * 2
    $E0:017A + id*2   -> scene script: [record ids ... $FF][palette ids ... $FF]
    $E0:02DC + k*6    asset record k: [src24][vram16][flag8]
    $C0:853D          loader: sets DP $00 = src, $03 = vram, $02 = src bank,
                      then (flag 1..$7D) jmp $C0:916B = decompress + DMA
    $E0:0390 + p*6    palette record: [start_colour][src16][bank][count16],
                      copied RAW into the CGRAM shadow at $7E:0500

Scene 2 = records 6,7,8 (tiles -> VRAM $2000, map -> $0000, map -> $0800) and
palettes 3 (BG rows 2-7) + 13 (one OBJ row).

The port needs no SMS-codec work in either direction:

  * ART — the three records are repointed at RAW, already-decompressed Super S
    data in an appended bank, and `$C0:916B` gets a 4-byte `jml` to a stub that
    recognises that bank and DMAs it straight to VRAM (skipping decompression
    AND the `$7F` staging copy). Any other caller falls through to the vanilla
    path, byte-for-byte.
  * PALETTE — SMS's palette blocks are already raw, so Super S's are simply
    written over stage 2's. No hook at all.

Super S's structures are the same, so its side is pure data:
    $E0:AB22   scene scripts (same format)
    job table  = its asset records (index == supers_lz job index)
    $E0:AC7A   palette records (same format)

Source stage is SUPERS_SCENE below (default 1 = the moonlit terrace with the
Elysion palace skyline; jobs 0/1/2, palettes 2 + 12). Swapping it is one
constant — every Super S stage decompresses to within SMS's budget (tilesets
0x1F40-0x5F60 vs the 0x6000 window, tilemaps exactly 0x1000).
"""
import sys
from hashlib import sha1
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "tools"))
sys.path.insert(0, str(REPO / "tools" / "saturn"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum
import supers_lz as LZ

CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

# ---- SMS side -----------------------------------------------------------
SMS_RECORDS = 0x02DC          # asset record 0, in bank $E0
SMS_PALRECS = 0x0390          # palette record 0, in bank $E0
SMS_STAGE = 2                 # Pluto — the space-time door
# Hook the ASSET LOADER's tail, not the decompressor entry ($C0:916B). $916B is
# called from five places in several accumulator widths, and a stub that assumes
# 8-bit there mis-parses its own code when A is 16-bit (it ran off into the
# appended bank and BRK'd into the engine's trap loop at $C0:FFAE). At $C0:8561
# the mode is fixed by the `sep #$20` six instructions earlier, and only asset
# records come through, so the stub sees exactly one shape of caller.
SITE_LOAD = 0x008561          # cmp #$7E / bcs $8568 / jmp $916B
SITE_LOAD_OLD = bytes.fromhex("c97eb0034c6b91")

# ---- Super S side -------------------------------------------------------
SUP_SCENES = 0xAB22           # scene-script pointer table (bank $E0)
SUP_PALRECS = 0xAC7A          # palette record 0 (bank $E0)
SUPERS_SCENE = 1              # moonlit terrace / Elysion skyline

STUB = 0x8000                 # in our appended bank
BLOBS = 0x8100


def supers_rom():
    import glob, os
    for d in (os.environ.get("SMS_ROM_DIR"), str(REPO / "roms"), str(REPO.parent / "roms")):
        if not d:
            continue
        for f in sorted(glob.glob(os.path.join(d, "*.sfc")) + glob.glob(os.path.join(d, "*.smc"))):
            if "SuperS" in f:
                return f
    raise SystemExit("error: Super S ROM not found (looked in $SMS_ROM_DIR, roms/, ../roms/)")


def read_script(rom, base, idx, bank_file):
    """-> (record ids, palette ids) for one scene."""
    p = rom[bank_file + base + idx * 2] | rom[bank_file + base + idx * 2 + 1] << 8
    o = bank_file + p
    recs = []
    while rom[o] != 0xFF:
        recs.append(rom[o]); o += 1
    o += 1
    pals = []
    while rom[o] != 0xFF:
        pals.append(rom[o]); o += 1
    return recs, pals


def palette_block(rom, table, pid, bank_file):
    o = bank_file + table + pid * 6
    start, src, bank, n = rom[o], rom[o + 1] | rom[o + 2] << 8, rom[o + 3], rom[o + 4] | rom[o + 5] << 8
    # bank $E0 == file 0x200000 in both ROMs (both are 4 MB HiROM)
    off = (bank - 0xC0) * 0x10000 + src
    return start, rom[off:off + n], n


def build(src_path, out_path):
    data = bytearray(open(src_path, "rb").read())
    sup = open(supers_rom(), "rb").read()
    E0 = 0x200000

    # --- pick the Super S stage: scene -> jobs + palettes ---
    jobs, spals = read_script(sup, SUP_SCENES, SUPERS_SCENE, E0)
    jobs = [j for j in jobs if j != 4]          # record 4 is the shared preamble
    if len(jobs) != 3:
        raise SystemExit(f"scene {SUPERS_SCENE} is not a 3-asset stage: {jobs}")
    blobs = []
    for j in jobs:
        s, vram, _f = LZ.job_entry(sup, j)
        raw = LZ.lz_decompress(sup, s)
        blobs.append((raw, vram))
        print(f"  supers job {j:2d}: {len(raw):#07x} bytes -> VRAM {vram:04X}")

    # --- our bank ---
    bank_file = len(data)
    if bank_file % 0x10000:
        raise SystemExit("input ROM is not bank-aligned")
    bank = 0xC0 + (bank_file >> 16)
    if bank > 0xFF:
        raise SystemExit("no free bank left for the stage data")
    blk = bytearray(0x10000)

    # blobs, each with a 2-byte length header the stub reads
    addrs, cur = [], BLOBS
    for raw, _v in blobs:
        if cur + 2 + len(raw) > 0x10000:
            raise SystemExit("stage data overruns the bank")
        blk[cur:cur + 2] = len(raw).to_bytes(2, "little")
        blk[cur + 2:cur + 2 + len(raw)] = raw
        addrs.append(cur)
        cur += 2 + len(raw)

    # --- the raw-path stub ---
    # entry (from `jmp $916B`): A 8-bit = flag, DP $00-$02 = source long,
    # DP $03 = VRAM word address. Ours -> DMA straight from ROM to VRAM.
    st = bytearray()
    st += bytes((0x48,))                              # pha (save the flag)
    st += bytes((0xA5, 0x02, 0xC9, bank))             # lda $02 / cmp #bank
    st += bytes((0xF0, 0x0D))                         # beq raw (+13)
    st += bytes((0x68, 0xC9, 0x7E))                   # pla / cmp #$7E
    st += bytes((0xB0, 0x04))                         # bcs to8568
    # Both vanilla continuations, in the $80 bank view — NOT $C0. The loader's
    # continuation calls a WRAM gadget (`jsr $0080`, the palette copier), which
    # only exists where $0000-$7FFF is the system area; with PB=$C0 that lands
    # in ROM and hangs the load right after the third stage asset.
    st += bytes((0x5C, 0x6B, 0x91, 0x80))             # jml $80916B (decompress)
    st += bytes((0x5C, 0x68, 0x85, 0x80))             # jml $808568 (raw-to-WRAM)
    assert len(st) == 20, len(st)   # `raw` starts here; keep the beq in sync
    # The raw path does its OWN DMA rather than jumping into $C0:9287, because
    # that helper takes its source from DP $30-$36 — shared state whose bank
    # byte ($36) the vanilla path never re-sets (it is $7F for the whole load).
    # Writing our bank there made the NEXT vanilla asset DMA out of bank $E8.
    st += bytes((0x68,))                              # raw: pla (flag unused)
    st += bytes((0xC2, 0x20, 0xE2, 0x10))             # rep #$20 / sep #$10
    st += bytes((0xA0, 0x18, 0x8C, 0x01, 0x43))       # ldy #$18 / sty $4301
    st += bytes((0xA5, 0x03, 0x8D, 0x16, 0x21))       # VRAM word address -> $2116
    st += bytes((0xA7, 0x00, 0x8D, 0x05, 0x43))       # length header -> $4305
    st += bytes((0xA5, 0x00, 0x1A, 0x1A, 0x8D, 0x02, 0x43))   # src + 2 -> $4302
    st += bytes((0xA4, 0x02, 0x8C, 0x04, 0x43))       # src bank -> $4304
    st += bytes((0xA0, 0x01, 0x8C, 0x00, 0x43))       # mode 1
    st += bytes((0x8C, 0x0B, 0x42))                   # kick channel 0
    # Return through the vanilla helper's OWN `rts` ($80:92AC) instead of our
    # own: `rts` restores only the 16-bit PC, so executing it here would resume
    # the caller with the program bank still set to ours.
    st += bytes((0x5C, 0xAC, 0x92, 0x80))             # jml $8092AC (an `rts`)
    if len(st) > BLOBS - STUB:
        raise SystemExit("stub overruns its slot")
    blk[STUB:STUB + len(st)] = st

    data += blk

    # --- repoint SMS stage 2's three asset records ---
    recs, pals = read_script(bytes(data), 0x017A, SMS_STAGE, E0)
    recs = [r for r in recs if r != 4]
    if len(recs) != 3:
        raise SystemExit(f"SMS scene {SMS_STAGE} is not a 3-asset stage: {recs}")
    for r, (blobaddr, (raw, vram)) in zip(recs, zip(addrs, blobs)):
        o = E0 + SMS_RECORDS + r * 6
        old_vram = data[o + 3] | data[o + 4] << 8
        if old_vram != vram:
            raise SystemExit(f"record {r}: VRAM {old_vram:04X} but the Super S asset "
                             f"targets {vram:04X} — asset order mismatch")
        print(f"  SMS record {r}: src {data[o]|data[o+1]<<8|data[o+2]<<16:06X} -> "
              f"{bank:02X}:{blobaddr:04X}  (VRAM {vram:04X}, {len(raw):#x} B)")
        data[o:o + 3] = bytes((blobaddr & 0xFF, blobaddr >> 8, bank))

    # --- palettes: raw over raw, no hook ---
    for spid, dpid in zip(spals, pals):
        s_start, s_data, s_n = palette_block(sup, SUP_PALRECS, spid, E0)
        d_start, d_data, d_n = palette_block(bytes(data), SMS_PALRECS, dpid, E0)
        if s_start != d_start:
            raise SystemExit(f"palette {spid}->{dpid}: start colour {s_start} vs {d_start}")
        o = E0 + SMS_PALRECS + dpid * 6
        dst = (data[o + 3] - 0xC0) * 0x10000 + (data[o + 1] | data[o + 2] << 8)
        n = min(s_n, d_n)
        data[dst:dst + n] = s_data[:n]
        print(f"  palette {dpid}: {n} bytes from Super S palette {spid} "
              f"(colours {d_start}..{d_start + n // 2 - 1})")

    # --- the loader hook, last (the only code bytes we touch) ---
    got = bytes(data[SITE_LOAD:SITE_LOAD + len(SITE_LOAD_OLD)])
    if got != SITE_LOAD_OLD:
        raise SystemExit(f"asset loader @{SITE_LOAD:#08x}: found {got.hex()}, "
                         f"expected {SITE_LOAD_OLD.hex()}")
    data[SITE_LOAD:SITE_LOAD + 7] = bytes((0x5C, STUB & 0xFF, STUB >> 8, bank)) + b"\xEA" * 3

    fix_checksum(data)
    open(out_path, "wb").write(data)
    print(f"wrote {out_path}: Super S scene {SUPERS_SCENE} over SMS stage {SMS_STAGE} "
          f"(Pluto), bank ${bank:02X}, sha1={sha1(bytes(data)).hexdigest()}")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Port a Super S stage over SMS's Pluto stage.")
    ap.add_argument("src", nargs="?", default=clean_rom())
    ap.add_argument("out", nargs="?", default=str(REPO / "build/saturn/sms_stageport.sfc"))
    ap.add_argument("--stacked", action="store_true")
    a = ap.parse_args()
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out)
