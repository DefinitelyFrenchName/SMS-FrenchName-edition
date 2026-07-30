#!/usr/bin/env python3
"""mksaturn_smoke.py — Saturn-in-SMS SMOKE-TEST ROM (Route A scaffold, NOT a patch).

Injects Saturn's three animation layers + a benign engine hook into a clean SMS ROM
so that an object with her new id animates idle/walk in a live match (poked by
tools/probe_sms_saturn_smoke.lua — she is NOT on the char select).

Design (docs/saturn/supers_map.md §pipeline + §Character architecture):
  * Saturn takes OBJECT ID 0x1C (28) — free in SMS's object-id namespace
    ($C0:0000 script-table ids 28..47 are zero; ids 10-27 are projectiles).
  * The three data layers can't extend in place (tables end flush against data),
    so each layer's whole region is COPIED into an appended bank and the engine's
    data-bank byte + table-base operands are patched (1-3 bytes per layer):
      $E8: $C0:0000-0x2200 script region copy + widened id->acttable entry
           + Saturn act table & scripts (CMD steps STRIPPED — the SMS interpreter
           $80:A05C has no 0xC0 case) + the recognizer-guard stub
      $E9: $84:8000-0x9400 pose-record region copy + widened table @ $9E00
           + Saturn records @ $9E40 (guard-fix bytes APPLIED — ships-fixed policy)
      $EA: $CB:0000-0x2000 cel-table region copy + widened table @ $2000
           + Saturn pose->cels @ $2100 + cel records @ $2210 (addr24 rebased)
      $EB/$EC/$ED: her cel blobs at the SAME in-bank offsets as Super S
           ($DD/$DE/$DF -> bank-delta rebase; DMA A-bus wraps at bank bounds)
  * Recognizer dispatch $C1:125F walks a garbage list for beyond-table ids and
    stomps struct bytes -> 11-byte head hooked with JSL to a bank-$E8 stub that
    returns an empty list ($C1:0AFD = FF FF FF FF) for id 0x1C.

NOT covered (smoke scope; tolerated garbage or unused paths):
  boxes ($8A ptr tables — hurt/coll garbage for id 0x1C; no attacks in smoke),
  button-map table $169B (garbage record; probe presses no buttons/double-taps),
  palettes (Uranus's), char-select/loader, sound. See NEXT_SESSION for the list.

Usage: python3 tools/mksaturn_smoke.py <out.sfc>   (reads clean SMS + Super S ROMs)
"""
import sys
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, supers_rom, require_source, SUPERS_SHA1, \
    fix_checksum, next_bank, write_bank  # noqa: E402
import hashlib  # noqa: E402
import extract_saturn_unit as X  # noqa: E402  (source addresses + script parser)

SAT_ID = 0x1C

# ---- SMS patch sites (all byte-asserted before writing) ----
SITE_INTERP_DB = 0x0A079      # $80:A078 lda #$C0 -> #$E8
SITE_POSE_DB = 0x09C9E        # $C0:9C9D lda #$84 -> #$E9
SITE_POSE_TBL = 0x09CB2       # $C0:9CB1 lda $809C,Y -> $9E00,Y
SITE_CEL_DB = 0x09FC1         # $C0:9FC0 lda #$CB -> #$EA
SITE_CEL_T1 = 0x09FCF         # $C0:9FCE lda $0000,Y -> $2000,Y
SITE_CEL_T2 = 0x09FD4         # $C0:9FD3 lda $0002,Y -> $2002,Y
SITE_RECOG = 0x1125F          # $C1:125F 11-byte head -> JSL stub + NOPs
RECOG_HEAD = bytes.fromhex("B50029FF000AA8B9C713A8")
EMPTY_LIST = 0x0AFD           # $C1:0AFD..0B04 = 8x FF (verified)
# Her REAL proc block (ported 2026-07-30, tools/port_saturn_proc.py): grafted into
# bank $EF = full SMS-$C1 copy + her block at its Super S in-bank offsets
# ($C6F7-$DC00 window; self-contained incl. data pockets $C806-C922/$D9F3-DA3B).
# Entry: 7-byte hook at the main dispatch $C1:007C -> JSL $EF:helper; helper routes
# id 0x1C to her dispatch (PB=$EF: engine jsr's hit the copied SMS routines, her
# records read via phk/plb readers resolve to the graft) and everything else back
# through a 4-byte $C1 stub (jsr ($00A6,X)/rtl) in the $C1:0AFD FF-run tail.
SITE_PROC_HOOK = 0x1007C      # $C1:007C: sep #$30 / asl / tax / jsr ($00A6,X)
PROC_HOOK_OLD = bytes.fromhex("E2300AAAFCA600")
STUB2 = 0x0B01                # $C1:0B01 (last 4 FF of the 0AFD run)
EF_HELPER = 0xDB00            # in-bank, inside the graft window, past block end
# Her specials spawn projectile OBJECTS with Super S ids (0x20 qcf LP/HP, 0x22,
# possibly more) — all in SMS's free id range 0x1D-0x2F. Until the projectile
# objects are ported (7-table units each), EVERY free-id proc entry points at the
# engine's despawn tail (stz $00,X / rts @ $C1:0E23) so spawns self-clear and her
# "wait for projectile" act handlers complete. TODO: full projectile port.
PROJ_IDS = [i for i in range(0x1D, 0x30)]
PROJ_DESPAWN = 0x0E23
# 4th layer: OAM sprite-layout. Renderer $C0:9A0E walks the draw list with DB=$84
# (lda #$84 @ $C0:9A29): char table $84:8000, 3B/id [ptr16, bank] -> per-pose word ->
# [count, 6B sprite records]. Saturn's Super S blob: $87:8000-$87:BE5E (15.6 KB,
# in-bank-absolute pointers -> same in-bank offset in a fresh bank, zero rebase).
# NOTE: the renderer's DB CANNOT be swapped to an appended bank — its low half
# must mirror WRAM (draw list $0B00, structs) which only banks $80-$BF do. Saturn's
# entry is instead written into the ORIGINAL table (slot 0x1C is an unused id).
OAM_BLOB_LO, OAM_BLOB_HI = 0x078000, 0x07BE5E
SITE_OAM_ENTRY = 0x048000 + 3 * SAT_ID          # $84:8054 (unused id slot)

