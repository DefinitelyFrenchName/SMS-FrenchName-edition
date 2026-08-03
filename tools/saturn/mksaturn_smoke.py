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
SATURN_VERSION = "0.13.3"

# Build variant. CONSENSUS (maintainer, 2026-07-31): the HIDDEN code is the
# canonical character-select — it is now the DEFAULT build.
#   default          -> HIDDEN (no visible trace: no marker, no navigable slot);
#   SATURN_VISIBLE=1 -> the 0.10.0 visible slot 10 (kept buildable for A/B);
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
# Card-portrait: ON since v0.12.1 (complete — art, layout and palette). Three
# pieces, all under per-player flag control so a non-Saturn card is untouched:
#   1. tiles  — her Super S portrait, converted from a 1:1 capture, DMA'd over
#      the card's VRAM window right after the vanilla upload ($EE:C900 wrapper);
#   2. layout — her OWN sprite list (the composition is per-character, and hers
#      is bigger than any SMS one), substituted at $C0:9E86 ($EE:CA00 stub);
#   3. palette — re-seeded into the CGRAM shadow every frame from that same
#      stub, because a one-shot copy is overwritten by the engine's own refill.
# Set SATURN_PORTRAIT=0 to build without it.
SATURN_PORTRAIT = _osv.environ.get("SATURN_PORTRAIT") != "0"
# DIAGNOSTIC: SATURN_PORTRAIT_FORCE=1 drops the "whose card is this" gate from
# the sprite-list hook, leaving only "the card's own portrait list is being
# drawn". Her portrait then appears on ANY card, which is wrong for shipping but
# answers one question in a single match: if her art shows, the hooks run and
# the GATE inputs differ in that flow; if the shell's portrait still shows, the
# hooks are not running there at all.
SATURN_PORTRAIT_FORCE = _osv.environ.get("SATURN_PORTRAIT_FORCE") == "1"
SATURN_HIDDEN = _osv.environ.get("SATURN_VISIBLE") != "1"
SATURN_STACKED = bool(_osv.environ.get("SATURN_BASE"))
VARIANT_FILE = f"{SATURN_VERSION}-hidden" if SATURN_HIDDEN else SATURN_VERSION
VARIANT_STR = SATURN_VERSION + ("H" if SATURN_HIDDEN else "") + ("R" if SATURN_STACKED else "")
ROM_STEM = "SailorMoonS_REFsaturn" if SATURN_STACKED else "SailorMoonS_saturn"

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
# v0.11.8 — CROSS-GAME OBJECT-ID SHIFT (the "crashed while fighting" bug).
# The two games' ENGINE object-id tables ($C1:00A6) differ by one entry in the
# effect range: Super S id N is SMS id N-1 for N >= 0x31 (verified by proc
# byte-match: SUP 31/32/33/34 -> SMS 30/31/32/33 at 35..42 of 48 bytes).
# Saturn's proc SPAWNS engine effect objects from 6-byte records in her data
# pocket ([id16 (id in the LOW byte, flags high), x16, y16] consumed by
# $C1:1141 -> $80:839D). Her KO handler (act 0x1E) spawns TWO id-0x34 objects;
# in SMS that id is a DIFFERENT object type whose proc never returns, so the
# whole frame update stops — game frozen, music still playing, screen fades to
# black. Reproduced deterministically: any KO with Saturn as the VICTIM.
# Fix: shift the ids in her spawn records. (Her projectile ids 0x20-0x22 are
# below the shift range and are objects we ported ourselves — untouched.)
SPAWN_ID_FIX = {0xD9F3: (0x33, 0x32), 0xD9F9: (0x34, 0x33), 0xD9FF: (0x34, 0x33)}
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
EF_TRAMP3 = 0xDA60      # v0.11.8: the id-routing trampoline outgrew its old
                        # DB30 slot (it now handles Saturn as well as the three
                        # projectiles) and was silently overwritten by the sound
                        # translator at DB50. Moved into the verified 158-byte
                        # zero run at $EF:DA56-DAF3 (inside the graft window,
                        # not part of her ported code or data pockets).
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
# v0.12.7 — corrected by parsing which ACT requests each arg (rather than
# inferring from when a sound was heard):
#   arg 0x22 is requested by act 0x24, HER WIN POSE — it is her laugh, not a
#     dash sound. v0.11.1 mapped it to the dash whoosh 0x2D alongside 0x06
#     (which really is the dash, act 0x26), so her win played a whoosh. Now
#     silent pending a real voice sample: silence beats an obviously wrong sfx.
#   args 0x23/0x24/0x25 are requested by her SPECIALS (acts 0x6E/0x6F,
#     0x3E/0x6A/0x6B, 0x3F/0x6C/0x6D/0x70-0x75) — 236P, 214P and j.632K. They
#     were left unmapped on the assumption the engine plays the starter sound
#     itself; the field confirms it does not, so they were silent. Mapped to
#     the heavy whoosh so the throws are audible; in Super S these are VOICE
#     samples, so a faithful fix needs the sample import (task #44 maximum).
CMD_SND_MAP = {0x15: 0x05, 0x14: 0x06, 0x0E: 0x06, 0x20: 0x06,
               0x02: 0x0C, 0x06: 0x2D, 0x08: 0x0D,
               0x23: 0x06, 0x24: 0x06, 0x25: 0x06}
# v0.13.0 — HER REAL VOICE (task #44). Set SATURN_VOICE=0 to build without it
# (CMD args 0x22-0x25 then fall back to the v0.12.7 whoosh/silence above).
SATURN_VOICE = _osv.environ.get("SATURN_VOICE") != "0"
#
# How SMS voices a fighter (all measured — probe_sms_voiceload / voiceid /
# voicetrace; full write-up in docs/saturn/sound_scope.md):
#
#   * Each player gets a private BRR bank in ARAM: P1 at $B700, P2 at $DB00
#     (delta $2400). Both are uploaded at match start from table $C0:ECE7,
#     record 30 + charID, whose single IPL block targets $B700:
#       P1  $C0:88D9  lda $1D00 / clc / adc #$1E / jsl $80:EB4B
#       P2  $C0:8A24  $10 = $2400 then  lda $1D03 / adc #$1E / jsl $80:EC5E
#     $C0:EC5E is the RELOCATING uploader — it adds dp $10 to every block's ARAM
#     destination (and zeroes $10 for the terminator so the entry point is not
#     offset). That is the whole answer to "how does P2's bank reach $DB00",
#     and it is also the lever we use to place her directory for either player.
#   * The BRR directory is NOT per match: DSP DIR = page $34, and a complete
#     nine-character table is resident from boot at ARAM $34C0 + (charID-1)*32
#     (source $E4:2CC4 + (charID-1)*32). Each 32-byte record is 8 entries of
#     [start16, loop16]: entries 0-3 describe that character's samples inside
#     P1's $B700 bank, 4-7 the same samples at $DB00.
#   * A voice is requested by writing an id to the player's struct +0x78; the
#     NMI at $C0:D4F2 forwards P1's to APU port 0 and P2's to port 1 with bit 7
#     SET, and the driver resolves id -> directory entry as
#         dir = 48 + (charID-1)*8 + k     for  id = 49 + (charID-1)*5 + k, k=0..3
#     adding 4 when bit 7 is set. Ids past 93 are dead — there is no spare
#     tenth-character slot to claim.
#
# So loading her samples is not enough: the directory has to describe HER
# layout, which corrects the earlier scoping note ("no id remapping is needed"
# — true for the bank, wrong about the directory). Since the two halves of a
# record are per player and can never both be Saturn's opponent, she can use
# ONE character's id range on whichever side she is playing:
#   she uses char 1's ids (49-52) and we overwrite char 1's half-record for her
#   player only. A P1 Moon cannot coexist with a P1 Saturn, and a P2 Moon reads
#   entries 4-7, which we never touch when she is P1.
# The clobber is undone by the same hook: a non-Saturn load restores char 1's
# half from ROM when the DIRTY flag says we dirtied it, so a later Moon match in
# the same session sounds normal. (The directory is boot-resident — without the
# restore, Moon would stay broken until a power cycle.)
VOICE_ARG_LO = 0x22       # her CMD args 0x22..0x25 = laugh, 236P, 214P, j.632K
VOICE_ID_BASE = 49        # -> char 1's ids 49..52 -> directory entries 48..51
VOICE_DIRTY = 0xF107      # $7F: "char 1's P1 half currently holds her samples"
VOICE_DIRTY2 = 0xF108     # ditto for the P2 half
# Spare records in the bank table. The loaders index it with an 8-bit id, so id
# n reads $ECE7 + 6n; vanilla ids stop at 39 and $C0:EE00-EE3F is a 64-byte zero
# run, which ids 47..57 index into. Verified unread across a full boot -> title
# -> select -> match -> KO -> win session (probe_sms_freetable.lua: 0 reads),
# and the builder asserts the run is still zero before claiming it.
VOICE_TBL = 0x00ECE7
VOICE_ID_SAMP = 47        # her sample bank      -> $B700 (+$2400 for P2)
VOICE_ID_DIRP1 = 48       # her directory, P1    -> $34C0
VOICE_ID_DIRP2 = 49       # her directory, P2    -> $34D0 (via dp $10 = $0010)
VOICE_ID_RESP1 = 50       # char 1's vanilla P1 half (restore)
VOICE_ID_RESP2 = 51       # char 1's vanilla P2 half (restore)
VOICE_DIR_ARAM = 0x34C0   # char 1's record; +0x10 is its P2 half
VOICE_SRC_ROM = 0x242CC4  # $E4:2CC4 — char 1's vanilla record, 32 bytes
SITE_VOICE_P1 = 0x0088DF  # jsl $80:EB4B  (P1's voice-bank load)
VOICE_P1_OLD = bytes.fromhex("224BEB80")
SITE_VOICE_P2 = 0x008A34  # jsl $80:EC5E  (P2's, with dp $10 = $2400)
VOICE_P2_OLD = bytes.fromhex("225EEC80")
# v0.13.1 — HER CHARACTER-SELECT LINE ("Yoroshiku"). SMS already voices every
# sailor when she is confirmed at the select screen, and the mechanism is a
# clean one to borrow (measured, probe_sms_selectvoice / selectwho):
#   $C0:AE4C   ldx $1B1E                 <- the character being presented
#              lda $AE7F,X / sta $1C50   <- her sound id (48/53/58/…, stride 5)
#              lda $AE75,X               <- her audio-bank id (22..30 = 21+charID)
#              jsl $80:EB4B              <- upload: one BRR sample to ARAM $B700
#                                           plus a 4-byte directory write to $3500
# Every one of those sound ids resolves to directory entry 48, whose start is
# $B700, and the sample is a one-shot terminated by its own END FLAG — so the
# length in the directory is irrelevant and Saturn needs NO id change and NO
# directory patch here. Only the bank has to be swapped, which is one hook.
#
# WHICH PLAYER is being voiced is not in $1B1E (that is the CHARACTER, and she
# can wear any shell — the exact shape of the card-portrait bug). But the three
# writers of $1B1E are per player and distinguishable:
#   $C0:AEF3 / $C0:AF34  lda $1B40  -> P1        $C0:AF12  lda $1B80  -> P2
# so each records the player in $7F:F109 and the bank hook reads it. Confirmed
# by measurement that the hidden confirm stub (which sets the Saturn flag from
# L+R) runs BEFORE this load, so the flag is already correct here.
VOICE_SEL_ID = 52             # her select bank -> another spare table record
VOICE_PLAYER = 0xF109         # $7F: who the select voice is currently for (0/1)
SITE_SELBANK = 0x00AE55       # lda $AE75,X / jsl $80:EB4B
SELBANK_OLD = bytes.fromhex("BD75AE224BEB80")
# the three `lda $1B40|$1B80 / and #$00FF / sta $1B1E` sequences, 9 bytes each
SITE_SELWHO = ((0x00AEF3, 0), (0x00AF12, 1), (0x00AF34, 0))
SELWHO_OLD = {0: bytes.fromhex("AD401B29FF008D1E1B"),
              1: bytes.fromhex("AD801B29FF008D1E1B")}
