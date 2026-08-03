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
SUPERS_SCENE = int(__import__("os").environ.get("SUPERS_SCENE", "1"))

# Which Super S scene is what, and which SMS scroll routine matches it. The
# right-hand column is MEASURED (probe_supers_stagejump.lua, per scene): what
# Super S itself does to the two planes, matched against the SMS routine with
# the same shape. Anything not listed keeps SMS stage 2's own vortex routine.
#   $C0:B40A  BG1 = camera/4, BG2 fixed
#   $C0:B42F  BG1 fixed,      BG2 = camera/4
#   $C0:B454  the vortex: one plane drifts continuously (SMS stage 2's own)
SUPERS_STAGES = {
    0: ("Dead Moon Circus, day",   0xB40A),
    1: ("Silver Millennium",       0xB42F),
    8: ("Silent Throne of the Messiah", None),   # its foreground DRIFTS in Super
                                                 # S too (BG2 h +1/frame), so
                                                 # SMS's vortex is the near twin
    9: ("Dead Moon Circus, night", 0xB40A),
}

# Tilemap entry bit $2000 is the per-tile PRIORITY bit. Super S leans on it far
# more than SMS does (this stage: 336 and 948 entries of 2048, vs 0 and 192 on
# SMS's own stage 2), and under SMS's priority setup those tiles draw IN FRONT
# of the fighters — the field saw the castle covering everything below the
# characters' chests. Stripping it puts the whole stage behind the sprites,
# which is what a fighting-game background wants; set to False to keep the
# Super S layering if a stage ever needs a genuine foreground element.
# Super S composes this stage across BOTH planes using the per-tile priority
# bit: map0 holds sky (behind the palace) AND ground (in front of it), the
# ground cells being exactly the ones flagged high-priority (measured: rows
# 10-13). SMS cannot reproduce that, because a high-priority BG tile also draws
# over the fighters — which is the occlusion the field reported first.
#
# So we re-cut the layers instead of re-prioritising them. Every high-priority
# cell of map0 (i.e. the ground) is MOVED into the other tilemap, and the
# priority bit is then stripped everywhere:
#     front plane = palace + ground      back plane = sky
# which renders in the right order with no priority bits at all, so the
# fighters stay in front of everything.
MERGE_GROUND = False
STRIP_PRIORITY = False

# PLANE SPLIT (2026-08-03, field round 2 on #43). Measured on Super S itself
# (probe_supers_stagejump.lua): at a jump apex its palace band moves +4 px while
# its ground stays put — and it does that on ONE plane, per SCANLINE, by
# enabling an HDMA channel onto $210E (BG1VOFS) for the duration of the jump.
# We have no such machinery, and MERGE_GROUND puts the palace and the ground on
# the SAME plane, so once the ground was made to track the camera 1:1 the palace
# was dragged along with it (+11 measured, against Super S's +4).
#
# So split by plane instead of by scanline, which the data allows because Super S
# marks the ground with the priority bit and nothing else: ground alone on BG1
# (1:1, fighters stay planted — the maintainer's preference, and better than
# either original), sky + palace on BG2 at camera/4 (Super S's own rate).
# BG1 draws in front of BG2 in mode 1, which is the occlusion order the re-cut
# was invented to get.
PLANE_SPLIT = False           # superseded by PORT_SCRIPT_TAIL: with $8F ported
                              # the fighters sit at OBJ priority 3 and Super S's
                              # own priority bits compose the stage correctly,
                              # so the maps go in VERBATIM — no re-cut at all

# Per-stage SCROLL ROUTINE. $C0:B317 is a 10-byte table (one per stage) of word
# offsets into a routine pointer table at $C0:B32B:
#   +$00 $C0:B40A  BG1 = camera, BG2 = camera/4   (stage 0)
#   +$02 $C0:B42F  the mirror: BG2 = camera, BG1 = camera/4   (stage 1)
#   +$08 $C0:B454  camera MINUS a counter decremented ~6/frame (stage 2, the
#                  space-time vortex) -- inheriting it is why the ported stage
#                  drifted continuously and sat at a wrong offset.
# Confirmed by measurement: stage 0 moves BG1 only, stage 1 moves BG2 only,
# stage 2 moves both in opposite directions.
# The per-stage selector byte turned out not to be where it looked, but the
# ROUTINE POINTER TABLE is enough: entry $C0:B32F is the vortex routine and, as
# measured, ONLY stage 2 selects it (patching it leaves stages 0/1/3 exactly as
# they were), so repointing that entry is effectively a per-stage change.
# Re-framing knob for the far tilemap (it wraps, so a rotation is free). Left at
# 0: rendering both maps offline shows the palace occupies map ROWS 0-10 while
# the near layer's floor is rows 9-13, so what is out of frame is the far
# plane's VERTICAL offset under the new scroll routine, not its horizontal one.
# Fixing that needs BG2VOFS measured ($210E/$2110) and then either a row
# rotation here or a small custom scroll routine.
MAP1_SHIFT = 0                # tiles; horizontal re-framing (unused: the
                              # far layer is off VERTICALLY, not horizontally)

