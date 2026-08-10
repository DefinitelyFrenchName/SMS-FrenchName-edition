#!/usr/bin/env python3
"""EXPERIMENT (not a numbered patch, not canonical): give Venus an AIR BACKDASH.

    python3 tools/exp_airbackdash.py <out.sfc> [--keep-air-invuln]

A throwaway probe of one design question — "if the handler gates that restrict
which acts you can reach were relaxed, could you get air movement?" — kept
deliberately outside the patch registry: no number, no SIG, no entry in
patch_index/patch_notes, no mksigs/checkknobs row, no release. The `exp_` name
is the marker; `mkpatchN.py` is the name that means "tracked".

WHY VENUS. Her jump handlers (acts 0x06/0x07/0x08 at $C1:6DFB/$6E2E/$6E67)
already end with `ldy #$6C1F / jsr $0958` — they already offer the special-start
table — while EVERY entry in that table is ground-flagged, so today that call
provably cannot produce anything airborne. She is the one character where this
changes exactly one thing.

---------------------------------------------------------------------------
THE ROUTE NOT TAKEN, and why — measured, not reasoned.

The obvious edit is the special-start table's flag byte: the starter at
$C1:097F reads bit0 = ground-only, bit1 = air-only, as an IF/ELSE, so 0x00 is
"no restriction". The backdash is entry 0/1 (`26/01 26/01`) of all nine tables,
so clearing those two bytes ought to be the whole job.

It is not, and the reason only shows up on a frame trace. The starter is called
EVERY frame the act runs, and the pending command in +0x51 stays latched for
several frames, so it re-fires the act repeatedly; each re-fire goes through
$C1:0224, which zeroes the step, which re-runs the handler's step-0 init. On the
CLEAN ROM that retry is rejected from frame 2 onward, because the backdash hop
has already left the ground and the entry is ground-flagged — the flag is what
stops the loop. Clear it and the loop runs. Measured on the fixture:

    clean            act 0x26 for 15 frames, step 0 -> 1 on frame 2
    flags cleared    act 0x26 for 22 frames, step pinned at 0 for six frames,
                     travelling further

So the flag edit does not "add an air option": it also lengthens and extends the
GROUNDED backdash, which is the tool the maintainer asked to leave alone. It
also makes the backdash re-startable out of itself mid-hop, i.e. unbounded
chaining of an invulnerable state.

---------------------------------------------------------------------------
WHAT THIS BUILDS INSTEAD. The special-start table is not touched at all, so the
grounded backdash keeps its flags, its 15 frames and its invulnerability
byte-for-byte. The air backdash is started directly by the three jump handlers,
as its own act:

  * act 0x2B, one of the 21 null slots every character has at 0x2B-0x3F,
    becomes a second entry point to the SAME backdash handler ($C1:722C) — same
    velocities, same hop, same landing check, no new code.
  * its animation is her JUMP-BACK script ($C0:0E3A), by pointing the null
    script-table slot at it. One pointer, no new art. Those seven poses carry
    real hurtboxes ($14-$1B), where the backdash's own poses ($5E/$5F) are
    `hurt 00` — the empty hurtbox that IS this engine's invulnerability. That is
    the whole answer to "invincible air movement is no good, but the grounded
    backdash must stay invincible": ground and air only shared invulnerability
    because they shared one act, and now they do not.
  * the jump handlers' `jsr $0958` is rerouted to a stub that runs the vanilla
    call first, then starts act 0x2B if a back double-tap is pending and she is
    airborne.

It also self-limits: act 0x2B's handler offers only the vanilla special route,
whose entries are all still ground-flagged, so an air backdash cannot start
another one. ONE PER JUMP, with no counter and no apex window — the restriction
falls out of the data being left alone.

--keep-air-invuln starts act 0x26 instead, i.e. the air backdash with the
backdash's own invulnerable animation, so the two can be flown side by side.
The grounded backdash is untouched in that variant too.

EDITS (file offsets; every one asserted before it is written):

  0x000D7E  00 00 -> 3A 0E    Venus script table $C0:0D28 + 0x2B*2 -> $C0:0E3A
  0x016B6F  00 00 -> 2C 72    Venus act table   $C1:6B19 + 0x2B*2 -> $C1:722C
  0x016E28  20 58 09 -> 20 80 BF    act 0x06 jump-up   starter call -> stub
  0x016E61  20 58 09 -> 20 80 BF    act 0x07 jump-fwd  starter call -> stub
  0x016E9A  20 58 09 -> 20 80 BF    act 0x08 jump-back starter call -> stub
  0x01BF80  25-byte stub at $C1:BF80

  (--keep-air-invuln writes the three hooks and the stub only; the two table
  slots stay null because act 0x26 already has both.)

Stub space: $C1:BF80 is clear of patches 1/2 ($C1:BE14-$BE85) and nothing in
tools/ writes bank $C1 above $BF00. Note the 42-byte zero runs that follow every
character's act table are the 21 NULL ACT SLOTS, not free space — 0x2B is one of
them, which is exactly what this uses.

Verify: tools/probe_exp_airdash.lua, on this build, on --keep-air-invuln, and on
the clean ROM as the negative control.
"""
import argparse
import hashlib
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum

# --- measured against the clean ROM (bc0e29ee…); file offset = SNES & 0x3FFFFF
AIR_ACT = 0x2B                  # a null slot in BOTH her act table and script table
SCRIPT_SLOT = 0x000D7E          # $C0:0D28 + 0x2B*2   (her action-script pointers)
JUMPBACK_SCRIPT = 0x0E3A        # act 0x08's script — poses with real hurtboxes
ACT_SLOT = 0x016B6F             # $C1:6B19 + 0x2B*2   (her act-handler table)
BACKDASH_HANDLER = 0x722C       # $C1:722C — reused verbatim
HOOKS = (0x016E28, 0x016E61, 0x016E9A)   # `jsr $0958` in jump up / fwd / back
STUB = 0x01BF80
STUB_ADDR = 0xBF80

# ---------------------------------------------------------------- front dash --
# STATUS: WIRED BUT NOT FIRING — opt-in via --front, off by default. Everything
# below is in the ROM and asserted, and the GROUND stays clean (measured: a
# grounded forward double-tap produces no dash act, because the appended entries
# are air-only). What does not work is the INPUT: Venus's forward double-tap
# never arms the recognizer's forward pair, so the id below is never looked up.
#
# Measured, and it is character-specific rather than a bad tap pattern: on the
# CLEAN ROM the identical pattern fires URANUS's Shadow Dash (act 0x60, cmd 04)
# and her +0x5D RESETS as +0x5E increments — the arming branch at $C1:165C is
# taken. For Venus +0x5D free-runs and +0x5E stays 00, so neither branch of
# $C1:164C is reached, which means `$6B & 3` came out zero for her.
#
# NEXT INSTRUMENT (do not guess at this): $6B samples as 00 from an endFrame
# callback — it is transient — so it needs an EXEC hook at $C1:1626 logging A
# and DP $00, run on Venus and Uranus back to back. The framing caveat applies:
# the $1602-$1626 listing was disassembled from a mid-instruction start once
# already this session (HANDOFF trap 22), so re-frame it from $C1:15C4.
#
# The forward air dash needs NO new handler code: Uranus's Shadow Dash handler
# ($C1:88C8) is 40 bytes of generic routine — `ldx $88`, four constants, shared
# helpers — with nothing Uranus-specific in it, so Venus's act table can simply
# point at it. Its animation is her own jump-forward script. That is question 2's
# answer built rather than argued.
#
# Reaching it needs an INPUT, and that is per-character data: the 7-byte record
# at $C1:16AF + (charID-1)*7 maps each motion to the command id the recognizer
# emits, and slot $09 (forward double-tap) is 00 for everyone except Moon and
# Uranus — a zero is rejected outright at $C1:167B. Venus's becomes 0x0C.
#
# Command id 0x0C indexes special-start entry 10, and her table only has 10
# entries (0-9), bounded immediately by her throw table — so the table is copied
# to free space with two entries appended and all 32 `ldy #$6C1F` sites
# repointed. The appended entries carry flag 0x02 = AIR ONLY, which is what keeps
# the ground honest: a forward double-tap on the ground indexes them and the
# starter rejects it, so grounded behaviour is unchanged by construction rather
# than by hope.
FWD_ACT = 0x2C
FWD_SCRIPT_SLOT = 0x000D80      # $C0:0D28 + 0x2C*2
JUMPFWD_SCRIPT = 0x0E29         # her act-0x07 script
FWD_ACT_SLOT = 0x016B71         # $C1:6B19 + 0x2C*2
URANUS_DASH_HANDLER = 0x88C8    # borrowed wholesale
INPUT_REC_FWD = 0x0116CC        # $C1:16CB + 1 — Venus's forward-double-tap id
FWD_CMD_ID = 0x0C
TABLE_SRC = 0x016C1F            # $C1:6C1F, 10 entries
TABLE_ENTRIES = 10
TABLE_DST = 0x01BF00            # $C1:BF00, 24 bytes of zeros
TABLE_DST_ADDR = 0xBF00
LDY_OLD = bytes([0xA0, 0x1F, 0x6C])
LDY_NEW = bytes([0xA0, TABLE_DST_ADDR & 0xFF, TABLE_DST_ADDR >> 8])
VENUS_PROC = (0x016B0A, 0x0179F1)   # her proc block, where all 32 sites must lie
EXPECT_LDY_SITES = 32