SEL_ARAM = 0xB700             # where a select line is uploaded
SEL_DIRW = 0x3500             # the 4-byte directory write the vanilla banks make
# in-bank layout of the appended voice bank
V_SAMP, V_DIRP1, V_DIRP2 = 0x0000, 0x2600, 0x2620
V_RESP1, V_RESP2 = 0x2640, 0x2660
V_HOOK1, V_HOOK2 = 0x2700, 0x2780
V_SEL = 0x2800                # her select-line stream (2610 B + headers)
V_SELHOOK, V_WHO1, V_WHO2 = 0x3300, 0x3360, 0x3380
# v0.13.2 — HER MOVELIST (task #41). SMS picks a character's list from a table
# of nine 3-byte pointers at $E0:021A + charID*3, expands it into the staging
# buffer and DMAs it to BG3 (P1 -> VRAM word $1000, P2 -> $1400). The two reads
# of that table are per player and each sits in a block fed by that player's own
# struct charID, so the override needs no shell-specific code:
#   $C0:8B53  lda $E0021A,X -> $00      (P1, from $1000)
#   $C0:8B59  lda $E0021C,X -> $02
#   $C0:8B7B / $C0:8B81                 (P2, from $1080)
# We hook the SECOND read of each pair, because a stub there can set BOTH halves
# of the pointer: $00 was already loaded by the vanilla first read, and A on
# return becomes $02. There is no free tenth row in the table (row 10 starts
# exactly at $E0:0238, the manifest pointer table), which is why this is a hook.
# Her tilemap is authored by tools/saturn/mkmovelist.py and compressed with
# tools/saturn/sms_lz.py — Super S does not share this codec, so it cannot be
# lifted; see docs/saturn/movelist.md.
SITE_ML_P1 = 0x008B59
SITE_ML_P2 = 0x008B81
ML_OLD = bytes.fromhex("BF1C02E0")
V_MOVELIST = 0x3400           # her compressed movelist
V_MLHOOK1, V_MLHOOK2 = 0x3700, 0x3740   # clear of the ~600-byte blob at $3400
# v0.8.0 — IN-ROM SATURN SELECT (P1): hold L+R while a round loads -> flag
# $7E:1F60 set; the effects-DMA helper hook ($C0:92A4, generic VRAM-DMA kick,
# filtered on $30==0x6A00/$36==$7F) also overrides the $7F:0000 staging with her
# raw tiles ($EE:D000, embedded from traces/saturn/supers_effecttiles.bin when
# present); the $EF proc helper transforms P1 at neutral + injects her palette.
# Hold SELECT at a round load to clear. Flag persists across rounds. P2 stays
# Lua-only (its effect-buffer layout unmapped).
SITE_DMA_KICK = 0x092A4
DMA_KICK_OLD = bytes.fromhex("A0018C00438C0B42")
E8_DMASTUB = 0x2A00   # v0.11.10: CMD stub grew past 0x2980
# v0.11.6 COLLISION FIX (found while REing the config screen): $7E:1F60-$1F63
# is NOT free — bank $C3 (menus/VS-config) writes all four ($C3:B904 sets
# $1F60=1, $C3:B973 $1F61, $C3:B9F5 $1F62, $C3:BA57 $1F63) and reads them
# ($C3:89D2 …). Our select flags + per-round latches squatted exactly there:
# the VS-config screen sits BETWEEN char select and the round load, i.e.
# between where the hidden code sets a flag and where the DMA stub latches it
# — a stray menu path could silently arm or disarm Saturn.
# Relocated to $7F:F100-F103, empirically verified untouched by a full vanilla
# session (boot→charselect→config→match→KO→win; the only writes are the
# frame-9 boot RAM clear) and a page clear of patch 11's $7F:F000-F065 block.
# Access cost: long addressing in the stubs (the DMA/proc stubs already run
# with a known DB, so lda/sta long is a 1-byte-per-site change).
SATURN_FLAG = 0xF100      # P1 select flag  ($7F bank — see above)
SATURN_FLAG2 = 0xF101     # P2 select flag
EE_TILES = 0xD000         # <- $7F:0000 staging reused); P2 pad = $421A/B.
# v0.11.11: blank cel for her "no cel" poses (0x7E-0x83, celA == 0). Super S
# treats cel 0 as invisible; SMS's engine does NOT skip it, and a zero-size
# record makes the DMA transfer 65536 bytes (SNES length-0 semantics) — the
# screen-wide corruption. Record 0 now points at a real, cel-sized run of
# zeros, so those frames render blank (the intended "invisible") instead.
EE_BLANKCEL = 0xE400
EE_BLANKCEL_SZ = 0x0480
# v0.12.0 — REPORT-CARD PORTRAIT. The card uploads each player's portrait from
# a per-character table ($9F:94C2, 3-byte pointers into bank $C8, index =
# (code-6)/2) through the loader at $80:8DEC; a Saturn player shows the shell
# character's face. Repointing the table entry would need her art re-encoded
# in SMS's own compression (a multi-mode bit codec, out of timebox), so we take
# the approved fallback: wrap the loader call at $9F:949F and, once the vanilla
# upload has run, blit HER portrait over the same VRAM window. Art comes from
# Super S job 100 (P1 dest) decompressed at build time — 0x820 bytes.
SUP_PORTRAIT_JOB = 100
EE_PORTRAIT = 0xE900
EE_PORTPAL = 0xE8C0   # her portrait palette -> CGRAM row 8 (colours 128-143)
EE_CARDPORT = 0xC900          # the wrapper stub
# The card's sprite composition is PER CHARACTER (Uranus 31 sprites / 71x72 px,
# Moon 18 / 66x64 — measured), and the renderer takes the list pointer from the
# portrait object's own fields +0x64/+0x66, re-read EVERY frame at $C0:9E86.
# Saturn's art is a full square, so squeezing it through Uranus's silhouette
# clipped her (field report: "lower left of face and hair, the Y of the glaive").
# We give her her own list: a 9x9 block of 8x8 sprites (72x72) over tiles
# $00-$50, generated by tools/saturn/mkportrait.py --list.
EE_SPRLIST = 0xE100           # her sprite list (count byte + 6-byte records)
EE_LISTHOOK = 0xCA00          # the $C0:9E86 substitution stub
EE_BLIT = 0xCB00              # the tile+palette blit, callable by both hooks
SITE_LISTPTR = 0x009E86       # lda $64,X / sta $12 / lda $66,X / sta $14
LISTPTR_OLD = bytes.fromhex("b5648512b5668514")
SITE_LISTBANK = 0x009EA6      # lda $66,X (re-read for `plb`, 8-bit A here)
LISTBANK_OLD = bytes.fromhex("b566")
VANILLA_LIST = 0xCBEC         # Uranus's list @ $9F:CBEC — our detection key
# WHICH PLAYER the card belongs to. Not derivable from the object: the card
# always builds the winner's portrait through the $1000 slot and always uploads
# it to VRAM $0000, whoever won — so keying on the slot (or on the upload
# destination) shows Saturn's portrait on a card won by the OTHER player when
# that player happens to be Uranus, our shell. Found by diffing all of WRAM
# between a P1 win and a P2 win: $7E:1E14 = 1 for a P1 win, 2 for a P2 win.
SITE_WINNER = 0x1E14
SITE_CARDLOAD = 0x1F949F      # $9F:949F  jsl $80:8DEC (the portrait upload)
CARDLOAD_OLD = bytes.fromhex("22EC8D80")
# v0.10.0 FIX (latent since 0.8.0): the $EF helper must NOT transform on the
# user flag directly — story-mode load screens pass its act/$1FA gates on
# non-fight actors, and a flag set BEFORE the load (char-select pick, or a
# stale flag from an earlier match) crashed the story sequencer (pc -> $FFB0).
# The L+R path never hit this only because the DMA stub sets the flag exactly
# at the effects transfer, which is AFTER that window. So the DMA stub now
# latches flag -> per-round ARM ($1F62/63) at that proven-safe moment, and the
# helper transforms on the latch. Pre-set flags thereby behave exactly like
# held-L+R: they take effect at the shell char's effects DMA, never earlier.
SATURN_LATCH = 0xF102     # P1 armed-this-round latch
SATURN_MARK = 0xF105   # "her card tiles are uploaded" marker
SATURN_INIDISP = 0xF106  # INIDISP saved across the blit's forced blank
SATURN_LATCH2 = 0xF103    # P2 armed-this-round latch
SATURN_BANK = 0x7F        # bank byte for all four (long addressing)
# v0.11.7: NO WRAM address is provably safe — $C0:9251 is a generic
# pointer-driven copy loop (`lda ($06),Y / sta ($03),Y`) whose destination is
# caller data, and it was observed spraying $7F:F100-F102 with 7F/3F junk
# during boot on the Saturn build. So the flags no longer mean "nonzero =
# Saturn": they must equal MAGIC. Junk therefore reads as "not selected"
# (fail-safe) instead of arming Saturn at random, and a clobber can only
# cancel a selection, never invent one.
SATURN_MAGIC = 0xA5
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
# v0.11.3 — WIN SCREEN (found via win-pose verification): the round-result
# screen loads per-WINNER-id far pointers from packed tables in bank $82 and
# long-DMAs the records to VRAM ($C0:8C4D consumer, header [vram16,rowlen16,
# rows16]): name-plate table $82:E008+id*2 (4 read sites) and win-quote table
# $82:E01C+id*2 -> 7-word per-char pointer array -> quote records (2 read
# sites; slot 0 = no quote, engine skips on $74==0). Id 0x1C indexed far past
# both tables -> garbage pointer -> the row-count word became a huge DMA loop
# inside the sequencer = BLACK SCREEN HANG after any round Saturn wins.
# Fix: hook all 6 sites (byte-identical load sequences) with two $EE stubs
# that serve id 0x1C from ported Super S records (name plate @$82:E894,
# quote array @$82:E2C4 — 4 real quotes; tile indices verified to exist in
# SMS's win-screen tileset; attrs kept verbatim). Records live in $EE — the
# consumer reads via [$74] long, any bank works.
WIN_NP_SITES = (0x0DC37, 0x0DC60, 0x0DF53, 0x0DF8D)
WIN_NP_OLD = bytes.fromhex("BF08E0828574A0828476")
WIN_QT_SITES = (0x0DDDB, 0x0DE0A)
WIN_QT_OLD = bytes.fromhex("BF1CE0828510AD091E29FE0018651085 10A982008512A7108574A0828476".replace(" ", ""))
SUP_WIN_NP = 0xE894           # Super S $82:E894 (126 B)
SUP_WIN_QARR = 0xE2C4         # Super S $82:E2C4 (7 words)
EE_WINSTUB_NP = 0xC500
EE_WINSTUB_QT = 0xC540
EE_WIN_NP = 0xC5A0
EE_WIN_QARR = 0xC620
EE_WIN_QREC = 0xC630
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
# Box DATA blocks in bank $F0. COLL sat at 0x8910 until 2026-08-02, which put
# it 16 bytes ahead of the projectile hitbox blob — so the projectile boxes
# overwrote collision entries 2-5 and Saturn had NO push box in most poses
# (field report: she walks straight through the opponent). The layout is now
# asserted non-overlapping at build time.
F0_HIT_D, F0_HURT_D, F0_COLL_D = 0x8230, 0x8330, 0x8960
F0_PROJ_HIT_D = 0x8920        # projectile hitboxes (PROJ_HIT_N bytes)
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
        str(REPO / "build" / "saturn" / f"{ROM_STEM}_v{VARIANT_FILE}.sfc")

    base_path = _osv.environ.get("SATURN_BASE")
    if base_path:
        require_source(base_path, stacked=True)
        data = bytearray(open(base_path, "rb").read())
    else:
        sms_path = clean_rom()
        require_source(sms_path)             # default: build from clean
        data = bytearray(open(sms_path, "rb").read())
    # ---- appended-bank layout, derived from the actual base (v0.11.5:
    # REF-stackable — on the REF v.1 bundle the first free bank is $F0) ----
    nb = 0xC0 + len(data) // 0x10000
    nbanks = 10 if SATURN_VOICE else 9
    assert nb + nbanks - 1 <= 0xFF, \
        f"no room: first free bank ${nb:02X} (+{nbanks} banks needed)"
    B_SCR = nb          # scripts        (clean-base: $E8)
    B_POSE = nb + 1     # pose records   ($E9)
    B_CELT = nb + 2     # cel tables     ($EA)
    B_CEL0, B_CEL1, B_CEL2 = nb + 3, nb + 4, nb + 5   # cels ($EB-$ED)
    B_MISC = nb + 6     # OAM blob/palettes/stubs/records ($EE)
    B_C1 = nb + 7       # full C1 copy + graft ($EF)
    B_BOX = nb + 8      # bank-$8A copy ($F0)
    B_VOICE = nb + 9    # voice bank + IPL streams + the two load hooks ($F1)
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
    assert bank == B_SCR, f"bank layout drift: ${bank:02X}"
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
            + bytes((0x22, EF_TRAMP & 0xFF, EF_TRAMP >> 8, B_C1, 0x6B)))
    assert len(stub) <= E8_BTNSTUB - E8_STUB, "recognizer stub overruns button stub"
    e8 += stub
    e8 += bytes(E8_STUB + (E8_BTNSTUB - E8_STUB) - len(e8))
    # button stub: skip the 7 data bytes; Saturn -> Y = her record (in the
    # recognizer hook's data slot); others -> original head
    btnstub = (bytes.fromhex("A3011869070083 01".replace(" ", ""))
               + bytes.fromhex("B50029FF00C91C00F0070AA8B99B16A86B")
               + bytes((0xA9, BTN_RECORD_ADDR & 0xFF, BTN_RECORD_ADDR >> 8, B_SCR - 0x40, 0x6B)))
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
    # v0.11.10 FIX (field report: wrong sfx on hit, "Sonic ring" tone): the
    # no-match path used to fall through into the shared store, so any CMD arg
    # we deliberately leave UNMAPPED (her hit-reaction args 0x05/0x11/0x12/
    # 0x16 — the engine already plays those sounds) was written to $78 RAW and
    # played as whatever sfx that id happens to be. Unmapped args are silent
    # again: matches branch to the store, the fallthrough skips it.
    cmd_tail = bytearray()
    # v0.13.0 — VOICE args go somewhere else entirely. 0x22-0x25 are her laugh
    # and her three specials, which in Super S are voice samples; SMS voices a
    # fighter through the PER-PLAYER slot at struct +0x78 (the NMI at $C0:D4F2
    # forwards it to APU port 0/1), not the shared effect slot at DP $78.
    # X already holds the running object's struct base: the interpreter is a loop
    # over objects (`$C0:A05C  ldx #$1000 … adc #$0080 … cpx #$1800`) and X is
    # live and 16-bit at the hook with DP = 0, so a bare `sta $78,X` reaches
    # $1078 or $10F8 for whoever is executing the script. That is what makes her
    # voice follow her player with no shell-specific code. Ids are char 1's
    # (49-52), matching the directory half this build patches for her.
    # An earlier version did `ldx $88` first, assuming $88 is the current object
    # the way it is in the proc helper. It is not — at CMD time it still holds
    # whatever object last set it (measured: a constant $1080), so her voice came
    # out of P2's slot while she was P1. Clobbering X was the whole bug;
    # probe_sms_cmdwho.lua is the measurement.
    snd_map = dict(CMD_SND_MAP)
    if SATURN_VOICE:
        for a in (0x23, 0x24, 0x25):
            snd_map.pop(a, None)         # were the placeholder heavy whoosh
        cmd_tail += bytes((0xC9, VOICE_ARG_LO, 0x90, 0x00))          # bcc -> sfx
        fx_lo = len(cmd_tail) - 1
        cmd_tail += bytes((0xC9, VOICE_ARG_LO + 4, 0xB0, 0x00))      # bcs -> sfx
        fx_hi = len(cmd_tail) - 1
        cmd_tail += bytes((0x18, 0x69, VOICE_ID_BASE - VOICE_ARG_LO))  # clc/adc
        cmd_tail += bytes((0x95, 0x78))                              # sta $78,X
        cmd_tail += bytes((0x80, 0x00))                              # bra -> ret
        fx_voice_done = len(cmd_tail) - 1
        cmd_tail[fx_lo] = len(cmd_tail) - (fx_lo + 1)
        cmd_tail[fx_hi] = len(cmd_tail) - (fx_hi + 1)
    fx_store = []
    for cid, sfx in snd_map.items():
        cmd_tail += bytes((0xC9, cid, 0xD0, 0x04, 0xA9, sfx, 0x80, 0x00))
        fx_store.append(len(cmd_tail) - 1)
    cmd_tail += bytes((0x80, 0x02))      # no match -> skip the store (silent)
    for pos in fx_store:
        cmd_tail[pos] = len(cmd_tail) - (pos + 1)
    cmd_tail += bytes((0x85, 0x78))      # store: sta $78
    if SATURN_VOICE:
        cmd_tail[fx_voice_done] = len(cmd_tail) - (fx_voice_done + 1)
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
        """Per-player: L+R sets flag=MAGIC, SELECT clears it, then latch mirrors
        it for this round. Returns (bytes, [(pos, kind)]) where each entry is a
        jump-to-`orig` needing fixup — kind 'brl' = 3-byte relative-long (the
        stub outgrew 8-bit branch range in v0.11.7; brl removes the class of
        bug entirely)."""
        b = bytearray()
        fix = []
        b += bytes((0xE2, 0x20))                             # sep #$20
        b += bytes((0xA5, 0x36, 0xC9, 0x7F, 0xF0, 0x03))     # ==7F: skip the brl
        b += bytes((0x82, 0x00, 0x00)); fix.append(len(b) - 2)   # operand idx
        # LONG reads (v0.11.7): these were DB-relative `lda $4218` — the stub is
        # JSL'd with the caller's DB, so it sampled WRAM garbage instead of the
        # pad, and the L+R arming NEVER actually worked. It only appeared to
        # because the game's own menu code wrote 1 to the old latch address
        # ($C3:B9F5 -> $1F62); moving the flags off that address exposed it.
        b += bytes((0xAF, pad_lo & 0xFF, pad_lo >> 8, 0x00, 0x29, 0x30, 0xC9, 0x30, 0xD0, 0x06))
        b += bytes((0xA9, SATURN_MAGIC, 0x8F, flag & 0xFF, flag >> 8, SATURN_BANK))
        b += bytes((0xAF, pad_hi & 0xFF, pad_hi >> 8, 0x00, 0x29, 0x20, 0xF0, 0x06))
        b += bytes((0xA9, 0x00, 0x8F, flag & 0xFF, flag >> 8, SATURN_BANK))
        # latch = MAGIC iff flag == MAGIC, else 0 (never leaves a stale latch)
        b += bytes((0xAF, flag & 0xFF, flag >> 8, SATURN_BANK))
        b += bytes((0xC9, SATURN_MAGIC, 0xF0, 0x04))         # beq armed
        b += bytes((0xA9, 0x00, 0x80, 0x02))                 # lda #0 / bra store
        b += bytes((0xA9, SATURN_MAGIC))                     # armed:
        b += bytes((0x8F, latch & 0xFF, latch >> 8, SATURN_BANK))   # store:
        b += bytes((0xC9, SATURN_MAGIC, 0xF0, 0x03))         # armed: skip the brl
        b += bytes((0x82, 0x00, 0x00)); fix.append(len(b) - 2)   # operand idx
        return b, fix
    d = bytearray()
    d += bytes((0x08, 0xC2, 0x30))                       # php / rep #$30
    d += bytes((0x48, 0xDA, 0x5A))                       # pha / phx / phy
    d += bytes((0xA5, 0x30, 0xC9, 0x00, 0x6A, 0xF0, 0x00))   # ==$6A00 -> p1eff
    fp1 = len(d) - 1
    d += bytes((0xC9, 0x00, 0x73, 0xF0, 0x00))               # ==$7300 -> p2eff
    fp2 = len(d) - 1
    d += bytes((0x82, 0x00, 0x00))                           # brl orig
    forig = [len(d) - 2]
    p1eff = len(d)
    b1, f1 = _flagblock(0x4218, 0x4219, SATURN_FLAG, SATURN_LATCH)
    d += b1
    d += bytes((0x82, 0x00, 0x00))                           # brl copy
    fcopy = len(d) - 2
    p2eff = len(d)
    b2, f2 = _flagblock(0x421A, 0x421B, SATURN_FLAG2, SATURN_LATCH2)
    d += b2
    copy = len(d)
    d += bytes((0xC2, 0x30))                             # rep #$30
    d += bytes((0xA2, 0x00, EE_TILES >> 8, 0xA0, 0x00, 0x00,
                0xA9, 0x3F, 0x10, 0x8B, 0x54, 0x7F, B_MISC, 0xAB))
    orig = len(d)
    def _rel8(pos, target, what):
        off = target - (pos + 1)
        assert -128 <= off <= 127, f"{what}: 8-bit branch out of range ({off})"
        d[pos] = off & 0xFF
    def _rel16(pos, target, what):
        assert d[pos - 1] == 0x82, f"{what}: not a brl operand slot"
        off = target - (pos + 2)                          # brl: PC after operand
        assert -32768 <= off <= 32767, f"{what}: brl out of range"
        d[pos] = off & 0xFF
        d[pos + 1] = (off >> 8) & 0xFF
    _rel8(fp1, p1eff, "fp1")
    _rel8(fp2, p2eff, "fp2")
    _rel16(forig[0], orig, "bra orig")
    _rel16(fcopy, copy, "bra copy")
    for base_, fixes in ((p1eff, f1), (p2eff, f2)):
        for off_ in fixes:
            _rel16(base_ + off_, orig, "flagblock -> orig")
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
    bankmap = {0xDD: B_CEL0, 0xDE: B_CEL1, 0xDF: B_CEL2}
    for c in range(X.NCELS):
        sz = crec[5 * c + 3] | crec[5 * c + 4] << 8
        if sz == 0:
            # v0.11.11 — THE SCREEN-WIDE CORRUPTION BUG. A zero-size record is
            # the "no cel" sentinel, and SMS's engine recognises it by the
            # record being ALL ZEROS (every vanilla character's record 0 is
            # 00 00 00 00 00). Saturn's record 0 is `40 0D DD 00 00`: a
            # non-null address with size 0. On the SMS engine that is not
            # recognised as "skip", so it kicks a DMA with length 0 — which on
            # the SNES means 65536 bytes — from an unrebased Super S bank into
            # VRAM, obliterating every tile on screen. It fires whenever a pose
            # resolves to cel 0 (the hit/throw reaction states), persists
            # across rounds (VRAM is only fully rebuilt at match load) and
            # clears at the match end: exactly the field report. Normalise
            # zero-size records to SMS's all-zero sentinel.
            crec[5 * c:5 * c + 5] = bytes((EE_BLANKCEL & 0xFF, EE_BLANKCEL >> 8,
                                           B_MISC, EE_BLANKCEL_SZ & 0xFF,
                                           EE_BLANKCEL_SZ >> 8))
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
    assert bank == B_MISC, f"bank layout drift: ${bank:02X}"
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
    # confirm-site chaining (v0.11.5): on a REF base the site holds patch 5's
    # 4-byte JSL (alt-palette/default-stage hook), which itself replicates the
    # displaced head (rep #$30 / lda [$FE]). Our stub's tail then CALLS that
    # displaced JSL instead of replicating the head, preserving both hooks.
    conf_head = bytes(data[CHARSEL_CONFIRM:CHARSEL_CONFIRM + 4])
    if conf_head == CHARSEL_CONFIRM_OLD:
        confirm_tail = bytes((0xC2, 0x30, 0xA7, 0xFE))
    elif conf_head[0] == 0x22:
        confirm_tail = conf_head                      # chain the displaced JSL
    else:
        raise SystemExit(f"error: unrecognized confirm head {conf_head.hex()}")

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
        c += bytes((0xE2, 0x20, 0xA9, SATURN_MAGIC))
        lbl("setflag")
        c += bytes((0xC0, 0x40, 0x1B)); br(0xD0, "p2f")
        c += bytes((0x8F, SATURN_FLAG & 0xFF, SATURN_FLAG >> 8, SATURN_BANK)); br(0x80, "finish")
        lbl("p2f")
        c += bytes((0x8F, SATURN_FLAG2 & 0xFF, SATURN_FLAG2 >> 8, SATURN_BANK))
        lbl("finish")
        c += confirm_tail + bytes((0x6B,))   # original head or chained JSL / rtl
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
        c += bytes((0xA9, SATURN_MAGIC)); br(0x80, "store")
        lbl("noflag")
        c += bytes((0xA9, 0x00))
        lbl("store")
        c += bytes((0xC0, 0x40, 0x1B)); br(0xD0, "p2f")
        c += bytes((0x8F, SATURN_FLAG & 0xFF, SATURN_FLAG >> 8, SATURN_BANK)); br(0x80, "finish")
        lbl("p2f")
        c += bytes((0x8F, SATURN_FLAG2 & 0xFF, SATURN_FLAG2 >> 8, SATURN_BANK))
        lbl("finish")
        c += confirm_tail + bytes((0x6B,))   # original head or chained JSL / rtl
        fix()
    assert len(c) <= 0x100, f"confirm stub too big: {len(c)}"
    ee[EE_CONFIRM:EE_CONFIRM + len(c)] = c

    # transform palette copier (see EE_PALCOPY): fighter row + effects row
    pc_ = bytearray()
    pc_ += bytes((0x64, 0x0D, 0xA5, 0x0E, 0x18, 0x69, 0x00, 0x85, 0x0C,
                  0xA9, 0x06, 0x85, 0x0D))       # $0C/0D = $06:row
    pc_ += bytes((0xDA, 0xA0, 0x1F, 0x00))       # phx / ldy #$001F
    pc_ += bytes((0xBB, 0xBF, 0x00, 0xC0, B_MISC, 0x91, 0x0C,
                  0x88, 0x10, (0x100 - 10) & 0xFF))   # fighter row loop
    pc_ += bytes((0xA9, 0x40, 0x85, 0x0C))       # -> $0640 (OBJ pal 2)
    pc_ += bytes((0xA0, 0x1F, 0x00))
    pc_ += bytes((0xBB, 0xBF, 0x60, 0xC0, B_MISC, 0x91, 0x0C,
                  0x88, 0x10, (0x100 - 10) & 0xFF))   # effects row loop
    pc_ += bytes((0xFA, 0x6B))                   # plx / rtl
    ee[EE_PALCOPY:EE_PALCOPY + len(pc_)] = pc_

    # -- win-screen records + stubs (v0.11.3, see WIN_* constants) --
    def _win_rec(p_):
        h_ = sup[0x020000 + p_:0x020000 + p_ + 6]
        rl_, rows_ = h_[2] | h_[3] << 8, h_[4] | h_[5] << 8
        assert 0 < rl_ <= 0x40 and 0 < rows_ <= 8, f"win rec {p_:#x} shape {rl_}x{rows_}"
        return bytes(sup[0x020000 + p_:0x020000 + p_ + 6 + rl_ * rows_])
    np_ = _win_rec(SUP_WIN_NP)
    assert len(np_) == 126
    ee[EE_WIN_NP:EE_WIN_NP + len(np_)] = np_
    qcur = EE_WIN_QREC
    qarr = bytearray()
    for qi in range(7):
        w = sup[0x020000 + SUP_WIN_QARR + 2 * qi] | sup[0x020000 + SUP_WIN_QARR + 2 * qi + 1] << 8
        if w == 0:
            qarr += bytes((0, 0))
            continue
        r = _win_rec(w)
        ee[qcur:qcur + len(r)] = r
        qarr += bytes((qcur & 0xFF, qcur >> 8))
        qcur += len(r)
    assert qcur <= 0xC800, f"quote records overrun: {qcur:#x}"
    ee[EE_WIN_QARR:EE_WIN_QARR + 14] = qarr

    # name-plate stub (M=16, X=8 at entry; X = winner id*2)
    w1, lbl, br, fix = _asm()
    w1 += bytes((0xE0, 0x38)); br(0xD0, "orig")          # cpx #$38
    w1 += bytes((0xA9, EE_WIN_NP & 0xFF, EE_WIN_NP >> 8, 0x85, 0x74))
    w1 += bytes((0xA0, B_MISC, 0x84, 0x76, 0x6B))
    lbl("orig")
    w1 += bytes((0xBF, 0x08, 0xE0, 0x82, 0x85, 0x74))
    w1 += bytes((0xA0, 0x82, 0x84, 0x76, 0x6B))
    fix()
    assert len(w1) <= EE_WINSTUB_QT - EE_WINSTUB_NP
    ee[EE_WINSTUB_NP:EE_WINSTUB_NP + len(w1)] = w1

    # quote stub: replicates table+variant-select+deref through the bank store
    w2, lbl, br, fix = _asm()
    w2 += bytes((0xE0, 0x38)); br(0xD0, "orig")
    w2 += bytes((0xAD, 0x09, 0x1E, 0x29, 0xFE, 0x00, 0x18))   # lda $1E09/and/clc
    w2 += bytes((0x69, EE_WIN_QARR & 0xFF, EE_WIN_QARR >> 8, 0x85, 0x10))
    w2 += bytes((0xA9, B_MISC, 0x00, 0x85, 0x12))
    w2 += bytes((0xA7, 0x10, 0x85, 0x74, 0xA0, B_MISC, 0x84, 0x76, 0x6B))
    lbl("orig")
    w2 += bytes((0xBF, 0x1C, 0xE0, 0x82, 0x85, 0x10))
    w2 += bytes((0xAD, 0x09, 0x1E, 0x29, 0xFE, 0x00, 0x18, 0x65, 0x10, 0x85, 0x10))
    w2 += bytes((0xA9, 0x82, 0x00, 0x85, 0x12))
    w2 += bytes((0xA7, 0x10, 0x85, 0x74, 0xA0, 0x82, 0x84, 0x76, 0x6B))
    fix()
    assert len(w2) <= EE_WIN_NP - EE_WINSTUB_QT
    ee[EE_WINSTUB_QT:EE_WINSTUB_QT + len(w2)] = w2

    # v0.11.4: effect tiles decompressed straight from the Super S ROM — no
    # more fixture dependency, and the FULL 0x1040-byte sheet (the old 0xC00
    # dump undercut the P1 transfer by 0x440 bytes). Decompressor + job-table
    # knowledge: tools/saturn/supers_lz.py (validated byte-exact vs live
    # staging). Her jobs: table idx 57 (P1, VRAM $6A00) / 67 (P2, $7300),
    # both -> stream $E3:FA09.
    import supers_lz
    tb = supers_lz.lz_decompress(sup, supers_lz.SATURN_FX_SRC)
    assert len(tb) == 0x1040, f"effect sheet size drift: {len(tb):#x}"
    src_chk, vram_chk, _fl = supers_lz.job_entry(sup, 57)
    assert src_chk == supers_lz.SATURN_FX_SRC and vram_chk == 0x6A00, "job table drift"
    ee[EE_TILES:EE_TILES + len(tb)] = tb
    assert ee[EE_BLANKCEL:EE_BLANKCEL + EE_BLANKCEL_SZ] == bytes(EE_BLANKCEL_SZ), \
        "blank-cel region is not zero-filled"

    # -- her report-card portrait + the loader wrapper (v0.12.0) --
    # Her card art is CONVERTED from a 1:1 capture of Super S's card by
    # tools/saturn/mkportrait.py: the portrait is a fixed 31-sprite composition
    # (OBJ tiles $00-$43, OBJ palette 0 = CGRAM row 8) that is identical for
    # every character, so the converter samples the capture through that exact
    # composition and emits tiles at the same tile numbers. Dropping Super S's
    # own portrait bytes in raw does NOT work — the two games' portraits are
    # different artwork in a different arrangement (checked: no Super S
    # portrait job matches SMS's own card art above noise).
    pfile = REPO / "build" / "saturn" / "portrait_saturn.bin"
    ppal = REPO / "build" / "saturn" / "portrait_saturn.pal"
    if SATURN_PORTRAIT and not (pfile.is_file() and ppal.is_file()):
        raise SystemExit("error: portrait art missing — run tools/saturn/mkportrait.py "
                         "--convert mockups/saturn_win.png traces/saturn/oamcard_oam.bin "
                         f"{pfile} {ppal}")
    portrait = pfile.read_bytes() if pfile.is_file() else bytes(0x880)
    assert ee[EE_PORTRAIT:EE_PORTRAIT + len(portrait)] == bytes(len(portrait)), \
        "portrait slot is not free"
    ee[EE_PORTRAIT:EE_PORTRAIT + len(portrait)] = portrait
    PSIZE = len(portrait)
    if ppal.is_file():
        ee[EE_PORTPAL:EE_PORTPAL + 32] = ppal.read_bytes()[:32]

    # -- her own sprite list + the $C0:9E86 substitution stub (selector) --
    lfile = REPO / "build" / "saturn" / "portrait_list.bin"
    if SATURN_PORTRAIT and not lfile.is_file():
        raise SystemExit("error: sprite list missing — run "
                         f"tools/saturn/mkportrait.py --list {lfile}")
    if lfile.is_file():
        sl = lfile.read_bytes()
        assert len(sl) == 1 + 6 * sl[0], f"malformed sprite list: {len(sl)} B"
        assert ee[EE_SPRLIST:EE_SPRLIST + len(sl)] == bytes(len(sl)), \
            "sprite-list slot is not free"
        ee[EE_SPRLIST:EE_SPRLIST + len(sl)] = sl

    # X = object base, DP = 0 (same convention as the code we displace). We only
    # substitute when the pointer being loaded IS the card's portrait list
    # ($9F:CBEC) — that identifies the report card unambiguously, so nothing
    # in-match can trip it — AND the slot's Saturn flag is set.
    lh, llbl, lbr, lfix = _asm()
    lh += bytes((0x08, 0xC2, 0x30))                     # php / rep #$30
    lh += bytes((0xB5, 0x64, 0x85, 0x12, 0xB5, 0x66, 0x85, 0x14))   # displaced
    # Bank $9F alone identifies the report card. Do NOT also compare the pointer
    # against one character's list: Saturn can be summoned over ANY of the nine
    # (L+R on any slot), and the card then draws THAT character's list, so a
    # test against Uranus's $9F:CBEC silently disabled the whole feature for
    # every other shell — the field saw each shell's own untouched portrait.
    # Measured safe: across a full boot-to-card run this renderer loads exactly
    # one pointer, the card's; nothing in-match reaches it.
    lh += bytes((0xC9, 0x9F, 0x00)); lbr(0xD0, "lend")  # bank must be $9F
    if not SATURN_PORTRAIT_FORCE:
        lh += bytes((0xE2, 0x20))                       # sep #$20
        lh += bytes((0xAF, SITE_WINNER & 0xFF, SITE_WINNER >> 8, 0x7E))
        lh += bytes((0xC9, 0x01)); lbr(0xF0, "l1")      # winner == P1?
        lh += bytes((0xC9, 0x02)); lbr(0xD0, "lend")    # winner == P2?
        lh += bytes((0xAF, SATURN_FLAG2 & 0xFF, SATURN_FLAG2 >> 8, SATURN_BANK))
        lbr(0x80, "lchk")
        llbl("l1")
        lh += bytes((0xAF, SATURN_FLAG & 0xFF, SATURN_FLAG >> 8, SATURN_BANK))
        llbl("lchk")
        lh += bytes((0xC9, SATURN_MAGIC)); lbr(0xD0, "lend")
        lh += bytes((0xC2, 0x20))                       # rep #$20
    llbl("lsub")
    lh += bytes((0xA9, EE_SPRLIST & 0xFF, EE_SPRLIST >> 8, 0x85, 0x12))
    # $14 becomes the emitter's DATA BANK (`lda $14 / pha / plb` at $C0:9EA6), and
    # the emitter also writes the OAM shadow with plain absolute stores — so the
    # bank MUST be a $80-$BF one that carries the WRAM mirror. $EE:8000-$FFFF is
    # the same ROM as $AE:8000-$FFFF, so we hand it the mirror alias. (Vanilla
    # gets this for free: its list lives in $9F.) With $EE the portrait vanished
    # entirely — every `sta $0200,X` went to ROM.
    lh += bytes((0xA9, B_MISC - 0x40, 0x00, 0x85, 0x14))
    # Palette, EVERY frame. A one-shot copy at card build does not stick: the
    # engine re-fills the CGRAM shadow ($7E:0500, DMA'd whole at $80:849F) from
    # its own source afterwards, and that refill is invisible to write callbacks
    # (it is itself a transfer). This hook runs once per drawn frame while the
    # portrait is on screen and lands before vblank, so re-seeding row 8
    # ($7E:0600 = OBJ palette 0 = colours 128-143) here always wins.
    # Tiles, if the card-build hook could not do them (the winner is not always
    # latched that early — the field hit this in both a 1P-vs-COM loss and a 2P
    # win). This path runs with the card already on screen, so it costs one
    # force-blanked frame, once.
    lh += bytes((0xE2, 0x20))                           # sep #$20
    lh += bytes((0xAF, SATURN_MARK & 0xFF, SATURN_MARK >> 8, SATURN_BANK))
    lh += bytes((0xC9, SATURN_MAGIC)); lbr(0xF0, "haveTiles")
    lh += bytes((0xA9, SATURN_MAGIC, 0x8F, SATURN_MARK & 0xFF, SATURN_MARK >> 8, SATURN_BANK))
    lh += bytes((0xC2, 0x30, 0xA9, 0x00, 0x00,
                 0x8F, 0x04, 0xF1, SATURN_BANK))        # dest = VRAM $0000
    lh += bytes((0xDA, 0x5A))                           # phx / phy
    lh += bytes((0x22, EE_BLIT & 0xFF, EE_BLIT >> 8, B_MISC))
    lh += bytes((0x7A, 0xFA))                           # ply / plx
    llbl("haveTiles")
    lh += bytes((0xC2, 0x20))                           # rep #$20
    lh += bytes((0xDA, 0xA0, 0x1F, 0x00))               # phx / ldy #$001F
    llbl("pcopy")
    lh += bytes((0xBB,))                                # tyx
    lh += bytes((0xBF, EE_PORTPAL & 0xFF, EE_PORTPAL >> 8, B_MISC))
    lh += bytes((0x9F, 0x00, 0x06, 0x7E))               # sta $7E0600,X
    lh += bytes((0x88, 0x10, (0x100 - 12) & 0xFF))      # dey / bpl pcopy
    lh += bytes((0xFA,))                                # plx (the caller needs X)
    llbl("lend")
    lh += bytes((0x28, 0x6B))                           # plp / rtl
    lfix()
    assert len(lh) <= 0xC0, f"list-hook stub too big: {len(lh)}"
    assert ee[EE_LISTHOOK:EE_LISTHOOK + len(lh)] == bytes(len(lh)), \
        "list-hook slot is not free"
    ee[EE_LISTHOOK:EE_LISTHOOK + len(lh)] = lh

    # ---- EE_BLIT: upload her card tiles + palette. Callable from BOTH hooks.
    # The tile upload used to happen only at card-build time, gated on the
    # winner ($7E:1E14). The field showed her portrait as scrambled tiles that
    # differed every match — the signature of the SPRITE LIST being substituted
    # (it is re-read every frame) while the TILES were never uploaded, so her
    # layout drew whatever the portrait VRAM window still held. So the blit is
    # now idempotent and self-healing: whichever hook first sees a settled
    # "this is Saturn's card" does it, and a marker stops the other repeating it.
    # Destination comes from $7F:F104 (the address the vanilla loader was given;
    # the card always builds the winner's portrait at VRAM $0000). Scratch lives
    # in $7F, never in direct page, because the per-frame caller is inside the
    # sprite renderer and DP there belongs to it.
    bl, blbl, bbr, bfix = _asm()
    bl += bytes((0x08, 0xC2, 0x30, 0x48, 0xDA, 0x5A))   # php/rep #$30/pha/phx/phy
    bl += bytes((0xAF, 0x04, 0xF1, SATURN_BANK))        # A = VRAM word address
    bl += bytes((0x48,))                            # save dest
    bl += bytes((0xE2, 0x20, 0xAF, 0x00, 0x21, 0x00,
                 0x8F, SATURN_INIDISP & 0xFF, SATURN_INIDISP >> 8, SATURN_BANK))
    bl += bytes((0xA9, 0x8F, 0x8D, 0x00, 0x21))     # force blank (brightness 15)
    bl += bytes((0xC2, 0x20, 0x68))                 # restore dest
    bl += bytes((0x8D, 0x16, 0x21))                 # sta $2116
    bl += bytes((0xE2, 0x20, 0xA9, 0x80, 0x8D, 0x15, 0x21))   # sep/VMAIN=$80
    bl += bytes((0xA9, 0x01, 0x8D, 0x00, 0x43))     # DMA mode 1 (2 regs)
    bl += bytes((0xA9, 0x18, 0x8D, 0x01, 0x43))     # B-bus $2118
    bl += bytes((0xC2, 0x20))
    bl += bytes((0xA9, EE_PORTRAIT & 0xFF, EE_PORTRAIT >> 8, 0x8D, 0x02, 0x43))
    bl += bytes((0xE2, 0x20, 0xA9, B_MISC, 0x8D, 0x04, 0x43))
    bl += bytes((0xC2, 0x20, 0xA9, PSIZE & 0xFF, PSIZE >> 8, 0x8D, 0x05, 0x43))
    bl += bytes((0xE2, 0x20, 0xA9, 0x01, 0x8D, 0x0B, 0x42))   # kick channel 0
    # palette -> CGRAM row 8
    bl += bytes((0xA9, 0x80, 0x8D, 0x21, 0x21))               # CGADD = 128
    bl += bytes((0xA9, 0x00, 0x8D, 0x00, 0x43))               # DMA mode 0
    bl += bytes((0xA9, 0x22, 0x8D, 0x01, 0x43))               # B-bus $2122
    bl += bytes((0xC2, 0x20, 0xA9, EE_PORTPAL & 0xFF, EE_PORTPAL >> 8, 0x8D, 0x02, 0x43))
    bl += bytes((0xE2, 0x20, 0xA9, B_MISC, 0x8D, 0x04, 0x43))
    bl += bytes((0xC2, 0x20, 0xA9, 0x20, 0x00, 0x8D, 0x05, 0x43))
    bl += bytes((0xE2, 0x20, 0xA9, 0x01, 0x8D, 0x0B, 0x42))
    # ALSO seed the engine's CGRAM shadow for OBJ palette 0 ($7E:0600) — the
    # card re-uploads CGRAM from that shadow, which is what overwrote the direct
    # write above (the portrait palette is CGRAM row 8, measured).
    bl += bytes((0xC2, 0x30, 0xA0, 0x1F, 0x00))         # rep #$30 / ldy #$001F
    blbl("palcopy")
    bl += bytes((0xBB,))                                # tyx
    bl += bytes((0xBF, EE_PORTPAL & 0xFF, EE_PORTPAL >> 8, B_MISC))
    bl += bytes((0x9F, 0x00, 0x06, 0x7E))               # sta $7E0600,X
    bl += bytes((0x88, 0x10, (0x100 - 12) & 0xFF))      # dey / bpl palcopy
    # Restore INIDISP — but never restore a BLANK one. The blit force-blanks to
    # do its DMA and puts back what it saved; if it happens to run while the
    # screen is legitimately dark (a fade, brightness 0), it saves 0 and hands
    # the screen back still black. Nothing else rewrites the register on a
    # static card, so the card stays black until the player leaves it — which
    # is precisely the field report: black screen, correct music, and the
    # portrait flashing up correctly for a few frames on the way out. If the
    # saved brightness is zero we hand back full brightness instead; a fade in
    # progress overwrites it on its next frame anyway.
    bl += bytes((0xE2, 0x20, 0xAF, SATURN_INIDISP & 0xFF, SATURN_INIDISP >> 8, SATURN_BANK))
    bl += bytes((0x29, 0x0F)); bbr(0xD0, "keep")      # brightness bits set?
    bl += bytes((0xA9, 0x0F))                          # no -> full brightness
    blbl("keep")
    bl += bytes((0x8D, 0x00, 0x21))                    # -> INIDISP
    bl += bytes((0xC2, 0x30, 0x7A, 0xFA, 0x68, 0x28, 0x6B))   # restore / rtl
    bfix()
    assert len(bl) <= 0xC0, f"blit routine too big: {len(bl)}"
    assert ee[EE_BLIT:EE_BLIT + len(bl)] == bytes(len(bl)), "blit slot is not free"
    ee[EE_BLIT:EE_BLIT + len(bl)] = bl

    cp, lbl, br, fix = _asm()
    brl_fix = []
    # The loader uses DP $00-$0E as workspace, so the destination in $03 must be
    # stashed BEFORE calling it (v0.12.0 bring-up bug: reading $03 afterwards
    # gave garbage and the blit never ran). Entry A/flags belong to the loader.
    cp += bytes((0x08, 0xC2, 0x30, 0x48))          # php / rep #$30 / pha
    cp += bytes((0xA5, 0x03, 0x8F, 0x04, 0xF1, SATURN_BANK))   # stash dest
    cp += bytes((0x68, 0x28))                      # pla / plp
    cp += bytes((0x22, 0xEC, 0x8D, 0x80))          # the vanilla upload we wrap
    # The card-build wrapper now ONLY resets the marker. It used to blit here
    # too, but the portrait loader is called FIVE times per card and this site
    # does not always get the portrait window: a destination of $7800 was
    # logged. Blitting there put her tiles somewhere harmless and still marked
    # the job done, so the per-frame rescue stayed suppressed and the card kept
    # the SHELL's tiles under her layout — which is exactly what the field saw
    # ("a garbled mess, but a few tiles are definitely Uranus"). The per-frame
    # path always targets VRAM $0000, so it cannot make that mistake.
    cp += bytes((0x08, 0xC2, 0x30, 0x48, 0xDA, 0x5A))   # php/rep #$30/pha/phx/phy
    cp += bytes((0xE2, 0x20))                           # sep #$20
    cp += bytes((0xA9, 0x00, 0x8F, SATURN_MARK & 0xFF, SATURN_MARK >> 8, SATURN_BANK))
    lbl("done")
    cp += bytes((0xC2, 0x30, 0x7A, 0xFA, 0x68, 0x28, 0x6B))   # restore / rtl
    fix()
    done_at = len(cp) - 7    # the restore/rtl tail assembled last
    for pos in brl_fix:
        off = done_at - (pos + 2)
        cp[pos] = off & 0xFF
        cp[pos + 1] = (off >> 8) & 0xFF
    assert len(cp) <= 0xF0, f"card-portrait stub too big: {len(cp)}"
    ee[EE_CARDPORT:EE_CARDPORT + len(cp)] = cp
    write_bank(data, bankbase, bytes(ee))

    # ---- bank $EF: full SMS-$C1 copy + Saturn's ported proc block ----
    import port_saturn_proc as PSP
    blk, rep = PSP.patched_block(sup, bytes(data[:0x280000]))
    if rep["unresolved"]:
        raise SystemExit(f"error: proc port has unresolved refs: {rep['unresolved']}")
    bankbase, bank = next_bank(data)
    assert bank == B_C1, f"bank layout drift: ${bank:02X}"
    ef = bytearray(data[0x10000:0x20000])            # SMS bank $C1 copy (pre-patch)
    ef[PSP.BLOCK_LO:PSP.BLOCK_HI] = blk
    for addr, (old_id, new_id) in SPAWN_ID_FIX.items():
        assert ef[addr] == old_id, \
            f"spawn record {addr:#x}: expected id {old_id:#04x}, found {ef[addr]:#04x}"
        ef[addr] = new_id
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
    h += bytes((0x48, 0xAF, SATURN_LATCH2 & 0xFF, SATURN_LATCH2 >> 8, SATURN_BANK,
                0xC9, SATURN_MAGIC)); _br(0xD0, "popn")
    h += bytes((0xA9, 0x20)); _br(0x80, "gates") # A=palette-row hint 0x20 -> $0620
    _lbl("p1chk")
    h += bytes((0x48, 0xAF, SATURN_LATCH & 0xFF, SATURN_LATCH >> 8, SATURN_BANK,
                0xC9, SATURN_MAGIC)); _br(0xD0, "popn")
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
    h += bytes((0x22, EE_PALCOPY & 0xFF, EE_PALCOPY >> 8, B_MISC))
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
    # v0.11.8: the engine has MORE THAN ONE proc dispatcher — `jsr ($00A6,X)`
    # also lives at $C1:1708 (projectiles) and $C1:259E (the KO/round-end
    # path), plus sites in other banks. The main-loop hook at $C1:007C only
    # covers the first, and Saturn's proc-table entry was still 0000, so any
    # other dispatcher jumped to $C1:0000 = the main object loop, re-entering
    # the whole update recursively -> the engine stops (music/NMI keep running,
    # screen goes black). That is the maintainer's "crashed while fighting":
    # it fires whenever a KO happens with Saturn on screen.
    # Fix: point her table entry at the same $C1 mini-stub the projectiles use
    # and let tramp3 route id 0x1C to her dispatch first.
    # v0.11.9: the Saturn branch must ONLY run her character proc for the two
    # PLAYER slots ($1000/$1080). v0.11.8 pointed her proc-table entry here so
    # the engine's other dispatchers could reach her — but those iterate the
    # projectile ($1100) and effect ($1200) pools, so any pooled object that
    # happens to carry id 0x1C would have run her FULL character proc against
    # a non-player struct: a second copy of her sprite drawn from bogus state
    # (the maintainer's "5LK shows LP and LK at once") and her per-frame cel
    # streaming DMAing from garbage addresses (screen-wide tile corruption).
    # Non-player slots now self-clear, exactly like the projectile placeholder.
    tramp3 = bytes.fromhex(
        "C210"            # rep #$10
        "A688"            # ldx $88
        "B500"            # lda $00,X      (object id)
        "C91C" "F014"     # id == 0x1C -> saturn-gate
        "C920" "F008"     # 0x20
        "C921" "F008"     # 0x21
        "20A629" "6B"     # else 0x22 proc
        "200B28" "6B"     # 0x20 proc
        "20D328" "6B"     # 0x21 proc
        # saturn-gate: only $1000 / $1080 are real players
        "E00010" "F008"   # cpx #$1000 -> run
        "E08010" "F003"   # cpx #$1080 -> run
        "7400" "6B"       # else: stz $00,X (despawn) / rtl
        "20F7C6" "6B")    # run: jsr her dispatch / rtl
    assert len(tramp3) <= 0x60, f"tramp3 too big: {len(tramp3)}"
    ef[EF_TRAMP3:EF_TRAMP3 + len(tramp3)] = tramp3
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
    old, new = bytes((0x22, 0xB7, 0x9F, 0x80)), bytes((0x22, EF_SND & 0xFF, EF_SND >> 8, B_C1))
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
    assert bank == B_BOX, f"bank layout drift: ${bank:02X}"
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
    # every data block in this bank must be disjoint — see F0_COLL_D's comment
    _blocks = [("hit", F0_HIT_D, len(hitb)), ("hurt", F0_HURT_D, len(hurtb)),
               ("coll", F0_COLL_D, len(collb)),
               ("projhit", F0_PROJ_HIT_D, PROJ_HIT_N),
               ("projoam", 0xB4A6, PROJ_OAM_HI - PROJ_OAM_LO)]
    for _i, (_n1, _a1, _s1) in enumerate(_blocks):
        for _n2, _a2, _s2 in _blocks[_i + 1:]:
            assert _a1 + _s1 <= _a2 or _a2 + _s2 <= _a1, \
                f"bank $F0 layout: {_n1} ({_a1:#06x}+{_s1:#x}) overlaps {_n2} ({_a2:#06x}+{_s2:#x})"
    for _n, _a, _sz in _blocks:
        assert _a + _sz <= 0x10000, f"bank $F0: {_n} overruns the bank"
    f0[F0_PROJ_HIT_D:F0_PROJ_HIT_D + PROJ_HIT_N] = sup[PROJ_HIT_LO:PROJ_HIT_LO + PROJ_HIT_N]
    for pid in PROJ_SCRIPT_ENTRIES:
        f0[F0_HIT_T + 2 * pid:F0_HIT_T + 2 * pid + 2] = \
            bytes((F0_PROJ_HIT_D & 0xFF, F0_PROJ_HIT_D >> 8))
    # projectile OAM blob at its original in-bank offset (read via $B0 mirror)
    f0[0xB4A6:0xB4A6 + (PROJ_OAM_HI - PROJ_OAM_LO)] = sup[PROJ_OAM_LO:PROJ_OAM_HI]
    write_bank(data, bankbase, bytes(f0))

    # ---- bank $F1: her voice bank, its IPL streams, and the two load hooks ----
    if SATURN_VOICE:
        import importlib.util as _ilu
        _spec = _ilu.spec_from_file_location(
            "extract_saturn_voice", str(REPO / "tools" / "saturn" / "extract_saturn_voice.py"))
        _vx = _ilu.module_from_spec(_spec); _spec.loader.exec_module(_vx)
        vbank, ventries = _vx.build_bank()
        assert len(vbank) <= 0xDB00 - 0xB700, "voice bank overruns P2's bank at $DB00"

        def ipl(*blocks):
            """IPL stream: [size16][dest16][payload] per block, then [0000][0800].

            Takes (dest, payload) pairs — the vanilla select banks use two blocks
            in one stream, so this has to be plural. The zero-size terminator
            carries the driver's entry point ($0800); every vanilla stream ends
            that way, and the relocating loader zeroes dp $10 before reading it so
            the entry point is never offset."""
            out = bytearray()
            for dest, payload in blocks:
                out += bytes((len(payload) & 0xFF, len(payload) >> 8,
                              dest & 0xFF, dest >> 8)) + bytes(payload)
            return bytes(out + bytes((0x00, 0x00, 0x00, 0x08)))

        van = bytes(data[VOICE_SRC_ROM:VOICE_SRC_ROM + 32])
        assert van[0:2] == bytes((0x00, 0xB7)) and van[16:18] == bytes((0x00, 0xDB)), \
            "char 1's vanilla voice record is not the expected $B700/$DB00 pair"
        # her select line, in exactly the shape the nine vanilla select banks
        # use: a 4-byte directory write, then the sample, both to the same
        # addresses they use (the sample is a one-shot, so `loop` is only ever
        # the end and is never reached)
        vsel = _vx.build_select()
        selend = SEL_ARAM + len(vsel)
        seldir = bytes((SEL_ARAM & 0xFF, SEL_ARAM >> 8, selend & 0xFF, selend >> 8))
        streams = {
            V_SAMP:  ipl((0xB700, vbank)),                      # +$2400 for P2
            V_DIRP1: ipl((VOICE_DIR_ARAM, _vx.dir_blob(ventries, 0xB700))),
            V_DIRP2: ipl((VOICE_DIR_ARAM, _vx.dir_blob(ventries, 0xDB00))),
            V_RESP1: ipl((VOICE_DIR_ARAM, van[0:16])),
            V_RESP2: ipl((VOICE_DIR_ARAM, van[16:32])),
            V_SEL:   ipl((SEL_DIRW, seldir), (SEL_ARAM, vsel)),
        }
        # the P2 directory streams say $34C0 and are steered to $34D0 by dp $10
        f1 = bytearray(0x10000)
        for off, blob in streams.items():
            assert not any(f1[off:off + len(blob)]), f"voice bank layout: {off:#06x} overlaps"
            f1[off:off + len(blob)] = blob

        # --- the two load hooks ---------------------------------------------
        # Entered by JSL from the char loader with M=1/X=1 and A = the vanilla
        # bank id. $C0:EC5E returns with the index registers 16-bit, hence the
        # `sep #$30` after every call.
        def _asm(body):
            out, fix, lbls = bytearray(), [], {}

            def emit(*bs): out.extend(bs)

            def br(op, name):
                out.extend((op, 0x00)); fix.append((len(out) - 1, name))

            def lbl(name): lbls[name] = len(out)
            body(emit, br, lbl)
            for pos, name in fix:
                d = lbls[name] - (pos + 1)
                assert -128 <= d <= 127, f"voice hook branch to {name} out of range ({d})"
                out[pos] = d & 0xFF
            return bytes(out)

        def _load(emit, bank_id):
            emit(0xA9, bank_id, 0x22, 0x5E, 0xEC, 0x80, 0xE2, 0x30)

        def _setdp10(emit, val):
            emit(0xA9, val & 0xFF, 0x85, 0x10, 0xA9, val >> 8, 0x85, 0x11)

        def _p1(emit, br, lbl):
            emit(0x48)                                              # pha (bank id)
            emit(0xAF, SATURN_FLAG & 0xFF, SATURN_FLAG >> 8, SATURN_BANK)
            emit(0xC9, SATURN_MAGIC); br(0xF0, "sat")
            emit(0xAF, SATURN_LATCH & 0xFF, SATURN_LATCH >> 8, SATURN_BANK)
            emit(0xC9, SATURN_MAGIC); br(0xF0, "sat")
            # not Saturn: put char 1's own directory back if we dirtied it
            emit(0xAF, VOICE_DIRTY & 0xFF, VOICE_DIRTY >> 8, SATURN_BANK)
            emit(0xC9, SATURN_MAGIC); br(0xD0, "vanilla")
            emit(0xA5, 0x10, 0x48, 0xA5, 0x11, 0x48)                # save dp $10/$11
            _setdp10(emit, 0x0000)
            _load(emit, VOICE_ID_RESP1)
            emit(0x68, 0x85, 0x11, 0x68, 0x85, 0x10)                # restore dp
            emit(0xA9, 0x00, 0x8F, VOICE_DIRTY & 0xFF, VOICE_DIRTY >> 8, SATURN_BANK)
            lbl("vanilla")
            emit(0x68)                                              # pla
            emit(0x22, 0x4B, 0xEB, 0x80)                            # jsl $80:EB4B
            emit(0x6B)
            lbl("sat")
            emit(0xA5, 0x10, 0x48, 0xA5, 0x11, 0x48)
            _setdp10(emit, 0x0000)
            _load(emit, VOICE_ID_SAMP)                              # samples -> $B700
            _setdp10(emit, 0x0000)
            _load(emit, VOICE_ID_DIRP1)                             # directory -> $34C0
            emit(0x68, 0x85, 0x11, 0x68, 0x85, 0x10)
            emit(0xA9, SATURN_MAGIC, 0x8F, VOICE_DIRTY & 0xFF, VOICE_DIRTY >> 8, SATURN_BANK)
            emit(0x68, 0x6B)                                        # pla / rtl

        def _p2(emit, br, lbl):
            emit(0x48)
            emit(0xAF, SATURN_FLAG2 & 0xFF, SATURN_FLAG2 >> 8, SATURN_BANK)
            emit(0xC9, SATURN_MAGIC); br(0xF0, "sat")
            emit(0xAF, SATURN_LATCH2 & 0xFF, SATURN_LATCH2 >> 8, SATURN_BANK)
            emit(0xC9, SATURN_MAGIC); br(0xF0, "sat")
            emit(0xAF, VOICE_DIRTY2 & 0xFF, VOICE_DIRTY2 >> 8, SATURN_BANK)
            emit(0xC9, SATURN_MAGIC); br(0xD0, "vanilla")
            _setdp10(emit, 0x0010)                                  # -> $34D0
            _load(emit, VOICE_ID_RESP2)
            emit(0xA9, 0x00, 0x8F, VOICE_DIRTY2 & 0xFF, VOICE_DIRTY2 >> 8, SATURN_BANK)
            lbl("vanilla")
            _setdp10(emit, 0x2400)                                  # as the caller had it
            emit(0x68)
            emit(0x22, 0x5E, 0xEC, 0x80)                            # jsl $80:EC5E
            emit(0x6B)
            lbl("sat")
            _setdp10(emit, 0x2400)
            _load(emit, VOICE_ID_SAMP)                              # samples -> $DB00
            _setdp10(emit, 0x0010)
            _load(emit, VOICE_ID_DIRP2)                             # directory -> $34D0
            emit(0xA9, SATURN_MAGIC, 0x8F, VOICE_DIRTY2 & 0xFF, VOICE_DIRTY2 >> 8, SATURN_BANK)
            emit(0x68, 0x6B)

        # --- select-voice hooks ---------------------------------------------
        def _who(player):
            """Replacement for `lda $1B40|$1B80 / and #$00FF / sta $1B1E`, plus a
            note of WHICH PLAYER is being voiced. php/plp keeps the register
            widths the caller established (it is mid `rep #$30`), and A comes back
            holding the character id, which the next vanilla instruction asl/tax's."""
            src = 0x1B40 if player == 0 else 0x1B80
            return (bytes((0x08, 0xE2, 0x20))                       # php / sep #$20
                    + bytes((0xA9, player, 0x8F,
                             VOICE_PLAYER & 0xFF, VOICE_PLAYER >> 8, SATURN_BANK))
                    + bytes((0x28,))                                # plp
                    + bytes((0xAD, src & 0xFF, src >> 8))           # lda $1B40/$1B80
                    + bytes((0x29, 0xFF, 0x00))                     # and #$00FF
                    + bytes((0x8D, 0x1E, 0x1B))                     # sta $1B1E
                    + bytes((0x6B,)))                               # rtl

        def _selbank(emit, br, lbl):
            # entry: M=8-bit, X=16-bit = charID, DB = the caller's (so the vanilla
            # `lda $AE75,X` still resolves). Substitute her bank id when the
            # player being voiced is Saturn; otherwise do exactly what we replaced.
            emit(0xDA)                                              # phx
            emit(0xA2, 0x00, 0x00)                                  # ldx #$0000
            emit(0xAF, VOICE_PLAYER & 0xFF, VOICE_PLAYER >> 8, SATURN_BANK)
            br(0xF0, "p1")
            emit(0xA2, 0x01, 0x00)                                  # ldx #$0001
            lbl("p1")
            emit(0xBF, SATURN_FLAG & 0xFF, SATURN_FLAG >> 8, SATURN_BANK)  # lda $7FF100,X
            emit(0xFA)                                              # plx (restores charID)
            emit(0xC9, SATURN_MAGIC)
            br(0xD0, "vanilla")
            emit(0xA9, VOICE_SEL_ID)                                # lda #her bank
            br(0x80, "go")
            lbl("vanilla")
            emit(0xBD, 0x75, 0xAE)                                  # lda $AE75,X
            lbl("go")
            emit(0x22, 0x4B, 0xEB, 0x80)                            # jsl $80:EB4B
            emit(0x6B)

        # --- movelist ------------------------------------------------------
        _mspec = _ilu.spec_from_file_location(
            "mkmovelist", str(REPO / "tools" / "saturn" / "mkmovelist.py"))
        _mv = _ilu.module_from_spec(_mspec); _mspec.loader.exec_module(_mv)
        mlblob = _mv.sms_lz.encode(_mv.build())
        assert _mv.sms_lz.decompress(mlblob, 0, 0x800) == _mv.build(), \
            "movelist round-trip failed"

        def _mlhook(player):
            """Replacement for `lda $E0021C,X`, which the caller stores to $02.
            When this player is Saturn, point $00/$02 at her list instead; the
            vanilla path does exactly what it replaced. A/M is 16-bit here."""
            flag = SATURN_FLAG if player == 0 else SATURN_FLAG2
            latch = SATURN_LATCH if player == 0 else SATURN_LATCH2
            b = bytearray()
            b += bytes((0x08, 0xE2, 0x20))                       # php / sep #$20
            b += bytes((0xAF, flag & 0xFF, flag >> 8, SATURN_BANK))
            b += bytes((0xC9, SATURN_MAGIC, 0xF0, 0x0A))         # beq sat
            b += bytes((0xAF, latch & 0xFF, latch >> 8, SATURN_BANK))
            b += bytes((0xC9, SATURN_MAGIC, 0xF0, 0x02))         # beq sat
            b += bytes((0x80, 0x0A))                             # bra vanilla
            # sat: $00 = her pointer low word, A = her bank
            b += bytes((0x28,))                                  # plp (A 16-bit)
            b += bytes((0xA9, V_MOVELIST & 0xFF, V_MOVELIST >> 8, 0x85, 0x00))
            b += bytes((0xA9, B_VOICE, 0x00, 0x6B))              # lda #bank / rtl
            # vanilla:
            b += bytes((0x28,))                                  # plp
            b += bytes((0xBF, 0x1C, 0x02, 0xE0, 0x6B))           # lda $E0021C,X / rtl
            return bytes(b)

        for off, blob in ((V_MOVELIST, mlblob),
                          (V_MLHOOK1, _mlhook(0)), (V_MLHOOK2, _mlhook(1)),
                          (V_WHO1, _who(0)), (V_WHO2, _who(1)),
                          (V_SELHOOK, _asm(_selbank))):
            assert not any(f1[off:off + len(blob)]), f"select stub at {off:#06x} overlaps"
            f1[off:off + len(blob)] = blob

        for off, body in ((V_HOOK1, _p1), (V_HOOK2, _p2)):
            blob = _asm(body)
            assert not any(f1[off:off + len(blob)]), f"voice hook at {off:#06x} overlaps"
            f1[off:off + len(blob)] = blob
        # keep the full 64K: every other appended bank is a whole bank, and
        # mkstage_port.py (and anything else that stacks after us) requires a
        # bank-aligned image — a short final bank fails its guard outright.
        bankbase, bank = next_bank(data)
        assert bank == B_VOICE, f"bank layout drift: ${bank:02X}"
        write_bank(data, bankbase, bytes(f1))

        # table records for our five streams, in the verified zero run
        for slot, iid in ((V_SAMP, VOICE_ID_SAMP), (V_DIRP1, VOICE_ID_DIRP1),
                          (V_DIRP2, VOICE_ID_DIRP2), (V_RESP1, VOICE_ID_RESP1),
                          (V_RESP2, VOICE_ID_RESP2), (V_SEL, VOICE_SEL_ID)):
            rec = VOICE_TBL + 6 * iid
            expect(rec, b"\x00" * 6, f"audio-table record {iid} (must be free)")
            # [3-byte source][3-byte second source = none]; only $C0:EB4B reads
            # the second one, and it tests the low word against $FFFF
            data[rec:rec + 6] = bytes((slot & 0xFF, slot >> 8, B_VOICE, 0xFF, 0xFF, 0x00))
        expect(SITE_VOICE_P1, VOICE_P1_OLD, "P1 voice-bank load")
        data[SITE_VOICE_P1:SITE_VOICE_P1 + 4] = \
            bytes((0x22, V_HOOK1 & 0xFF, V_HOOK1 >> 8, B_VOICE))
        expect(SITE_VOICE_P2, VOICE_P2_OLD, "P2 voice-bank load")
        data[SITE_VOICE_P2:SITE_VOICE_P2 + 4] = \
            bytes((0x22, V_HOOK2 & 0xFF, V_HOOK2 >> 8, B_VOICE))
        # select-voice: the bank pick, and the three per-player $1B1E writers
        expect(SITE_SELBANK, SELBANK_OLD, "select-voice bank pick")
        data[SITE_SELBANK:SITE_SELBANK + 7] = \
            bytes((0x22, V_SELHOOK & 0xFF, V_SELHOOK >> 8, B_VOICE)) + b"\xEA" * 3
        for site, tgt in ((SITE_ML_P1, V_MLHOOK1), (SITE_ML_P2, V_MLHOOK2)):
            expect(site, ML_OLD, f"movelist table read {site:#x}")
            data[site:site + 4] = bytes((0x22, tgt & 0xFF, tgt >> 8, B_VOICE))
        for site, player in SITE_SELWHO:
            expect(site, SELWHO_OLD[player], f"select-voice $1B1E writer {site:#x}")
            tgt = V_WHO1 if player == 0 else V_WHO2
            data[site:site + 9] = \
                bytes((0x22, tgt & 0xFF, tgt >> 8, B_VOICE)) + b"\xEA" * 5

    # ---- engine patches ----
    data[SITE_INTERP_DB] = B_SCR
    expect(SITE_INTERP_CMD, INTERP_CMD_OLD, "interpreter ctrl decode")
    data[SITE_INTERP_CMD:SITE_INTERP_CMD + 8] = \
        bytes((0x22, E8_CMDSTUB & 0xFF, E8_CMDSTUB >> 8, B_SCR)) + b"\xEA" * 4
    expect(SITE_DMA_KICK, DMA_KICK_OLD, "generic VRAM-DMA kick")
    data[SITE_DMA_KICK:SITE_DMA_KICK + 8] = \
        bytes((0x22, E8_DMASTUB & 0xFF, E8_DMASTUB >> 8, B_SCR)) + b"\xEA" * 4
    # bank byte $AE (not $EE): the emitter WRITES the OAM shadow via DB-absolute
    # $0200,X — only $80-$BF banks mirror WRAM in the low half; $AE:8000+ mirrors
    # the same ROM bytes as $EE:8000+ (file 0x2E8000).
    data[SITE_OAM_ENTRY:SITE_OAM_ENTRY + 3] = bytes((0x00, 0x80, B_MISC - 0x40))  # WRAM-mirror bank
    data[SITE_POSE_DB] = B_POSE
    data[SITE_POSE_TBL:SITE_POSE_TBL + 2] = bytes((E9_TABLE & 0xFF, E9_TABLE >> 8))
    data[SITE_CEL_DB] = B_CELT
    data[SITE_CEL_T1:SITE_CEL_T1 + 2] = bytes((EA_TABLE & 0xFF, EA_TABLE >> 8))
    data[SITE_CEL_T2:SITE_CEL_T2 + 2] = bytes(((EA_TABLE + 2) & 0xFF, (EA_TABLE + 2) >> 8))
    hook = bytes((0x22, E8_STUB & 0xFF, E8_STUB >> 8, B_SCR)) + b"\xEA" * 7
    data[SITE_RECOG:SITE_RECOG + 11] = hook
    expect(SITE_PROC_HOOK, PROC_HOOK_OLD, "main proc-dispatch head")
    data[SITE_PROC_HOOK:SITE_PROC_HOOK + 7] = \
        bytes((0x22, EF_HELPER & 0xFF, EF_HELPER >> 8, B_C1)) + b"\xEA" * 3
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
            + bytes((0x22, EF_TRAMP3 & 0xFF, EF_TRAMP3 >> 8, B_C1, 0x60)) + b"\xFF" * 2
    import os
    if os.environ.get("SATURN_SKIP") != "box":
        for site in BOX_PLB_SITES:
            data[site + 1] = B_BOX - 0x40
        for site, (old, new) in BOX_READS.items():
            data[site + 1:site + 3] = bytes((new & 0xFF, new >> 8))
    # -- v0.10.0 char-select 10th slot / v0.11.0 hidden-code variant --
    assert bytes(data[CHARSEL_CONFIRM:CHARSEL_CONFIRM + 4]) == conf_head
    data[CHARSEL_CONFIRM:CHARSEL_CONFIRM + 4] = \
        bytes((0x22, EE_CONFIRM & 0xFF, EE_CONFIRM >> 8, B_MISC))
    if not SATURN_HIDDEN:
        expect(CHARSEL_DRAW1, CHARSEL_DRAW1_OLD, "draw-blk1 head")
        data[CHARSEL_DRAW1:CHARSEL_DRAW1 + 5] = \
            bytes((0x22, EE_DRAW1 & 0xFF, EE_DRAW1 >> 8, B_MISC, 0x60))
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
    # -- v0.11.3 win-screen per-id table hooks --
    for site in WIN_NP_SITES:
        expect(site, WIN_NP_OLD, f"win nameplate site {site:#x}")
        data[site:site + 10] = \
            bytes((0x22, EE_WINSTUB_NP & 0xFF, EE_WINSTUB_NP >> 8, B_MISC)) + b"\xEA" * 6
    for site in WIN_QT_SITES:
        expect(site, WIN_QT_OLD, f"win quote site {site:#x}")
        data[site:site + 30] = \
            bytes((0x22, EE_WINSTUB_QT & 0xFF, EE_WINSTUB_QT >> 8, B_MISC)) + b"\xEA" * 26
    # Saturn's own proc-table entry (v0.11.8): every dispatcher can now reach her
    sat_site = 0x100A6 + 2 * SAT_ID
    expect(sat_site, b"\x00\x00", "proc-table entry 0x1c (must be free)")
    data[sat_site:sat_site + 2] = bytes(((SITE_BTN + 4) & 0xFF, ((SITE_BTN + 4) - 0x10000) >> 8))
    if SATURN_PORTRAIT:
        expect(SITE_CARDLOAD, CARDLOAD_OLD, "card portrait loader call")
        data[SITE_CARDLOAD:SITE_CARDLOAD + 4] = \
            bytes((0x22, EE_CARDPORT & 0xFF, EE_CARDPORT >> 8, B_MISC))
        # selector: give her her own sprite list (both reads of +0x64/+0x66)
        expect(SITE_LISTPTR, LISTPTR_OLD, "portrait sprite-list pointer load")
        data[SITE_LISTPTR:SITE_LISTPTR + 8] = \
            bytes((0x22, EE_LISTHOOK & 0xFF, EE_LISTHOOK >> 8, B_MISC)) + b"\xEA" * 4
        expect(SITE_LISTBANK, LISTBANK_OLD, "portrait list data-bank re-read")
        data[SITE_LISTBANK:SITE_LISTBANK + 2] = bytes((0xA5, 0x14))  # lda $14
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
        data[site:site + 3] = bytes((0xA6, 0xB4, B_BOX - 0x40))

    fix_checksum(data)
    open(out_path, "wb").write(data)
    print(f"wrote {out_path}: saturn-smoke v{VARIANT_STR}, {len(data):#x} bytes, "
          f"Saturn object id {SAT_ID:#04x}, {nscripts} scripts (CMD-intact)")
    print("sha1", hashlib.sha1(bytes(data)).hexdigest())


if __name__ == "__main__":
    main()
