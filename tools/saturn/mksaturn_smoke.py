#!/usr/bin/env python3
"""mksaturn_smoke.py — Saturn-in-SMS SMOKE-TEST ROM (Route A scaffold, NOT a patch).

Injects Saturn's three animation layers + a benign engine hook into a clean SMS ROM
so that an object with her new id animates idle/walk in a live match (poked by
tools/saturn/probe_sms_saturn_smoke.lua — she is NOT on the char select).

Design (docs/saturn/supers_map.md §pipeline + §Character architecture):
  * Saturn takes OBJECT ID 0x1C (28) — free in SMS's object-id namespace
    ($C0:0000 script-table ids 28..47 are zero; ids 10-27 are projectiles).
  * The three data layers can't extend in place (tables end flush against data),
    so each layer's whole region is COPIED into an appended bank and the engine's
    data-bank byte + table-base operands are patched (1-3 bytes per layer):
      $E8: $C0:0000-0x2800 FULL script region copy (v0.10.0: vanilla story-mode
           scripts reach 0x2800!) + widened id->acttable entry + Saturn act
           table & scripts above the stubs + the recognizer-guard stub
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

Usage: python3 tools/saturn/mksaturn_smoke.py <out.sfc>   (reads clean SMS + Super S ROMs)
"""
import sys
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, supers_rom, require_source, SUPERS_SHA1, \
    fix_checksum, next_bank, write_bank  # noqa: E402
import hashlib  # noqa: E402
import extract_saturn_unit as X  # noqa: E402  (source addresses + script parser)

# Build version (semver). Bump MINOR per feature batch, PATCH per fix; registry
# with per-version contents + ROM SHAs: docs/saturn/BUILDS.md. The version is
# embedded at $EE:C040 (ASCII, 0-terminated) and shown on-screen by
# tools/saturn/saturn_test.lua — the naked-eye tell for regression reports.
SATURN_VERSION = "0.11.2"

# Build variant (maintainer request 2026-07-31, "hidden like Gouki in SF2"):
#   default        -> VISIBLE slot 10 on the select screen (0.10.0 behavior)
#   SATURN_HIDDEN=1 -> NO visible trace (no marker sprite, no navigable slot);
#                      instead HOLD L+R WHILE CONFIRMING any character at the
#                      select screen -> that character becomes Saturn at round
#                      load. Every confirm press re-decides (no code held =
#                      flag cleared), so stale flags self-clean per select.
#                      The physical pad is chosen from the confirm handler's
#                      own [$FE] pad pointer ($60=P1 pad, $62=P2 pad), so in
#                      practice mode P1 holding L+R while confirming the DUMMY
#                      correctly makes the dummy Saturn. L+R-at-load and the
#                      0.10.0 latent-bug fixes are in BOTH variants.
# Ship-time balance call: keep whichever variant fits (filenames + version
# strings differ: v<ver> vs v<ver>-hidden / "SATURN v<ver>H").
import os as _osv
SATURN_HIDDEN = _osv.environ.get("SATURN_HIDDEN") == "1"
VARIANT_FILE = f"{SATURN_VERSION}-hidden" if SATURN_HIDDEN else SATURN_VERSION
VARIANT_STR = SATURN_VERSION + ("H" if SATURN_HIDDEN else "")

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
# Her REAL proc block (ported 2026-07-30, tools/saturn/port_saturn_proc.py): grafted into
# bank $EF = full SMS-$C1 copy + her block at its Super S in-bank offsets
# ($C6F7-$DC00 window; self-contained incl. data pockets $C806-C922/$D9F3-DA3B).
# Entry: 7-byte hook at the main dispatch $C1:007C -> JSL $EF:helper; helper routes
# id 0x1C to her dispatch (PB=$EF: engine jsr's hit the copied SMS routines, her
# records read via phk/plb readers resolve to the graft) and everything else back
# through a 4-byte $C1 stub (jsr ($00A6,X)/rtl) in the $C1:0AFD FF-run tail.
SITE_PROC_HOOK = 0x1007C      # $C1:007C: sep #$30 / asl / tax / jsr ($00A6,X)
PROC_HOOK_OLD = bytes.fromhex("E2300AAAFCA600")
STUB2 = 0x0B01                # $C1:0B01 (last 4 FF of the 0AFD run)
EF_HELPER = 0xDB70            # in-bank, clear of tramp(DB20)/tramp3(DB30)/snd(DB50)
# Her specials spawn projectile OBJECTS with Super S ids (0x20 qcf LP/HP, 0x22,
# possibly more) — all in SMS's free id range 0x1D-0x2F. Until the projectile
# objects are ported (7-table units each), EVERY free-id proc entry points at the
# engine's despawn tail (stz $00,X / rts @ $C1:0E23) so spawns self-clear and her
# "wait for projectile" act handlers complete. TODO: full projectile port.
PROJ_IDS = [i for i in range(0x1D, 0x30)]
PROJ_DESPAWN = 0x0E23
# Button-map hook: same 11-byte head shape as the recognizer dispatch, at $C1:15C4.
# Both hooks use RETURN-ADDRESS SURGERY (stub adds N to the JSL return on the
# stack): the 7 post-JSL bytes never execute -> the recognizer hook's 7 bytes at
# $C1:1263 hold Saturn's BUTTON RECORD (02 00 04 08 06 00 0a) as pure data.
SITE_BTN = 0x115C4
BTN_HEAD = bytes.fromhex("B50029FF000AA8B99B16A8")
BTN_RECORD_ADDR = 0x1263            # = the recognizer hook's data slot
SATURN_BTN_RECORD = bytes.fromhex("0200040806000A")
E8_BTNSTUB = 0x2840
# Recognizer graft: her payload ($C1:1452-1615 Super S) goes into the $EF copy at
# original offsets; copied table entry [0x1C] ($EF:13FF) -> $1452; the recognizer
# stub runs the FULL copied dispatch via an $EF trampoline (balanced phb/plb) and
# skips the real dispatch remainder entirely (surgery +0x26 to $C1:1289 plb/rts).
# v0.11.2: HI was 0x011616 — but spec5 (the desperation, 412364+HP) is the
# longest record: 7 pairs + FF ending at 0x161A inclusive. The truncation left
# its pair index 5 reading SMS-copy leftovers at $EF:1616 -> the matcher's
# hold path parked the timer at 0 forever = the long-standing "rec5 freezes at
# [00,05]" mystery. ($EF:1616-161A in the SMS copy is dead code tail of SMS's
# own button handler, never executed from $EF - safe to overwrite.)
RECOG_PAYLOAD_LO, RECOG_PAYLOAD_HI = 0x011452, 0x01161B
EF_TRAMP = 0xDB20
# Sound: SMS sfx API = one-shot WRAM slots forwarded to the APU by NMI ($C0:D4F2):
# DP $78 = effect channel (whoosh 0x05 light / 0x06 heavy), $1078/$10F8 = per-
# player voice. Super S instead calls a command handler ($80:FBB0->FBB4, no SMS
# twin); her blocks' JSLs (mapped to a bare RTL by the port) are re-pointed to a
# translator at $EF:DB50 that plays an SMS sfx for known command ids and stays
# silent otherwise. Normals' whooshes were script CMD steps (stripped) — their
# restoration needs an interpreter CMD back-port: TODO, see BUILDS.md gaps.
SND_MAP = {0x0E: 0x06, 0x20: 0x06}   # her special-move command ids -> SMS heavy whoosh
EF_SND = 0xDB50
# Interpreter CMD back-port: the SMS interpreter lacks Super S's 0xC0 command
# step. AUDIT (2026-07-30): all 757 SMS scripts contain NO byte >=0xC0 in a
# duration/ctrl position -> adding the case is behavior-neutral for SMS content.
# Hook: 8 bytes at $80:A0AA (the ctrl decode) -> JSL $E8:2900 stub which decodes
# plain/hold/loop via return-address surgery and handles CMD inline (script CMD
# args translated to SMS sfx: 0x15->0x05 light whoosh, 0x14->0x06 heavy; her
# scripts are now kept CMD-INTACT for exact Super S timing).
SITE_INTERP_CMD = 0x0A0AA
INTERP_CMD_OLD = bytes.fromhex("29C0F00F2980D005")
E8_CMDSTUB = 0x2900
# v0.11.1 (field report: backdash silent): her movement sounds are script-CMD
# driven too — natively measured SMS values (probe_sms_dashsfx): dash/backdash
# whoosh 0x2D, jump 0x0C, landing 0x0D. Hit-reaction args (0x05/0x11/0x12/0x16)
# and special-starter args (0x23/0x24/0x25) stay unmapped — those sounds come
# from the engine's hit-resolution/starter paths and would double.
CMD_SND_MAP = {0x15: 0x05, 0x14: 0x06, 0x0E: 0x06, 0x20: 0x06,
               0x02: 0x0C, 0x06: 0x2D, 0x22: 0x2D, 0x08: 0x0D}