def build(src, out, keep_air_invuln=False, front=False):
    rom = bytearray(open(src, "rb").read())
    air_act = 0x26 if keep_air_invuln else AIR_ACT

    if not keep_air_invuln:
        # act 0x2B -> the backdash handler; its animation -> her jump-back script.
        if rom[ACT_SLOT:ACT_SLOT + 2] != b"\0\0":
            raise ValueError(f"0x{ACT_SLOT:06X}: act slot {AIR_ACT:#04x} is not null")
        if rom[SCRIPT_SLOT:SCRIPT_SLOT + 2] != b"\0\0":
            raise ValueError(f"0x{SCRIPT_SLOT:06X}: script slot {AIR_ACT:#04x} is not null")
        rom[ACT_SLOT:ACT_SLOT + 2] = BACKDASH_HANDLER.to_bytes(2, "little")
        rom[SCRIPT_SLOT:SCRIPT_SLOT + 2] = JUMPBACK_SCRIPT.to_bytes(2, "little")

    # the three jump handlers' starter call -> the stub
    for off in HOOKS:
        if rom[off:off + 3] != bytes.fromhex("205809"):
            raise ValueError(f"0x{off:06X}: expected jsr $0958, found {rom[off:off + 3].hex()}")
        rom[off:off + 3] = bytes([0x20, STUB_ADDR & 0xFF, STUB_ADDR >> 8])

    # The stub. Entered exactly where `jsr $0958` was: Y = her special-start
    # table, X = object base, A 8-bit is not assumed (the starter sets it).
    stub = bytes([
        0x20, 0x58, 0x09,   # jsr $0958      the vanilla route, unchanged and FIRST
        0xE2, 0x20,         # sep #$20
        0xB5, 0x16,         # lda $16,X
        0x29, 0x80,         # and #$80       bit7 = grounded
        0xD0, 0x0D,         # bne done       grounded: behave exactly as vanilla
        0xB5, 0x51,         # lda $51,X      pending command nibble
        0x29, 0x0E,         # and #$0E       ids 02/03 = back double-tap, either strength
        0xC9, 0x02,         # cmp #$02
        0xD0, 0x05,         # bne done
        0xA9, air_act,      # lda #act
        0x4C, 0x24, 0x02,   # jmp $0224      the act setter rts's for us
        0x60,               # done: rts
    ])
    if any(rom[STUB:STUB + len(stub)]):
        raise ValueError(f"0x{STUB:06X}: stub area is not free")
    rom[STUB:STUB + len(stub)] = stub

    if front:
        # act 0x2C -> Uranus's dash handler; its animation -> her jump-forward script
        for slot, val, what in ((FWD_ACT_SLOT, URANUS_DASH_HANDLER, "act"),
                                (FWD_SCRIPT_SLOT, JUMPFWD_SCRIPT, "script")):
            if rom[slot:slot + 2] != b"\0\0":
                raise ValueError(f"0x{slot:06X}: {what} slot {FWD_ACT:#04x} is not null")
            rom[slot:slot + 2] = val.to_bytes(2, "little")

        # relocate her special-start table, +2 AIR-ONLY entries for the forward dash
        if any(rom[TABLE_DST:TABLE_DST + TABLE_ENTRIES * 2 + 4]):
            raise ValueError(f"0x{TABLE_DST:06X}: relocation target is not free")
        old = bytes(rom[TABLE_SRC:TABLE_SRC + TABLE_ENTRIES * 2])
        rom[TABLE_DST:TABLE_DST + len(old)] = old              # byte-identical copy
        rom[TABLE_DST + len(old):TABLE_DST + len(old) + 4] = bytes(
            [0x02, FWD_ACT, 0x02, FWD_ACT])                    # flags 02 = air only

        # repoint every site that hands her table to a starter — exactly 32, all
        # inside her own proc block (asserted, so a stray data match cannot pass)
        n, i = 0, VENUS_PROC[0]
        while True:
            j = rom.find(LDY_OLD, i, VENUS_PROC[1])
            if j < 0:
                break
            rom[j:j + 3] = LDY_NEW
            n += 1
            i = j + 3
        if n != EXPECT_LDY_SITES:
            raise ValueError(f"expected {EXPECT_LDY_SITES} `ldy #$6C1F` sites, repointed {n}")
        if LDY_OLD in bytes(rom[0x010000:0x020000]):
            raise ValueError("a reference to the old table survives somewhere in bank $C1")

        # and the input: give her forward double-tap a command id at all
        if rom[INPUT_REC_FWD] != 0x00:
            raise ValueError(f"0x{INPUT_REC_FWD:06X}: expected 00, found {rom[INPUT_REC_FWD]:02X}")
        rom[INPUT_REC_FWD] = FWD_CMD_ID

    fix_checksum(rom)
    open(out, "wb").write(rom)
    print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}"
          + ("  [back: act 0x26, INVULNERABLE]" if keep_air_invuln
             else f"  [back: act 0x{AIR_ACT:02X}, vulnerable]")
          + (f"  [front: act 0x{FWD_ACT:02X}]" if front else "  [no front dash]"))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="EXPERIMENT: Venus air backdash.")
    ap.add_argument("out")
    ap.add_argument("src", nargs="?", default=None)
    ap.add_argument("--stacked", action="store_true")
    ap.add_argument("--front", action="store_true",
                    help="ALSO wire the forward air dash — INCOMPLETE, does not fire yet; "
                         "see the FRONT DASH section of this file's docstring")
    ap.add_argument("--keep-air-invuln", action="store_true",
                    help="start act 0x26 in the air instead of the new act, i.e. keep the "
                         "backdash's own invulnerable animation, for A/B")
    a = ap.parse_args()
    src = a.src or clean_rom()
    require_source(src, stacked=a.stacked)
    check_not_inplace(src, a.out)
    build(src, a.out, keep_air_invuln=a.keep_air_invuln, front=a.front)
