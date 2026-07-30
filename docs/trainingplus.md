# Training+ — the in-ROM training mode (patch 11)

Patch 11 upgrades the base game's own **Practice mode** into a real training mode, entirely
inside the ROM. Everything renders and runs on real hardware — no emulator, no Lua, no
overlay. The Mesen-Lua training mode (`docs/training_usage.md`) remains the *precision*
tool (frame meter, exact frame data, hitbox viewer); Training+ is its console-friendly
sibling, oracle-validated against it feature by feature.

---

## 1. Install

Apply one of the BPS patches (with Flips or any BPS patcher) to the **clean** Japanese ROM
(SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`):

| Patch file | Contents | Result ROM SHA-1 |
|---|---|---|
| `build/sms_trainingplus.bps` | clean + patch 11 only | `e9ac2205…` |
| `build/sms_full11_trainingplus.bps` | canonical v0.7 (patches 1-5) + 11 | `09106a07…` |
| `build/sms_allpatches_v1.1.bps` | **everything** (patches 1-11), title shows "v.1.1" | `be2cb752…` |

Or rebuild from source: `python3 tools/mkpatch11.py [src] [out]` — the builder stacks on
*any* patch 1-10 ROM in any order (its two hook sites are byte-disjoint from every other
patch).

Then: title menu → **down, right** (the menu is a 2-column grid) → **Practice**.

## 2. Controls

| Input | Effect |
|---|---|
| **L+R** (both shoulders) | open / close the training menu |
| **L** alone (patch 12 installed) | taunt — the character's native failed-special pratfall; blocked while the menu is open, and R-held never taunts |
| **↑ / ↓** (menu open) | move cursor |
| **← / →** (menu open) | change the value (on RESET: perform the reset) |
| **Start** (menu closed) | native movelist, untouched |
| **Select** (menu closed) | exit Practice, untouched |

While the menu is open, P1's pad drives only the menu (the fighter stands still; Start and
Select are swallowed). The menu takes about half a second to appear — it paints invisibly
and pops in complete. Settings persist across rematches while the console stays on.

## 3. Menu reference

| Row | Values | What it does |
|---|---|---|
| **POSE** | STAND / CROUCH / JUMP | Dummy holds the pose. STAND leaves the dummy's pad free, so a second controller can still drive it. JUMP re-jumps on every landing. |
| **GUARD** | OFF / ALL / HIT | ALL: holds down-back (side-aware) and blocks everything blockable. HIT: stays open until the first hit or throw connects, then blocks — the classic "punish the second hit" drill. |
| **WAKEUP** | OFF / JAB / THROW / DASH | On the dummy's first actionable frame after knockdown or throw: presses jab (3-frame hold, 30 Hz-safe), attempts a forward-throw, or performs a real 44 backdash (injected back/neutral/back — the motion recognizer fires it, act 0x26). |
| **TECH** | OFF / ON | Dummy mashes throw-tech: a fresh HK every other frame, the measured-optimal rate against the 30 Hz press latch. Against a standard throw this always techs (thrower's mash counter ≥ 2, half damage). |
| **DAMAGE** | OFF / ON | The game's own hidden switch (game_mode 4 ↔ 5). OFF (native default): every hit connects — hitstun, hitstop, knockdowns, combos — but HP never drops. ON: HP drops as in a versus match. (No HP bars exist in Practice; the game never draws its HUD here.) |
| **REGEN** | OFF / ON | With DAMAGE ON: the dummy heals to full 2 seconds after the last hit, held back while it's still in any stun/knockdown (so a slow string can't be interrupted by a refill). |
| **REFILL** | OFF / ON | Nobody dies. A lethal hit knocks down normally; HP snaps to full during the knockdown and the victim performs a normal wakeup — the KO pose and the frozen post-KO state never happen. Applies to both players. |
| **RECORD** | OFF / ARM | Set ARM and close the menu: **your pad now puppets the dummy** and everything you do is recorded (up to ~34 s). Press L+R to stop (this also reopens the menu). Opening the movelist or leaving the match also finalizes the recording. |
| **PLAY** | OFF / ONCE / LOOP | On menu close, the recording plays back into the dummy — once, or looping forever. Great for meaty/okizeme and punish drills. |
| **P1 HP** | FULL / LOW | Sets P1's HP: LOW = 0x17 (23/96, under the 25% desperation threshold of 0x18) so P1 can practice desperation moves; FULL restores max. One-shot on toggle. Desperations also need DAMAGE ON (the game skips them in mode 4). |
| **SHOW** | OFF / ON | Three live readouts on the lower screen: your **current inputs** (U D L R + LP LK HP HK, lit while held), an **advantage readout** (`ADV N` / `ADV -N`, 1.5 s after each exchange), and **both players' HP as numbers** — finally making DAMAGE / REGEN / REFILL (and Guts-buff testing) directly observable in Practice. |
| **RESET** | GO | Press ←/→ on this row: both fighters snap to round-start positions in neutral. Refused unless both are grounded and actionable (no mid-move teleports). |

### Reading the ADV number

It's the gap, in frames, between the two players' first *neutral* frame after an exchange —
positive means **you** recovered first. It is an approximation: it can differ by ±1 from
the Lua trainer's framedata conventions (which exclude hitstop and know each character's
cancellable-recovery frames), and it doesn't reason about live projectiles. Use it for
"safe or not, roughly by how much"; use the Lua trainer for exact numbers.

### Recording notes

Recordings store raw pad input, **not** facing-relative input — if the characters have
switched sides since recording, the directions play back mirrored. Record and replay from
the same positions (RESET makes this easy). One recording slot; re-arming overwrites it.

## 4. Suggested drills

- **Block-punish**: GUARD ALL, DAMAGE ON, SHOW ON — poke into the dummy's block, read ADV,
  practice your fastest punishable-gap response.
- **Meaty/okizeme**: knock the dummy down once, RECORD your oki sequence as the *attacker*…
  or better: RECORD the dummy's wakeup reversal (ARM → close → do the reversal on wakeup →
  L+R), then PLAY LOOP and practice safe meaties against it. WAKEUP JAB/DASH covers the
  simple cases without recording anything.
- **Throw game**: TECH ON to verify your throws are tech-able; TECH OFF + WAKEUP THROW to
  practice defending wakeup grabs.
- **Infinite practice** (this project's raison d'être): DAMAGE ON, REGEN ON, REFILL ON —
  grind `[2LP > 2HP > 66]xN` forever; on the patched v0.7+ builds the loop needs the
  1-frame link, and the combo counter (patch 10) is unavailable here (Practice has no HUD)
  — use SHOW's ADV to confirm the link timing instead, or the Lua trainer for the meter.

## 5. How it works (internals summary)

Full engine background: `docs/sms_engine_internals.md` §10 (Practice mode) and §11 (modding
playbook); flat addresses: `docs/annotations.md` "patch 11 RE"; per-byte changes and
verification: `docs/patch_notes.md` Patch 11.

- **Two JML hooks**, byte-disjoint from patches 1-10 (stacking order never matters):
  - `$80:8373` — joy_read tail, after the held words are stored, before press edges are
    derived. The INPUT stub does everything here: the mode gate, the menu FSM (with its own
    edge detection on raw P1 input), input eating, the dummy layers (record ▸ playback ▸
    wakeup one-shots ▸ tech-mash ▸ guard ▸ pose — the Lua trainer's priority stack), and
    the effects (damage flip, regen, refill, reset, advantage counters).
  - `$80:D574` — inside the HUD uploader (NMI, scanline 237): all VRAM work — one item per
    vblank (font DMA / row paint / clear / displays) plus TM (`$212C`) management. Replays
    its displaced `beq/sta $2116` branch-aware.
- **The dummy is pure input injection**: rewriting P2's `$5E/$5F` at that hook point makes
  the engine derive edges, latch presses (30 Hz), fire motion recognizers, block, and mash
  exactly as a real pad would. No action-byte force-writes — with one exception: cancelling
  a KO requires forcing the native standup act (0x20) at the "down" frame, because the
  death is latched at damage-apply and ignores HP afterwards.
- **BG3 is free real estate in Practice** — it's the movelist layer with the screen layer
  turned off; the movelist restages itself on every Start press. The patch wipes rows 0-17,
  paints its UI, and turns BG3 on (TM 0x17) only while something is showing.
- **State lives in bank `$7F`** (`$7F:F000+`; recording ring `$7F:E000+` via the WMDATA
  port) — the only WRAM the game provably never touches during play. Boot's RAM clear
  resets everything; settings re-initialize on the first gated frame.
- **Fonts**: 25 white 2bpp glyphs DMA'd to the free BG3 CHR window 0xC7-0xDF (the first 16
  tiles are patch 10's letters in the same slots; the two patches' fonts never coexist on
  screen — patch 10 renders only in VS, patch 11 only in Practice).

## 6. Building & testing

```bash
python3 tools/mkpatch11.py                       # clean -> build/sms_trainingplus.sfc
python3 tools/mkpatch11.py <any-1..10-rom> <out> # stack on anything
python3 tools/mkpatch11.py --stage pipe          # plumbing smoke-test build

# feature suite (14 phases, 50+ checks, oracle-derived expectations) — expect ALL PASS:
ROM="build/sms_trainingplus.sfc" tools/run.sh tools/test_p11_tier1.lua 260
# performance (stub cycle costs, vblank span, or SOAK=true in the cfg for 5000f):
ROM="build/sms_trainingplus.sfc" tools/run.sh tools/perf_patch11.lua 200
# VS non-interference (must diff empty):
tools/run.sh tools/probe_noninterf.lua on v0.7 vs v0.7+11 and diff traces/ni_*.txt
```

Measured: worst-case combined stub cost **3.4 %** of a frame (INPUT ≤ 705 cyc, UPL2 ≤ 691
cyc, ≤ 4 scanlines of vblank); 5000-frame all-features soak clean; VS/story gameplay RAM
**frame-identical** to the unpatched ROM.

## 7. Known limitations

- ADV readout is ±1-approximate (see §3) and projectile-blind.
- Recordings don't mirror on side swap; single slot; not persisted across power-off.
- Menu opens in ~0.5 s (invisible painting; by design, one VRAM item per vblank).
- No HP bars in Practice (native behavior — the game's HUD producer never runs there);
  DAMAGE/REGEN/REFILL work on the invisible HP value.
- The in-match combo counter / status labels (patch 10) don't display in Practice for the
  same reason — they hook the HUD producer. Use the Lua trainer when you need meters.