# v0.8.0 — IN-ROM SATURN SELECT (P1): hold L+R while a round loads -> flag
# $7E:1F60 set; the effects-DMA helper hook ($C0:92A4, generic VRAM-DMA kick,
# filtered on $30==0x6A00/$36==$7F) also overrides the $7F:0000 staging with her
# raw tiles ($EE:D000, embedded from traces/saturn/supers_effecttiles.bin when
# present); the $EF proc helper transforms P1 at neutral + injects her palette.
# Hold SELECT at a round load to clear. Flag persists across rounds. P2 stays
# Lua-only (its effect-buffer layout unmapped).
SITE_DMA_KICK = 0x092A4
DMA_KICK_OLD = bytes.fromhex("A0018C00438C0B42")
E8_DMASTUB = 0x2980
SATURN_FLAG = 0x1F60      # P1; P2 flag = +1. v0.9.0: P2 in-ROM select — the same
SATURN_FLAG2 = 0x1F61     # DMA site also runs P2's effects transfer (VRAM $7300
EE_TILES = 0xD000         # <- $7F:0000 staging reused); P2 pad = $421A/B.
# v0.10.0 FIX (latent since 0.8.0): the $EF helper must NOT transform on the
# user flag directly — story-mode load screens pass its act/$1FA gates on
# non-fight actors, and a flag set BEFORE the load (char-select pick, or a
# stale flag from an earlier match) crashed the story sequencer (pc -> $FFB0).
# The L+R path never hit this only because the DMA stub sets the flag exactly
# at the effects transfer, which is AFTER that window. So the DMA stub now
# latches flag -> per-round ARM ($1F62/63) at that proven-safe moment, and the
# helper transforms on the latch. Pre-set flags thereby behave exactly like
# held-L+R: they take effect at the shell char's effects DMA, never earlier.
SATURN_LATCH = 0x1F62     # P1 armed-this-round latch; P2 = +1
SATURN_LATCH2 = 0x1F63
# v0.10.0 — CHAR-SELECT 10TH SLOT (placeholder graphic): the select screen is a
# group photo with table-driven spatial cursor movement. Decoded (charsel probes
# 2026-07-31, code runs from the $80 FastROM mirror):
#   move-t1 $C0:A58E  nav table $AA4D (10 rows x [up,down,left,right] charID)
#                     — serves BOTH cursors in VS AND practice (Y=$1B40/$1B80)
#   move-t2 $C0:A5DF  nav table $AA75 — story/vs-CPU single cursor only
#   draw-blk1/2a/2b/2c/3: cursor sprites; position tables base+charID*2 at
#     $AA9D (P1) / $AAB1 (P2/dummy) / $AAC5 (story); each table's char-0 word is
#     dead (reads are 1-indexed) = the PREVIOUS table's free char-10 slot.
#   confirm $C0:A630  per-player per-frame; buttons A/Y/Start ($5080 pad mask,
#                     normal palette) or B/X ($8040, alt palette); union $D0C0.
# Slot 10 (Saturn): t1 gains an 11th row in-place at $AA75 (t2's dead row 0 —
# story cursor never reaches 0); Chibimoon-right + Venus-down lead to it.
# STORY MODE IS DELIBERATELY EXCLUDED: t2 exists precisely to restrict the
# story roster — its rows never lead to 6/7/8 (the outer senshi are story
# bosses with no player story data; forcing cursor 6 there crashes VANILLA
# too, verified). Slot 10 (shell 6) follows the same policy, so t2/draw-blk3
# stay untouched and Saturn in 1P mode remains the L+R-at-load select.
# Confirm hook (4-byte JSL over rep #$30/lda [$FE]) translates cursor 10 ->
# shell char 6 (Uranus) + sets $1F60/$1F61 by cursor struct (Y) on the press
# frame, so ALL downstream UI/loader sees a normal Uranus pick and the proven
# round-load transform does the rest; while browsing (pre-confirm) it clears
# that player's flag so each char-select trip re-decides (L+R at load still
# overrides). A placeholder marker sprite (P1-cursor glyph, OAM slot 0x7B —
# tail slot free in all modes) parks at the empty photo spot (170,162); the
# engine clears the OAM shadow AFTER the confirm poll, so the marker is written
# by the DRAW-phase hooks (draw-blk1 for VS/practice — hooked for this purpose
# alone — and draw-blk3 for story), never by the confirm stub.
CHARSEL_DRAW1 = 0x0A77D       # sep #$30 / lda $AA9D,Y head
CHARSEL_DRAW1_OLD = bytes.fromhex("E230B99DAA")
CHARSEL_CONFIRM = 0x0A630     # rep #$30 / lda [$FE] head
CHARSEL_CONFIRM_OLD = bytes.fromhex("C230A7FE")
T1_IDX10 = 0xAA75             # t1 row 10 == t2 row 0 (dead)
T1_ID9_RIGHT = 0xAA74         # Chibimoon right: 9 -> 10
T1_ID5_DOWN = 0xAA62          # Venus down: 5 -> 10
POS1_10 = 0xAAB1              # blk1 char-10 word == blk2 char-0 (dead)
POS2_10 = 0xAAC5              # blk2 char-10 word == blk3 char-0 (dead)
SLOT10_XY = (0xAA, 0xA2)      # (170,162): bottom-right, beside Chibimoon
CHARSEL_SHELL = 0x06          # shell charID stored on confirm (Uranus)
EE_DRAW1 = 0xC1A0             # draw-blk1 reimpl (+marker call)
EE_CONFIRM = 0xC220           # confirm stub: slot-10 translation + flags
EE_MARKER = 0xC2A0            # shared marker-sprite enqueuer (jsr'd by the draws)
EE_PALCOPY = 0xC300           # transform palette copier (JSL'd by the $EF helper:
                              # fighter row -> $0600+hint($0E), effects row ->
                              # $0640; moved out of the helper in v0.11.1 — the
                              # helper's slot is only $EF:DB70-DC00 and the
                              # in-line loops overflowed it into the live C1 copy)
