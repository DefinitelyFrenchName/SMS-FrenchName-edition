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


def build(src, out, keep_air_invuln=False):
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

    fix_checksum(rom)
    open(out, "wb").write(rom)
    print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}"
          + (f"  [air backdash on act 0x26 — INVULNERABLE variant]" if keep_air_invuln
             else f"  [air backdash on act 0x{AIR_ACT:02X} — vulnerable]"))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="EXPERIMENT: Venus air backdash.")
    ap.add_argument("out")
    ap.add_argument("src", nargs="?", default=None)
    ap.add_argument("--stacked", action="store_true")
    ap.add_argument("--keep-air-invuln", action="store_true",
                    help="start act 0x26 in the air instead of the new act, i.e. keep the "
                         "backdash's own invulnerable animation, for A/B")
    a = ap.parse_args()
    src = a.src or clean_rom()
    require_source(src, stacked=a.stacked)
    check_not_inplace(src, a.out)
    build(src, a.out, keep_air_invuln=a.keep_air_invuln)