# Which PLANE each tilemap lands on. The two games put their stage tilemaps at
# the same VRAM addresses ($0000 and $0800), but if their BG tilemap-base
# registers are reversed, a straight copy puts Super S's far map on SMS's near
# plane. Field symptoms of exactly that: the sky/horizon drawn IN FRONT of the
# palace, the far layer framed wrong, and the two planes scrolling at each
# other's rates.
SWAP_MAPS = False

# Carry the scene script's THIRD LIST and its three tail bytes across with the
# art (see parse_script). Without this the ported stage keeps SMS stage 2's
# configuration -- including $8F = 0x10, the one stage in the game that draws
# the fighters at OBJ priority 2 -- and no arrangement of two BG planes can then
# reproduce the three depths the art was drawn for.
PORT_SCRIPT_TAIL = True
PORT_A2 = __import__("os").environ.get("PORT_A2") == "1"

SCROLL_PTR = 0x00B32F         # the entry stage 2 selects
SCROLL_PTR_OLD = bytes.fromhex("54b4")    # $C0:B454, the vortex
_SCROLL_TARGET = SUPERS_STAGES.get(SUPERS_SCENE, (None, None))[1]
SCROLL_PTR_NEW = (bytes([_SCROLL_TARGET & 0xFF, _SCROLL_TARGET >> 8])
                  if _SCROLL_TARGET else None)

# ---- the jump slide (#43) ----------------------------------------------
# Measured (probe_sms_stagejump.lua, scene forced to 2): the scroll block at
# $0A00 holds camera x/y, and $0A18..$0A27 the four per-plane (h,v) pairs, of
# which BG1 = $0A18/$0A1A and BG2 = $0A1C/$0A1E. OBJECTS are placed at the FULL
# camera -- with the dummy's idle pose held constant, her sprite top tracks camY
# 1:1 (topY + camY == 89 across camY 0..-12). So whatever a plane does NOT do
# with the full camera, everything standing on that plane slides against.
#
#   $C0:B40A (stage 0):  BG1 = camera/4 both axes, BG2 = 0
#   $C0:B454 (stage 2):  BG1 = camera 1:1 both axes, BG2 = camera - vortex counter
#
# Borrowing B40A to kill the vortex drift therefore traded the drift for a
# quarter-rate VERTICAL: on a 12px jump the fighters and their shadows drop 12px
# while the ground drops 3 -- the reported slide. (Stage 0 does the same in
# vanilla; nobody notices, because its ground is a flat grass field with no
# feature at the fighters' feet, while the ported stage has a hard perspective
# floor line exactly there.)
#
# Fix: keep B40A's horizontal treatment, restore stage 2's own 1:1 vertical, in
# a routine written over the vortex -- which only stage 2 selects, so no other
# stage can see it, and the pointer at $C0:B32F is then left alone.
GROUND_TRACKS_CAMERA = False
SCROLL_CODE = 0x00B454        # the vortex routine's body; code runs to $B4C0,
                              # data (its HDMA table) starts at $B4C1
SCROLL_CODE_OLD = bytes.fromhex("c220ad000a38ed180a8500")   # its first 11 bytes
SCROLL_CODE_NEW = bytes.fromhex(
    "c220"          # rep #$20
    "ad000a"        # lda $0A00      camera x
    "8d240a"        # sta $0A24
    "4a4a"          # lsr a : lsr a
    "8d180a"        # sta $0A18      BG1 h = camera/4
    "8d1c0a"        # sta $0A1C      BG2 h = camera/4  (same as BG1: the two
    "8d200a"        # sta $0A20       planes must not drift horizontally)
    "ad020a"        # lda $0A02      camera y
    "8d260a"        # sta $0A26
    "8d1a0a"        # sta $0A1A      BG1 v = camera 1:1   — the ground tracks
    "4a4a"          # lsr a : lsr a    the fighters (they stay planted)
    "8d1e0a"        # sta $0A1E      BG2 v = camera/4     — the palace parallax,
    "8d220a"        # sta $0A22        Super S's own rate (+4 px at the apex)
    "60")           # rts

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
    return parse_script(rom, base, idx, bank_file)[:2]