EMIT_GADGET = 0xA782          # jsr $9B17 / rtl — carved from dead draw-blk1 body
# Box tables: appended bank $F0 = full bank-$8A copy read via WRAM-mirror $B0
# (6x plb #$8A -> #$B0); widened ptr tables (0x30 entries) + Saturn's box data
# grafted into the copy's upper half; 7 table-read operands repointed.
BOX_PLB_SITES = (0xBFD2, 0xC004, 0xC36F, 0xC3A8, 0xC3E6, 0xC74F)
BOX_READS = {  # site -> (old operand, new operand)
    0xBFDF: (0xC1F1, 0x8100), 0xC37C: (0xC1F1, 0x8100), 0xC3B7: (0xC1F1, 0x8100),
    0xC015: (0xC229, 0x8160), 0xC3F7: (0xC229, 0x8160),
    0xC764: (0xC23D, 0x81C0), 0xC795: (0xC23D, 0x81C0),
}
F0_HIT_T, F0_HURT_T, F0_COLL_T = 0x8100, 0x8160, 0x81C0
F0_HIT_D, F0_HURT_D, F0_COLL_D = 0x8230, 0x8330, 0x8910
# 4th layer: OAM sprite-layout. Renderer $C0:9A0E walks the draw list with DB=$84
# (lda #$84 @ $C0:9A29): char table $84:8000, 3B/id [ptr16, bank] -> per-pose word ->
# [count, 6B sprite records]. Saturn's Super S blob: $87:8000-$87:BE5E (15.6 KB,
# in-bank-absolute pointers -> same in-bank offset in a fresh bank, zero rebase).
# NOTE: the renderer's DB CANNOT be swapped to an appended bank — its low half
# must mirror WRAM (draw list $0B00, structs) which only banks $80-$BF do. Saturn's
# entry is instead written into the ORIGINAL table (slot 0x1C is an unused id).
OAM_BLOB_LO, OAM_BLOB_HI = 0x078000, 0x07BE5E
SITE_OAM_ENTRY = 0x048000 + 3 * SAT_ID          # $84:8054 (unused id slot)

# in-bank layout of the appended banks.
# v0.10.0 LAYOUT FIX (latent since 0.1.0): the SMS script region does NOT end
# at 0x2200 — vanilla act-table pointers reach 0x2780 (story-mode object ids up
# to 50; script data runs to 0x2800). The old 0x2200-cut copy put Saturn's act
# table + scripts + the projectile blob on top of those bytes, so any STORY
# scene actor (e.g. Uranus's intro, act 0x22) executed garbage -> crash at
# story round load (pc -> $FFB0) in every mode-1P flow. The copy now takes the
# full 0x0000-0x2800 and everything Saturn-owned lives above the stubs.
E8_SATURN_ACTTBL = 0x2C00     # 128-word act table, then scripts (end < 0x3200)
# Projectile objects 0x20-0x22 (her fireballs): scripts are CMD-free; their
# Super S home (0x2715-0x2795) collides with SMS's own script tail, so the
# blob is RELOCATED to 0x3200 with its act-table words (bank-absolute into the
# blob) rebased by the same delta; pose records + OAM blob + hit boxes + procs
# ported alongside.
PROJ_SCRIPTS_LO, PROJ_SCRIPTS_HI = 0x2715, 0x2795
PROJ_SCRIPTS_NEW = 0x3200
PROJ_DELTA = PROJ_SCRIPTS_NEW - PROJ_SCRIPTS_LO
PROJ_SCRIPT_ENTRIES = {0x20: 0x2715 + PROJ_DELTA, 0x21: 0x2725 + PROJ_DELTA,
                       0x22: 0x2735 + PROJ_DELTA}