# in-bank layout of the appended banks
E8_SATURN_ACTTBL = 0x2200     # 128-word act table, then scripts
E8_STUB = 0x2700
E9_TABLE, E9_RECORDS = 0x9E00, 0x9E40
EA_TABLE, EA_P2C, EA_CELREC = 0x2000, 0x2100, 0x2210


def build_saturn_scripts(sup, new_base):
    """Rebuild Saturn's act table + scripts with CMD steps stripped, rebased so the
    act table sits at new_base (script bytes follow it)."""
    table = []
    for act in range(128):
        w = sup[X.SCRIPTS_LO + 2 * act] | sup[X.SCRIPTS_LO + 2 * act + 1] << 8
        table.append(w)
    out = bytearray(256)                     # act table placeholder
    ptrs = {}
    for act, w in enumerate(table):
        if not w or not (0x2205 <= w < 0x252B):
            continue
        if w not in ptrs:                    # scripts may be shared between acts
            steps, _ = X.parse_script(sup, w)
            blob = bytearray()
            for kind, a, b in steps:
                if kind == "cmd":
                    continue                 # SMS interpreter has no CMD case
                if kind == "step":
                    blob += bytes((a - 1, b))
                elif kind == "loop":
                    blob.append(0x40 | a)
                elif kind == "hold":
                    blob.append(a)
            if not blob or blob == b"\x80":  # CMD-only scripts degrade to bare hold
                blob = bytearray((0x80,))
            ptrs[w] = new_base + len(out)
            out += blob
        pass
    for act, w in enumerate(table):
        p = ptrs.get(w, 0)
        out[2 * act] = p & 0xFF
        out[2 * act + 1] = p >> 8
    return bytes(out), len(ptrs)


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__.strip().splitlines()[-1])
    out_path = sys.argv[1]

    sms_path = clean_rom()
    require_source(sms_path)                 # smoke always builds from clean
    data = bytearray(open(sms_path, "rb").read())
    sup = open(supers_rom(), "rb").read()
    if len(sup) % 0x8000 == 0x200:
        sup = sup[0x200:]
    if hashlib.sha1(sup).hexdigest() != SUPERS_SHA1:
        raise SystemExit("error: Super S ROM sha1 mismatch")

    def expect(off, want, what):
        got = bytes(data[off:off + len(want)])
        if got != want:
            raise SystemExit(f"error: {what} @ {off:#x}: found {got.hex()} "
                             f"expected {want.hex()}")

    expect(SITE_INTERP_DB - 1, b"\xA9\xC0", "interpreter DB load")
    expect(SITE_POSE_DB - 1, b"\xA9\x84", "pose-writer DB load")
    expect(SITE_POSE_TBL - 1, b"\xB9\x9C\x80", "pose-table read")
    expect(SITE_CEL_DB - 1, b"\xA9\xCB", "cel-resolver DB load")
    expect(SITE_CEL_T1 - 1, b"\xB9\x00\x00", "cel-table read 1")
    expect(SITE_CEL_T2 - 1, b"\xB9\x02\x00", "cel-table read 2")
    expect(SITE_RECOG, RECOG_HEAD, "recognizer dispatch head")
    expect(0x10000 + EMPTY_LIST, b"\xFF" * 8, "empty-list FF run")

    # ---- bank $E8: scripts ----
    bankbase, bank = next_bank(data)
    assert bank == 0xE8, f"first free bank is ${bank:02X}, expected $E8 (clean src)"
    e8 = bytearray(data[0x00000:0x02200])            # $C0 script region copy
    e8 += bytes(E8_SATURN_ACTTBL - len(e8))
    sat_tbl, nscripts = build_saturn_scripts(sup, E8_SATURN_ACTTBL)
    e8 += sat_tbl
    assert len(e8) <= E8_STUB, "Saturn scripts overrun the stub slot"
    e8 += bytes(E8_STUB - len(e8))
    # lda $00,X / and #$00FF / cmp #SAT_ID / beq sat / asl / tay / lda $13C7,Y
    # / tay / rtl / sat: lda #EMPTY_LIST / tay / rtl        (M=0 at the hook site)
    stub = bytes.fromhex("B50029FF00C91C00F0070AA8B9C713A86B") \
        + bytes((0xA9, EMPTY_LIST & 0xFF, EMPTY_LIST >> 8, 0xA8, 0x6B))
    e8 += stub
    e8[2 * SAT_ID] = E8_SATURN_ACTTBL & 0xFF          # id -> act-table entry
    e8[2 * SAT_ID + 1] = E8_SATURN_ACTTBL >> 8
    write_bank(data, bankbase, bytes(e8))

    # ---- bank $E9: pose records ----
    bankbase, bank = next_bank(data)
    e9 = bytearray(0x10000)
    e9[0x8000:0x9400] = data[0x048000:0x049400]       # $84 region copy
    e9[E9_TABLE:E9_TABLE + 56] = data[0x04809C:0x04809C + 56]  # 28 entries
    e9[E9_TABLE + 2 * SAT_ID] = E9_RECORDS & 0xFF
    e9[E9_TABLE + 2 * SAT_ID + 1] = E9_RECORDS >> 8
    poses = bytearray(sup[X.POSES_LO:X.POSES_HI])
    for off, _pose, van, fix in X.GUARDFIX:           # ships-fixed policy
        assert poses[off] == van
        poses[off] = fix
    e9[E9_RECORDS:E9_RECORDS + len(poses)] = poses
    write_bank(data, bankbase, bytes(e9))

    # ---- bank $EA: cel tables ----
    bankbase, bank = next_bank(data)
    ea = bytearray(0x10000)
    ea[0x0000:0x2000] = data[0x0B0000:0x0B2000]       # $CB region copy
    ea[EA_TABLE:EA_TABLE + 40] = data[0x0B0000:0x0B0000 + 40]
    ent = EA_TABLE + 4 * SAT_ID
    ea[ent:ent + 4] = bytes((EA_P2C & 0xFF, EA_P2C >> 8, EA_CELREC & 0xFF, EA_CELREC >> 8))
    ea[EA_P2C:EA_P2C + (X.P2C_HI - X.P2C_LO)] = sup[X.P2C_LO:X.P2C_HI]
    crec = bytearray(sup[X.CELREC_LO:X.CELREC_LO + X.NCELS * 5])
    bankmap = {0xDD: 0xEB, 0xDE: 0xEC, 0xDF: 0xED}
    for c in range(X.NCELS):
        sz = crec[5 * c + 3] | crec[5 * c + 4] << 8
        if sz == 0:
            continue
        crec[5 * c + 2] = bankmap[crec[5 * c + 2]]    # addr24 bank-delta rebase
    ea[EA_CELREC:EA_CELREC + len(crec)] = crec
    write_bank(data, bankbase, bytes(ea))

    # ---- banks $EB/$EC/$ED: cel blobs at preserved in-bank offsets ----
    for tag, (srcbank, lo, hi) in X.CEL_SPANS.items():
        bankbase, bank = next_bank(data)
        assert bank == bankmap[srcbank], f"bank layout drift: ${bank:02X}"
        blob = bytes(lo) + sup[(srcbank & 0x3F) << 16 | lo:(srcbank & 0x3F) << 16 | hi]
        write_bank(data, bankbase, blob)
        if len(blob) < 0x10000:                       # pad the bank
            pad = 0x10000 - len(blob)
            data[bankbase + len(blob):bankbase + 0x10000] = bytes(pad)

    # ---- bank $EE: OAM sprite-layout blob at in-bank 0x8000 ----
    bankbase, bank = next_bank(data)
    assert bank == 0xEE, f"bank layout drift: ${bank:02X}"
    write_bank(data, bankbase, bytes(0x8000) + sup[OAM_BLOB_LO:OAM_BLOB_HI])
    pad = 0x10000 - 0x8000 - (OAM_BLOB_HI - OAM_BLOB_LO)
    data[bankbase + 0x10000 - pad:bankbase + 0x10000] = bytes(pad)

    # ---- bank $EF: full SMS-$C1 copy + Saturn's ported proc block ----
    import port_saturn_proc as PSP
    blk, rep = PSP.patched_block(sup, bytes(data[:0x280000]))
    if rep["unresolved"]:
        raise SystemExit(f"error: proc port has unresolved refs: {rep['unresolved']}")
    bankbase, bank = next_bank(data)
    assert bank == 0xEF, f"bank layout drift: ${bank:02X}"
    ef = bytearray(data[0x10000:0x20000])            # SMS bank $C1 copy (pre-patch)
    ef[PSP.BLOCK_LO:PSP.BLOCK_HI] = blk
    # helper: sep #$30 / cmp #SAT_ID / beq sat / asl / tax / JSL $C1:stub2 / rtl
    #         sat: jsr $C6F7 / rtl          (entered with 8-bit A=id via the hook)
    helper = bytes.fromhex("E230C91CF0070AAA") + \
        bytes((0x22, STUB2 & 0xFF, STUB2 >> 8, 0xC1, 0x6B, 0x20, 0xF7, 0xC6, 0x6B))
    ef[EF_HELPER:EF_HELPER + len(helper)] = helper
    write_bank(data, bankbase, bytes(ef))

    # ---- engine patches ----
    data[SITE_INTERP_DB] = 0xE8
    # bank byte $AE (not $EE): the emitter WRITES the OAM shadow via DB-absolute
    # $0200,X — only $80-$BF banks mirror WRAM in the low half; $AE:8000+ mirrors
    # the same ROM bytes as $EE:8000+ (file 0x2E8000).
    data[SITE_OAM_ENTRY:SITE_OAM_ENTRY + 3] = bytes((0x00, 0x80, 0xAE))  # -> $AE:8000
    data[SITE_POSE_DB] = 0xE9
    data[SITE_POSE_TBL:SITE_POSE_TBL + 2] = bytes((E9_TABLE & 0xFF, E9_TABLE >> 8))
    data[SITE_CEL_DB] = 0xEA
    data[SITE_CEL_T1:SITE_CEL_T1 + 2] = bytes((EA_TABLE & 0xFF, EA_TABLE >> 8))
    data[SITE_CEL_T2:SITE_CEL_T2 + 2] = bytes(((EA_TABLE + 2) & 0xFF, (EA_TABLE + 2) >> 8))
    hook = bytes((0x22, E8_STUB & 0xFF, E8_STUB >> 8, 0xE8)) + b"\xEA" * 7
    data[SITE_RECOG:SITE_RECOG + 11] = hook
    expect(SITE_PROC_HOOK, PROC_HOOK_OLD, "main proc-dispatch head")
    data[SITE_PROC_HOOK:SITE_PROC_HOOK + 7] = \
        bytes((0x22, EF_HELPER & 0xFF, EF_HELPER >> 8, 0xEF)) + b"\xEA" * 3
    expect(0x10000 + STUB2, b"\xFF\xFF\xFF\xFF", "stub2 slot (FF-run tail)")
    data[0x10000 + STUB2:0x10000 + STUB2 + 4] = bytes.fromhex("FCA6006B")
    expect(0x10000 + PROJ_DESPAWN, bytes.fromhex("740060"), "despawn tail")
    for pid in PROJ_IDS:
        site = 0x100A6 + 2 * pid
        expect(site, b"\x00\x00", f"proc-table entry {pid:#04x} (must be free)")
        data[site:site + 2] = bytes((PROJ_DESPAWN & 0xFF, PROJ_DESPAWN >> 8))

    fix_checksum(data)
    open(out_path, "wb").write(data)
    print(f"wrote {out_path}: {len(data):#x} bytes, Saturn object id {SAT_ID:#04x}, "
          f"{nscripts} scripts (CMD-stripped)")
    print("sha1", hashlib.sha1(bytes(data)).hexdigest())


if __name__ == "__main__":
    main()