def parse_script(rom, base, idx, bank_file):
    """Full scene script: -> (records, palettes, third list, tail bytes, offset).

    The script does NOT end at the palette list. Measured at $C0:85C8-$85FC, it
    is FOUR parts:

        [record ids .. FF][palette ids .. FF][third list .. FF][$6F][$8F][$A2]

    and those last three bytes are the per-stage configuration. **`$8F` is the
    sprite-attribute byte**: `0x18` on the nine SMS stages that draw the
    fighters at OBJ priority 3, `0x10` on stage 2 — the one slot this port
    targets, and the only stage in the game whose fighters sit at priority 2.
    It is mirrored into each player's +0x08.

    That single byte is behind the whole layering saga. At priority 2 a BG tile
    with the priority bit draws in FRONT of the fighters, which is the original
    "the castle covers everything below their chests" report; that is why the
    port stripped the priority bits, which cost it the third depth (sky <
    palace < ground), which is why the palace could not be given its own
    parallax without either burying the sky or blacking out its own edges.

    SMS's OWN Silver Millennium (scene 1) is the same stage and composes it the
    same way as Super S does — sky BG1.0, palace BG2.1, ground BG1.1 — and its
    script tail reads `a0 18 0a`. Super S scene 1's reads `a0 18 00`. So the
    port has to carry the script tail across, not just the art.
    """
    p = rom[bank_file + base + idx * 2] | rom[bank_file + base + idx * 2 + 1] << 8
    o = start = bank_file + p
    out = []
    for _ in range(3):
        lst = []
        while rom[o] != 0xFF:
            lst.append(rom[o]); o += 1
        o += 1
        out.append(lst)
    tail = (rom[o], rom[o + 1], rom[o + 2])
    return out[0], out[1], out[2], tail, start


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
        if MAP1_SHIFT and vram == 0x0800:
            m = bytearray(raw)
            for row in range(32):                    # 64x32 entries, 2 bytes each
                o = row * 128
                sh = (MAP1_SHIFT % 64) * 2
                m[o:o + 128] = m[o + sh:o + 128] + m[o:o + sh]
            raw = bytes(m)
            print(f"    (rotated the far tilemap by {MAP1_SHIFT} tiles)")
        blobs.append((raw, vram))
        print(f"  supers job {j:2d}: {len(raw):#07x} bytes -> VRAM {vram:04X}")

    # --- re-cut the two planes (see PLANE_SPLIT / MERGE_GROUND) ---
    if PLANE_SPLIT:
        idx = {v: i for i, (_r, v) in enumerate(blobs)}
        if 0x0000 in idx and 0x0800 in idx:
            src = bytearray(blobs[idx[0x0000]][0])      # sky + palace + ground
            other = bytearray(blobs[idx[0x0800]][0])    # a small foreground block
            front = bytearray(len(src))                 # ground only
            back = bytearray(src)                       # sky + palace
            moved = 0
            for k in range(0, len(src), 2):
                if src[k + 1] & 0x20:                   # priority = in front of the palace
                    front[k:k + 2] = src[k:k + 2]
                    back[k:k + 2] = b"\x00\x00"
                    moved += 1
            # The PALACE is in the second map, not the first — and the first map
            # (sky) has no blank cells, so a "fill the gaps" merge silently threw
            # the whole palace away and the stage rendered as bare sky. The
            # second map wins wherever it has a tile: it is the nearer art.
            kept = 0
            for k in range(0, len(other), 2):
                if (other[k] | other[k + 1] << 8) & 0x3FF:
                    back[k:k + 2] = other[k:k + 2]
                    kept += 1
            blobs[idx[0x0000]] = (bytes(front), 0x0000)
            blobs[idx[0x0800]] = (bytes(back), 0x0800)
            print(f"    (plane split: {moved} ground cells to BG1, sky+palace to BG2, "
                  f"{kept} cells kept from the second map)")
    elif MERGE_GROUND:
        idx = {v: i for i, (_r, v) in enumerate(blobs)}
        if 0x0000 in idx and 0x0800 in idx:
            near = bytearray(blobs[idx[0x0000]][0])     # sky + ground
            far = bytearray(blobs[idx[0x0800]][0])      # palace
            moved = 0
            for k in range(0, len(near), 2):
                if near[k + 1] & 0x20:                  # high-priority = ground
                    far[k:k + 2] = near[k:k + 2]        # draw it on the front plane
                    near[k:k + 2] = b"\x00\x00"         # and blank it behind
                    moved += 1
            blobs[idx[0x0000]] = (bytes(near), 0x0000)
            blobs[idx[0x0800]] = (bytes(far), 0x0800)
            print(f"    (moved {moved} ground cells onto the front plane)")

    if STRIP_PRIORITY:
        for i, (raw, vram) in enumerate(blobs):
            if vram not in (0x0000, 0x0800):
                continue
            m = bytearray(raw)
            n = 0
            for k in range(1, len(m), 2):
                if m[k] & 0x20:
                    m[k] &= ~0x20
                    n += 1
            if n:
                print(f"    (cleared the priority bit on {n} entries)")
            blobs[i] = (bytes(m), vram)

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
    if PORT_SCRIPT_TAIL:
        _sr, _sp, s_third, s_tail, _so = parse_script(sup, SUP_SCENES, SUPERS_SCENE, E0)
        d_recs, d_pals, d_third, d_tail, d_off = parse_script(bytes(data), 0x017A, SMS_STAGE, E0)
        # (no length check: only $8F is copied, and it is found by walking
        # SMS's own three lists, so the two scripts need not be the same shape)
        # ONLY $8F. The third list and the other two tail bytes are SMS
        # resource ids / SMS-side config: copying Super S's numbers over them
        # hangs the round load (measured — the match never starts), exactly like
        # the record and palette ids, which is why those are kept as SMS's and
        # only their DATA is repointed.
        o = d_off + len(d_recs) + 1 + len(d_pals) + 1 + len(d_third) + 1
        data[o + 1] = s_tail[1]
        if PORT_A2:
            data[o + 2] = s_tail[2]
            print(f"  scene script tail: $A2 {d_tail[2]:02X} -> {s_tail[2]:02X} (PORT_A2)")
        print(f"  scene script tail: $8F {d_tail[1]:02X} -> {s_tail[1]:02X} "
              f"= fighters at OBJ priority {(d_tail[1] >> 3) & 3} -> "
              f"{(s_tail[1] >> 3) & 3} (SMS's own Silver Millennium, scene 1, "
              f"also uses 18); $6F and $A2 and the third list left as SMS's")
    recs = [r for r in recs if r != 4]
    if len(recs) != 3:
        raise SystemExit(f"SMS scene {SMS_STAGE} is not a 3-asset stage: {recs}")
    order = list(range(len(recs)))
    if SWAP_MAPS and not PLANE_SPLIT:
        maps = [i for i, (_r, v) in enumerate(blobs) if v in (0x0000, 0x0800)]
        if len(maps) == 2:
            order[maps[0]], order[maps[1]] = order[maps[1]], order[maps[0]]
            print("  (tilemaps swapped between planes)")
    addrs = [addrs[i] for i in order]
    blobs = [blobs[i] for i in order]
    for r, (blobaddr, (raw, vram)) in zip(recs, zip(addrs, blobs)):
        o = E0 + SMS_RECORDS + r * 6
        old_vram = data[o + 3] | data[o + 4] << 8
        if old_vram != vram and not (SWAP_MAPS and {old_vram, vram} == {0x0000, 0x0800}):
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

    # scroll routine (see SCROLL_PTR / GROUND_TRACKS_CAMERA)
    if GROUND_TRACKS_CAMERA:
        got = bytes(data[SCROLL_CODE:SCROLL_CODE + len(SCROLL_CODE_OLD)])
        if got != SCROLL_CODE_OLD:
            raise SystemExit(f"scroll routine @{SCROLL_CODE:#08x}: found {got.hex()}, "
                             f"expected {SCROLL_CODE_OLD.hex()}")
        if SCROLL_CODE + len(SCROLL_CODE_NEW) > 0x00B4C1:
            raise SystemExit("scroll routine would run into the vortex HDMA table at $B4C1")
        data[SCROLL_CODE:SCROLL_CODE + len(SCROLL_CODE_NEW)] = SCROLL_CODE_NEW
        print(f"  scroll routine: $C0:B454 rewritten in place "
              f"({len(SCROLL_CODE_NEW)} B) — BG1 h = camera/4, BG1 v = camera 1:1")
    elif SCROLL_PTR_NEW is None:
        print("  scroll routine: left as SMS stage 2's vortex "
              "(the source scene drifts a plane too)")
    else:
        got = bytes(data[SCROLL_PTR:SCROLL_PTR + 2])
        if got != SCROLL_PTR_OLD:
            raise SystemExit(f"scroll pointer @{SCROLL_PTR:#08x}: found {got.hex()}, "
                             f"expected {SCROLL_PTR_OLD.hex()}")
        data[SCROLL_PTR:SCROLL_PTR + 2] = SCROLL_PTR_NEW
        print(f"  scroll routine: $C0:B454 (vortex) -> $C0:{_SCROLL_TARGET:04X}"
              f"   [{SUPERS_STAGES.get(SUPERS_SCENE, ('?',))[0]}]")

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