PROJ_POSES_LO, PROJ_POSES_N = 0x049575, 24 * 4     # $84:9575, 24 records
PROJ_OAM_LO, PROJ_OAM_HI = 0x04B4A6, 0x04B6DA      # $84:B4A6 blob (in-bank abs)
PROJ_HIT_LO, PROJ_HIT_N = 0x2FF552, 8 * 8          # $AF:F552 hit boxes
PROJ_BLOCK_LO, PROJ_BLOCK_HI = 0x280B, 0x2B60      # procs (grafted into $EF)
PROJ_PROC_ENTRIES = [0x280B, 0x28D3, 0x29A6]
E8_STUB = 0x2800
E9_TABLE, E9_RECORDS, E9_PROJ_POSES = 0x9E00, 0x9E80, 0xA080
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
                    blob += bytes((a, b))    # kept: CMD case is back-ported
                    continue
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
    if len(sys.argv) > 2:
        raise SystemExit(__doc__.strip().splitlines()[-1])
    out_path = sys.argv[1] if len(sys.argv) == 2 else \
        str(REPO / "build" / "saturn" / f"SailorMoonS_saturn_v{VARIANT_FILE}.sfc")

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
    expect(SITE_BTN, BTN_HEAD, "button-handler head")
    for site in BOX_PLB_SITES:
        expect(site, b"\xA9\x8A\x48\xAB", f"box plb site {site:#x}")
    for site, (old, new) in BOX_READS.items():
        expect(site, bytes((0xB9, old & 0xFF, old >> 8)), f"box read site {site:#x}")

    # ---- bank $E8: scripts ----
    bankbase, bank = next_bank(data)
    assert bank == 0xE8, f"first free bank is ${bank:02X}, expected $E8 (clean src)"
    e8 = bytearray(data[0x00000:0x02800])            # FULL $C0 script region copy
    # recognizer stub (M=0 at hook): id != Saturn -> skip the 7 data bytes
    # (surgery +7) and emulate the original head; id == Saturn -> skip the whole
    # real dispatch remainder (surgery +0x26 lands at $C1:1289 plb/rts) and run
    # the full COPIED dispatch in $EF (her grafted specs) via the trampoline.
    stub = (bytes.fromhex("B50029FF00C91C00F014")        # lda/and/cmp/beq sat
            + bytes.fromhex("A3011869070083 01".replace(" ", ""))  # skip data bytes
            + bytes.fromhex("B50029FF000AA8B9C713A86B")  # original head + rtl
            # sat:
            + bytes.fromhex("A3011869260083 01".replace(" ", ""))  # skip remainder
            + bytes((0x22, EF_TRAMP & 0xFF, EF_TRAMP >> 8, 0xEF, 0x6B)))
    assert len(stub) <= E8_BTNSTUB - E8_STUB, "recognizer stub overruns button stub"
    e8 += stub
    e8 += bytes(E8_STUB + (E8_BTNSTUB - E8_STUB) - len(e8))
    # button stub: skip the 7 data bytes; Saturn -> Y = her record (in the
    # recognizer hook's data slot); others -> original head
    btnstub = (bytes.fromhex("A3011869070083 01".replace(" ", ""))
               + bytes.fromhex("B50029FF00C91C00F0070AA8B99B16A86B")
               + bytes((0xA9, BTN_RECORD_ADDR & 0xFF, BTN_RECORD_ADDR >> 8, 0xA8, 0x6B)))
    e8 += btnstub
    e8 += bytes(E8_CMDSTUB - len(e8))
    # cmd stub: A=raw ctrl byte, Y=arg cursor, DB=$E8, M=1; stack: [A][PCL PCH][PB]
    def _setret(target):                 # rep/lda #target-1/sta $02,S/sep/pla/rtl
        t = target - 1
        return bytes((0xC2, 0x20, 0xA9, t & 0xFF, t >> 8, 0x83, 0x02,
                      0xE2, 0x20, 0x68, 0x6B))
    # each entry: cmp #cid / bne +4 / lda #sfx / bra store — a match jumps
    # PAST the remaining compares (v0.11.1: the old fallthrough left A=sfx in
    # the later compares; harmless for the original 4-entry map, but the
    # movement sfx values collide with cids in the 8-entry map)
    cmd_tail = bytearray()
    fx_store = []
    for cid, sfx in CMD_SND_MAP.items():
        cmd_tail += bytes((0xC9, cid, 0xD0, 0x04, 0xA9, sfx, 0x80, 0x00))
        fx_store.append(len(cmd_tail) - 1)
    for pos in fx_store:
        cmd_tail[pos] = len(cmd_tail) - (pos + 1)
    cmd_tail += bytes((0x85, 0x78))      # store: sta $78
    cmd_tail += _setret(0xA076)          # reprocess next step
    stub = bytearray()
    stub += bytes((0x48,))                               # pha
    stub += bytes((0x29, 0xC0, 0xC9, 0xC0, 0xF0, 0x00))  # and/cmp #$C0/beq cmd
    fx_cmd = len(stub) - 1
    stub += bytes((0xC9, 0x80, 0xF0, 0x00))              # cmp #$80/beq hold
    fx_hold = len(stub) - 1
    stub += bytes((0xC9, 0x40, 0xF0, 0x00))              # cmp #$40/beq loop
    fx_loop = len(stub) - 1
    stub += _setret(0xA0BD)                              # plain
    stub[fx_hold] = len(stub) - (fx_hold + 1)
    stub += _setret(0xA0B7)                              # hold
    stub[fx_loop] = len(stub) - (fx_loop + 1)
    stub += _setret(0xA0B2)                              # loop
    stub[fx_cmd] = len(stub) - (fx_cmd + 1)
    stub += bytes((0xB1, 0x10))                          # cmd: lda ($10),Y = arg
    stub += cmd_tail
    e8 += bytes(stub)
    e8 += bytes(E8_DMASTUB - len(e8))
    # DMA-kick stub: P1 ($6A00) and P2 ($7300) effects transfers; per-player
    # flags from the respective autopoll pads; staging override when flagged
    def _flagblock(pad_lo, pad_hi, flag, latch):
        b = bytearray()
        b += bytes((0xE2, 0x20))                             # sep #$20
        b += bytes((0xA5, 0x36, 0xC9, 0x7F, 0xD0, 0x00))     # $36!=7F -> orig
        j1 = len(b) - 1
        b += bytes((0xAD, pad_lo & 0xFF, pad_lo >> 8, 0x29, 0x30, 0xC9, 0x30, 0xD0, 0x05))
        b += bytes((0xA9, 0x01, 0x8D, flag & 0xFF, flag >> 8))
        b += bytes((0xAD, pad_hi & 0xFF, pad_hi >> 8, 0x29, 0x20, 0xF0, 0x03))
        b += bytes((0x9C, flag & 0xFF, flag >> 8))
        b += bytes((0xAD, flag & 0xFF, flag >> 8))           # lda flag
        b += bytes((0x8D, latch & 0xFF, latch >> 8))         # arm this round
        b += bytes((0xF0, 0x00))
        j2 = len(b) - 1
        return b, (j1, j2)
    d = bytearray()
    d += bytes((0x08, 0xC2, 0x30))                       # php / rep #$30
    d += bytes((0x48, 0xDA, 0x5A))                       # pha / phx / phy
    d += bytes((0xA5, 0x30, 0xC9, 0x00, 0x6A, 0xF0, 0x00))   # ==$6A00 -> p1eff
    fp1 = len(d) - 1
    d += bytes((0xC9, 0x00, 0x73, 0xF0, 0x00))               # ==$7300 -> p2eff
    fp2 = len(d) - 1
    d += bytes((0x80, 0x00))                                 # bra orig
    forig1 = len(d) - 1
    p1eff = len(d)
    b1, (j11, j12) = _flagblock(0x4218, 0x4219, SATURN_FLAG, SATURN_LATCH)
    d += b1
    d += bytes((0x80, 0x00))                                 # bra copy
    fcopy = len(d) - 1
    p2eff = len(d)
    b2, (j21, j22) = _flagblock(0x421A, 0x421B, SATURN_FLAG2, SATURN_LATCH2)
    d += b2
    copy = len(d)
    d += bytes((0xC2, 0x30))                             # rep #$30
    d += bytes((0xA2, 0x00, EE_TILES >> 8, 0xA0, 0x00, 0x00,
                0xA9, 0xFF, 0x0B, 0x8B, 0x54, 0x7F, 0xEE, 0xAB))
    orig = len(d)
    d[fp1] = p1eff - (fp1 + 1)
    d[fp2] = p2eff - (fp2 + 1)
    d[forig1] = orig - (forig1 + 1)
    d[fcopy] = copy - (fcopy + 1)
    d[p1eff + j11] = orig - (p1eff + j11 + 1)
    d[p1eff + j12] = orig - (p1eff + j12 + 1)
    d[p2eff + j21] = orig - (p2eff + j21 + 1)
    d[p2eff + j22] = orig - (p2eff + j22 + 1)
    d += bytes((0xC2, 0x30, 0x7A, 0xFA, 0x68, 0x28))     # rep #$30/ply/plx/pla/plp
    d += bytes((0xA0, 0x01, 0x8C, 0x00, 0x43, 0x8C, 0x0B, 0x42))
    d += bytes((0x6B,))
    e8 += bytes(d)
    assert len(e8) <= E8_SATURN_ACTTBL, f"stubs overrun Saturn act table: {len(e8):#x}"
    e8 += bytes(E8_SATURN_ACTTBL - len(e8))
    sat_tbl, nscripts = build_saturn_scripts(sup, E8_SATURN_ACTTBL)
    e8 += sat_tbl
    assert len(e8) <= PROJ_SCRIPTS_NEW, "Saturn scripts overrun the projectile region"
    e8 += bytes(PROJ_SCRIPTS_NEW - len(e8))
    # projectile blob, relocated. The act tables are irregular word arrays with
    # script bytes interleaved, so ONLY the verified pointer spans rebase:
    # 0x2715(3 acts, id 0x20), 0x2725(3, id 0x21), 0x2735(5, id 0x22) and the
    # dead-but-kept 0x274C(5) — every word verified in-blob before rebasing.
    proj = bytearray(sup[PROJ_SCRIPTS_LO:PROJ_SCRIPTS_HI])
    for base, n in ((0x2715, 3), (0x2725, 3), (0x2735, 5), (0x274C, 5)):
        for i in range(n):
            off = base - PROJ_SCRIPTS_LO + 2 * i
            w = proj[off] | proj[off + 1] << 8
            assert PROJ_SCRIPTS_LO <= w < PROJ_SCRIPTS_HI, \
                f"proj act table {base:#x}[{i}] not in-blob: {w:#x}"
            w += PROJ_DELTA
            proj[off], proj[off + 1] = w & 0xFF, w >> 8
    e8 += proj
    e8[2 * SAT_ID] = E8_SATURN_ACTTBL & 0xFF          # id -> act-table entry
    e8[2 * SAT_ID + 1] = E8_SATURN_ACTTBL >> 8
    for pid, tbl in PROJ_SCRIPT_ENTRIES.items():
        e8[2 * pid:2 * pid + 2] = bytes((tbl & 0xFF, tbl >> 8))
    write_bank(data, bankbase, bytes(e8))

    # ---- bank $E9: pose records ----
    bankbase, bank = next_bank(data)
    e9 = bytearray(0x10000)
    e9[0x8000:0x9400] = data[0x048000:0x049400]       # $84 region copy
    e9[E9_TABLE:E9_TABLE + 56] = data[0x04809C:0x04809C + 56]  # 28 entries (of 0x30)
    e9[E9_TABLE + 2 * SAT_ID] = E9_RECORDS & 0xFF
    e9[E9_TABLE + 2 * SAT_ID + 1] = E9_RECORDS >> 8
    for pid in PROJ_SCRIPT_ENTRIES:
        e9[E9_TABLE + 2 * pid:E9_TABLE + 2 * pid + 2] = \
            bytes((E9_PROJ_POSES & 0xFF, E9_PROJ_POSES >> 8))
    e9[E9_PROJ_POSES:E9_PROJ_POSES + PROJ_POSES_N] = \
        sup[PROJ_POSES_LO:PROJ_POSES_LO + PROJ_POSES_N]
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

    # ---- bank $EE: OAM sprite-layout blob at 0x8000 + her palettes at 0xC000 ----
    bankbase, bank = next_bank(data)
    assert bank == 0xEE, f"bank layout drift: ${bank:02X}"
    ee = bytearray(0x10000)
    ee[0x8000:0x8000 + (OAM_BLOB_HI - OAM_BLOB_LO)] = sup[OAM_BLOB_LO:OAM_BLOB_HI]
    # pal1 ($E0:B0C8) + pal2 ($E0:B0A8), 32 B each — consumed by the tester/probes
    # (written into the CGRAM shadow row $0600 = OBJ palette 0 = P1's fighter pal)
    ee[0xC000:0xC020] = sup[0x20B0C8:0x20B0C8 + 32]
    ee[0xC020:0xC040] = sup[0x20B0A8:0x20B0A8 + 32]
    # v0.11.1 (field report: red fireballs): both games draw projectiles with
    # OAM PALETTE 2 (attrs x34/x74/xB4/xF4, measured mid-flight in both) —
    # Super S loads a blue EFFECTS palette there ($E0:B208), SMS's row 2 holds
    # the shell game's effect colors (fire-orange ramp) -> red fireballs. The
    # helper injects this row into shadow $0640 at transform. Tradeoff: OBJ
    # pal 2 is shared, so a non-Saturn opponent's own projectile art recolors
    # slightly while a Saturn is in play.
    ee[0xC060:0xC080] = sup[0x20B208:0x20B208 + 32]
    ver = ("SATURN v" + VARIANT_STR).encode()
    ee[0xC040:0xC040 + len(ver) + 1] = ver + b"\x00"
    # -- char-select 10th-slot stubs (consumed by the v0.10.0 hooks below) --
    def _asm():
        code, fixups, labels = bytearray(), [], {}
        def lbl(name): labels[name] = len(code)
        def br(op, name):
            code.extend((op, 0x00)); fixups.append((len(code) - 1, name))
        def fix():
            for pos, name in fixups:
                d = labels[name] - (pos + 1)
                assert -128 <= d <= 127, f"branch too far: {name}"
                code[pos] = d & 0xFF
        return code, lbl, br, fix

    # shared marker enqueuer: UI sprites are QUEUED via the $9B17 emitter and
    # written to the OAM shadow later in the frame (direct shadow pokes get
    # E0-cleared), so the marker is a second $9B17 call with its own params:
    # same cursor def ($AADA), parked at the slot-10 photo spot. The emitter
    # is reached via the EMIT_GADGET (jsr $9B17 / rtl) carved from the dead
    # body of the hooked draw-blk1 routine — PB=$80 exactly like the original.
    if not SATURN_HIDDEN:
        mk = bytearray()
        mk += bytes((0xA9, SLOT10_XY[0], 0x85, 0x01, 0x64, 0x02))  # x
        mk += bytes((0xA9, SLOT10_XY[1], 0x85, 0x03, 0x64, 0x04))  # y
        mk += bytes((0x64, 0x06, 0xA9, 0x30, 0x85, 0x07))          # attr/prio
        mk += bytes((0xAF, 0xD9, 0xAA, 0xC0, 0x85, 0x00))          # count ($AAD9)
        mk += bytes((0xA9, 0xDA, 0x85, 0x12, 0xA9, 0xAA, 0x85, 0x13))  # def $AADA
        mk += bytes((0x22, EMIT_GADGET & 0xFF, EMIT_GADGET >> 8, 0x80))
        mk += bytes((0x60,))
        ee[EE_MARKER:EE_MARKER + len(mk)] = mk

        # draw reimpl: original routine body with long position reads (so the
        # char-10 row exists), emitter via the gadget, then the marker call;
        # plain rtl — the hooked site's trailing rts returns to the caller.
        d1 = bytearray()
        d1 += bytes((0xE2, 0x30))               # sep #$30
        d1 += bytes((0xDA, 0xBB))               # phx / tyx
        d1 += bytes((0xBF, 0x9D, 0xAA, 0xC0, 0x85, 0x01, 0x64, 0x02))
        d1 += bytes((0xBF, 0x9E, 0xAA, 0xC0, 0x85, 0x03))
        d1 += bytes((0x64, 0x04, 0x64, 0x06))
        d1 += bytes((0xA9, 0x30, 0x85, 0x07))   # attr/prio template
        d1 += bytes((0xAF, 0xD9, 0xAA, 0xC0, 0x85, 0x00))  # count byte ($AAD9)
        d1 += bytes((0xA9, 0xDA, 0x85, 0x12, 0xA9, 0xAA, 0x85, 0x13))  # def $AADA
        d1 += bytes((0xFA,))                    # plx
        d1 += bytes((0x22, EMIT_GADGET & 0xFF, EMIT_GADGET >> 8, 0x80))  # cursor
        d1 += bytes((0x20, EE_MARKER & 0xFF, EE_MARKER >> 8))            # marker
        d1 += bytes((0x6B,))
        assert len(d1) <= EE_CONFIRM - EE_DRAW1, f"draw1 stub too big: {len(d1)}"
        ee[EE_DRAW1:EE_DRAW1 + len(d1)] = d1

        # confirm stub (VISIBLE variant): slot-10 translation + flag
        # maintenance; ends by replicating the replaced head and rtl.
        c, lbl, br, fix = _asm()
        c += bytes((0xC2, 0x30))                   # rep #$30
        c += bytes((0xC0, 0x40, 0x1B)); br(0xF0, "known")   # cpy #$1B40
        c += bytes((0xC0, 0x80, 0x1B)); br(0xD0, "finish")  # cpy #$1B80
        lbl("known")
        c += bytes((0xB9, 0x02, 0x00)); br(0xD0, "finish")  # already confirmed
        c += bytes((0xB9, 0x00, 0x00, 0xC9, 0x0A, 0x00)); br(0xF0, "on10")
        c += bytes((0xE2, 0x20, 0xA9, 0x00)); br(0x80, "setflag")  # browsing: clear
        lbl("on10")
        c += bytes((0xA7, 0xFE, 0x29, 0xC0, 0xD0)); br(0xF0, "finish")  # press?
        c += bytes((0xA9, CHARSEL_SHELL, 0x00, 0x99, 0x00, 0x00))  # cursor -> shell
        c += bytes((0xE2, 0x20, 0xA9, 0x01))
        lbl("setflag")
        c += bytes((0xC0, 0x40, 0x1B)); br(0xD0, "p2f")
        c += bytes((0x8F, SATURN_FLAG & 0xFF, SATURN_FLAG >> 8, 0x7E)); br(0x80, "finish")
        lbl("p2f")
        c += bytes((0x8F, SATURN_FLAG2 & 0xFF, SATURN_FLAG2 >> 8, 0x7E))
        lbl("finish")
        c += bytes((0xC2, 0x30, 0xA7, 0xFE, 0x6B))  # rep #$30 / lda [$FE] / rtl
        fix()
    else:
        # confirm stub (HIDDEN variant, Gouki-style): no slot, no marker — a
        # confirm press with L+R HELD on the confirming pad picks Saturn for
        # that player; without the code the flag is cleared (per-press
        # re-decision, so stale flags self-clean). Held state comes from the
        # autopoll regs; the physical pad follows the handler's own [$FE]
        # pointer low byte ($60 = P1 pad, $62 = P2 pad) so the practice dummy
        # (P1-driven, Y=$1B80) reads P1's pad.
        c, lbl, br, fix = _asm()
        c += bytes((0xC2, 0x30))                   # rep #$30
        c += bytes((0xC0, 0x40, 0x1B)); br(0xF0, "known")   # cpy #$1B40
        c += bytes((0xC0, 0x80, 0x1B)); br(0xD0, "finish")  # cpy #$1B80
        lbl("known")
        c += bytes((0xB9, 0x02, 0x00)); br(0xD0, "finish")  # already confirmed
        c += bytes((0xA7, 0xFE, 0x29, 0xC0, 0xD0)); br(0xF0, "finish")  # press?
        c += bytes((0xE2, 0x20))                   # sep #$20
        c += bytes((0xA5, 0xFE, 0xC9, 0x62)); br(0xF0, "p2pad")  # pad ptr low
        c += bytes((0xAF, 0x18, 0x42, 0x00)); br(0x80, "got")    # JOY1L
        lbl("p2pad")
        c += bytes((0xAF, 0x1A, 0x42, 0x00))                     # JOY2L
        lbl("got")
        c += bytes((0x29, 0x30, 0xC9, 0x30)); br(0xD0, "noflag") # L+R held?
        c += bytes((0xA9, 0x01)); br(0x80, "store")
        lbl("noflag")
        c += bytes((0xA9, 0x00))
        lbl("store")
        c += bytes((0xC0, 0x40, 0x1B)); br(0xD0, "p2f")
        c += bytes((0x8F, SATURN_FLAG & 0xFF, SATURN_FLAG >> 8, 0x7E)); br(0x80, "finish")
        lbl("p2f")
        c += bytes((0x8F, SATURN_FLAG2 & 0xFF, SATURN_FLAG2 >> 8, 0x7E))
        lbl("finish")
        c += bytes((0xC2, 0x30, 0xA7, 0xFE, 0x6B))  # rep #$30 / lda [$FE] / rtl
        fix()
    assert len(c) <= 0x100, f"confirm stub too big: {len(c)}"
    ee[EE_CONFIRM:EE_CONFIRM + len(c)] = c

    # transform palette copier (see EE_PALCOPY): fighter row + effects row
    pc_ = bytearray()
    pc_ += bytes((0x64, 0x0D, 0xA5, 0x0E, 0x18, 0x69, 0x00, 0x85, 0x0C,
                  0xA9, 0x06, 0x85, 0x0D))       # $0C/0D = $06:row
    pc_ += bytes((0xDA, 0xA0, 0x1F, 0x00))       # phx / ldy #$001F
    pc_ += bytes((0xBB, 0xBF, 0x00, 0xC0, 0xEE, 0x91, 0x0C,
                  0x88, 0x10, (0x100 - 10) & 0xFF))   # fighter row loop
    pc_ += bytes((0xA9, 0x40, 0x85, 0x0C))       # -> $0640 (OBJ pal 2)
    pc_ += bytes((0xA0, 0x1F, 0x00))
    pc_ += bytes((0xBB, 0xBF, 0x60, 0xC0, 0xEE, 0x91, 0x0C,
                  0x88, 0x10, (0x100 - 10) & 0xFF))   # effects row loop
    pc_ += bytes((0xFA, 0x6B))                   # plx / rtl
    ee[EE_PALCOPY:EE_PALCOPY + len(pc_)] = pc_

    tiles = REPO / "traces" / "saturn" / "supers_effecttiles.bin"
    if tiles.is_file():
        tb = tiles.read_bytes()[:0xC00]
        ee[EE_TILES:EE_TILES + len(tb)] = tb
    else:
        print("WARNING: no effect-tile dump (traces/saturn/supers_effecttiles.bin);"
              " in-ROM L+R select will show wrong fireball art. Generate with:"
              " ROM=<SuperS> tools/run.sh tools/saturn/probe_supers_effecttiles.lua 60")
    write_bank(data, bankbase, bytes(ee))

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
    # helper v3 (at EF_HELPER): id test + P1/P2 in-ROM transforms
    h = bytearray()
    fixups = []          # (pos, labelname)
    labels = {}
    def _lbl(name): labels[name] = len(h)
    def _br(op, name):   # 2-byte branch with fixup
        h.extend((op, 0x00)); fixups.append((len(h) - 1, name))
    h += bytes((0xE2, 0x30))                     # sep #$30
    h += bytes((0xC9, 0x1C)); _br(0xF0, "sat")   # already Saturn
    h += bytes((0xE0, 0x00)); _br(0xF0, "p1chk")
    h += bytes((0xE0, 0x80)); _br(0xD0, "normal")
    # P2 check
    h += bytes((0x48, 0xAD, SATURN_LATCH2 & 0xFF, SATURN_LATCH2 >> 8)); _br(0xF0, "popn")
    h += bytes((0xA9, 0x20)); _br(0x80, "gates") # A=palette-row hint 0x20 -> $0620
    _lbl("p1chk")
    h += bytes((0x48, 0xAD, SATURN_LATCH & 0xFF, SATURN_LATCH >> 8)); _br(0xF0, "popn")
    h += bytes((0xA9, 0x00))                     # palette row 0x00 -> $0600
    _lbl("gates")
    h += bytes((0x85, 0x0E))                     # sta $0E (palette-dest low byte)
    h += bytes((0xAD, 0x04, 0x1E)); _br(0xD0, "popn")        # intro
    h += bytes((0xAD, 0xFA, 0x01, 0xC9, 0x80)); _br(0xD0, "popn")  # not-live
    h += bytes((0xC2, 0x10, 0xA6, 0x88))         # rep #$10 / ldx $88
    h += bytes((0xB5, 0x01, 0xC9, 0x03)); _br(0xB0, "pop8")  # act>=3
    h += bytes((0xA9, 0x1C, 0x95, 0x00))
    for o in (0x01, 0x02, 0x04, 0x05, 0x06, 0x07):
        h += bytes((0x74, o))
    # palette copy moved to $EE (EE_PALCOPY) — the helper slot is 0x90 bytes
    h += bytes((0x22, EE_PALCOPY & 0xFF, EE_PALCOPY >> 8, 0xEE))
    h += bytes((0x68, 0xA9, 0x1C, 0xE2, 0x10)); _br(0x80, "sat")
    _lbl("pop8")
    h += bytes((0xE2, 0x10))
    _lbl("popn")
    h += bytes((0x68,))
    _lbl("normal")
    h += bytes((0x0A, 0xAA))
    h += bytes((0x22, STUB2 & 0xFF, STUB2 >> 8, 0xC1, 0x6B))
    _lbl("sat")
    h += bytes((0x20, 0xF7, 0xC6, 0x6B))
    for pos, name in fixups:
        h[pos] = (labels[name] - (pos + 1)) & 0xFF
    assert len(h) <= 0x90, f"helper overflows its DB70-DC00 slot: {len(h)}"
    ef[EF_HELPER:EF_HELPER + len(h)] = h
    # recognizer graft: payload at original offsets; copied-table entry -> her list
    ef[0x1452:0x1452 + (RECOG_PAYLOAD_HI - RECOG_PAYLOAD_LO)] = \
        sup[RECOG_PAYLOAD_LO:RECOG_PAYLOAD_HI]
    ef[0x13C7 + 2 * SAT_ID:0x13C7 + 2 * SAT_ID + 2] = bytes((0x52, 0x14))
    # trampoline: jsr the copied dispatch AT ITS OWN PROLOGUE ($125C phb/phk/plb;
    # phk in bank $EF sets DB=$EF) so its tail plb/rts self-balances; then rtl
    ef[EF_TRAMP:EF_TRAMP + 4] = bytes.fromhex("205C126B")
    pblk, prep = PSP.patched_block(sup, bytes(data[:0x280000]),
                                   PROJ_BLOCK_LO, PROJ_BLOCK_HI, PROJ_PROC_ENTRIES)
    if prep["unresolved"]:
        raise SystemExit(f"error: projectile port unresolved: {prep['unresolved']}")
    ef[PROJ_BLOCK_LO:PROJ_BLOCK_HI] = pblk
    # tramp3 @ $EF:DB30: re-dispatch the projectile id to its proc (jsr keeps
    # rts semantics; entered via JSL from the $C1 mini-stub)
    # ldx $88 / lda $00,X / cmp #$20 / beq p20 / cmp #$21 / beq p21
    # / jsr $29A6 / rtl / p20: jsr $280B / rtl / p21: jsr $28D3 / rtl
    tramp3 = bytes.fromhex("C210A688B500C920F008C921F00820A6296B200B286B20D3286B")
    ef[0xDB30:0xDB30 + len(tramp3)] = tramp3
    # sound translator: sep #$20 / pha / (cmp #id / beq)* / pla / rtl;
    # per-id tails: lda #sfx / sta $78 / pla?? -> keep A-restoring tails
    snd = bytearray(bytes.fromhex("E22048"))
    tails = bytearray()
    fixups = []
    for cid, sfx in SND_MAP.items():
        snd += bytes((0xC9, cid, 0xF0, 0x00))       # beq -> patched below
        fixups.append((len(snd) - 1, len(tails)))
        tails += bytes((0xA9, sfx, 0x85, 0x78, 0x68, 0x6B))
    snd += bytes((0x68, 0x6B))                      # default: pla / rtl
    base_tails = len(snd)
    for off, tpos in fixups:
        snd[off] = base_tails + tpos - (off + 1)    # rel8 from after the beq operand
    snd += tails
    ef[EF_SND:EF_SND + len(snd)] = snd
    # re-point all silenced sound JSLs (JSL $80:9FB7 stub) to the translator
    old, new = bytes((0x22, 0xB7, 0x9F, 0x80)), bytes((0x22, EF_SND & 0xFF, EF_SND >> 8, 0xEF))
    cnt = 0
    i = ef.find(old)
    while i != -1:
        ef[i:i + 4] = new
        cnt += 1
        i = ef.find(old, i + 1)
    assert cnt >= 6, f"expected 6+ reached sound JSL sites, found {cnt}"
    write_bank(data, bankbase, bytes(ef))

    # ---- bank $F0: bank-$8A copy + widened box ptr tables + Saturn's boxes ----
    bankbase, bank = next_bank(data)
    assert bank == 0xF0, f"bank layout drift: ${bank:02X}"
    f0 = bytearray(data[0x0A0000:0x0B0000])
    for src, dst, n in ((0xC1F1, F0_HIT_T, 28), (0xC229, F0_HURT_T, 10), (0xC23D, F0_COLL_T, 10)):
        f0[dst:dst + 0x60] = bytes(0x60)
        f0[dst:dst + 2 * n] = data[0x0A0000 + src:0x0A0000 + src + 2 * n]
    for tbl, addr in ((F0_HIT_T, F0_HIT_D), (F0_HURT_T, F0_HURT_D), (F0_COLL_T, F0_COLL_D)):
        f0[tbl + 2 * SAT_ID:tbl + 2 * SAT_ID + 2] = bytes((addr & 0xFF, addr >> 8))
    hitb = sup[X.BOXES["hit"][0]:X.BOXES["hit"][0] + X.BOXES["hit"][1]]
    hurtb = sup[X.BOXES["hurt"][0]:X.BOXES["hurt"][0] + X.BOXES["hurt"][1]]
    collb = sup[X.BOXES["coll"][0]:X.BOXES["coll"][0] + X.BOXES["coll"][1]]
    f0[F0_HIT_D:F0_HIT_D + len(hitb)] = hitb
    f0[F0_HURT_D:F0_HURT_D + len(hurtb)] = hurtb
    f0[F0_COLL_D:F0_COLL_D + len(collb)] = collb
    f0[0x8920:0x8920 + PROJ_HIT_N] = sup[PROJ_HIT_LO:PROJ_HIT_LO + PROJ_HIT_N]
    for pid in PROJ_SCRIPT_ENTRIES:
        f0[F0_HIT_T + 2 * pid:F0_HIT_T + 2 * pid + 2] = bytes((0x20, 0x89))
    # projectile OAM blob at its original in-bank offset (read via $B0 mirror)
    f0[0xB4A6:0xB4A6 + (PROJ_OAM_HI - PROJ_OAM_LO)] = sup[PROJ_OAM_LO:PROJ_OAM_HI]
    write_bank(data, bankbase, bytes(f0))

    # ---- engine patches ----
    data[SITE_INTERP_DB] = 0xE8
    expect(SITE_INTERP_CMD, INTERP_CMD_OLD, "interpreter ctrl decode")
    data[SITE_INTERP_CMD:SITE_INTERP_CMD + 8] = \
        bytes((0x22, E8_CMDSTUB & 0xFF, E8_CMDSTUB >> 8, 0xE8)) + b"\xEA" * 4
    expect(SITE_DMA_KICK, DMA_KICK_OLD, "generic VRAM-DMA kick")
    data[SITE_DMA_KICK:SITE_DMA_KICK + 8] = \
        bytes((0x22, E8_DMASTUB & 0xFF, E8_DMASTUB >> 8, 0xE8)) + b"\xEA" * 4
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
    # recognizer hook data slot = Saturn's button record (skipped via surgery)
    data[0x10000 + BTN_RECORD_ADDR:0x10000 + BTN_RECORD_ADDR + 7] = SATURN_BTN_RECORD
    import os as _os
    if _os.environ.get("SATURN_SKIP") != "btn":
        # the 7 skipped bytes host the projectile-proc mini-stub (jsr-dispatch
        # target at $C1:15C8): JSL $EF:DB30 (tramp3) / RTS
        data[SITE_BTN:SITE_BTN + 11] = \
            bytes((0x22, E8_BTNSTUB & 0xFF, E8_BTNSTUB >> 8, 0xE8)) \
            + bytes((0x22, 0x30, 0xDB, 0xEF, 0x60)) + b"\xFF" * 2
    import os
    if os.environ.get("SATURN_SKIP") != "box":
        for site in BOX_PLB_SITES:
            data[site + 1] = 0xB0
        for site, (old, new) in BOX_READS.items():
            data[site + 1:site + 3] = bytes((new & 0xFF, new >> 8))
    # -- v0.10.0 char-select 10th slot / v0.11.0 hidden-code variant --
    expect(CHARSEL_CONFIRM, CHARSEL_CONFIRM_OLD, "charsel confirm head")
    data[CHARSEL_CONFIRM:CHARSEL_CONFIRM + 4] = \
        bytes((0x22, EE_CONFIRM & 0xFF, EE_CONFIRM >> 8, 0xEE))
    if not SATURN_HIDDEN:
        expect(CHARSEL_DRAW1, CHARSEL_DRAW1_OLD, "draw-blk1 head")
        data[CHARSEL_DRAW1:CHARSEL_DRAW1 + 5] = \
            bytes((0x22, EE_DRAW1 & 0xFF, EE_DRAW1 >> 8, 0xEE, 0x60))
        expect(EMIT_GADGET, bytes.fromhex("85016402"), "gadget slot (dead blk1 body)")
        data[EMIT_GADGET:EMIT_GADGET + 4] = bytes((0x20, 0x17, 0x9B, 0x6B))
        expect(T1_IDX10, b"\x00\x00\x00\x00", "t1 row 10 (t2 dead row 0)")
        data[T1_IDX10:T1_IDX10 + 4] = bytes((0x05, 0x0A, 0x09, 0x0A))
        expect(T1_ID9_RIGHT, b"\x09", "t1 Chibimoon right")
        data[T1_ID9_RIGHT] = 0x0A
        expect(T1_ID5_DOWN, b"\x05", "t1 Venus down")
        data[T1_ID5_DOWN] = 0x0A
        expect(POS1_10, b"\x00\x00", "blk1 char-10 word")
        data[POS1_10:POS1_10 + 2] = bytes(SLOT10_XY)
        expect(POS2_10, b"\x00\x00", "blk2 char-10 word")
        data[POS2_10:POS2_10 + 2] = bytes((SLOT10_XY[0] + 0x10, SLOT10_XY[1]))
    expect(0x10000 + PROJ_DESPAWN, bytes.fromhex("740060"), "despawn tail")
    for pid in PROJ_IDS:
        site = 0x100A6 + 2 * pid
        expect(site, b"\x00\x00", f"proc-table entry {pid:#04x} (must be free)")
        if pid in PROJ_SCRIPT_ENTRIES:      # real ported procs via the mini-stub
            data[site:site + 2] = bytes(((SITE_BTN + 4) & 0xFF, ((SITE_BTN + 4) - 0x10000) >> 8))
        else:
            data[site:site + 2] = bytes((PROJ_DESPAWN & 0xFF, PROJ_DESPAWN >> 8))
    # OAM char-table entries for the projectiles -> shared blob via $B0 mirror
    for pid in PROJ_SCRIPT_ENTRIES:
        site = 0x048000 + 3 * pid
        expect(site, b"\x00\x00\x00", f"OAM entry {pid:#04x} (must be free)")
        data[site:site + 3] = bytes((0xA6, 0xB4, 0xB0))

    fix_checksum(data)
    open(out_path, "wb").write(data)
    print(f"wrote {out_path}: saturn-smoke v{VARIANT_STR}, {len(data):#x} bytes, "
          f"Saturn object id {SAT_ID:#04x}, {nscripts} scripts (CMD-intact)")
    print("sha1", hashlib.sha1(bytes(data)).hexdigest())


if __name__ == "__main__":
    main()
