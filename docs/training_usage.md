# Training mode — commands & usage reference

You are **P1**; the script drives **P2** (the dummy) unless you take control of it.
Everything below assumes the script is running (see `training_install.md`).

## Keyboard hotkeys (rebindable in `training_cfg.lua` → `TM_CFG.keys`)

| Key | Action |
|---|---|
| `M` | Open/close the **menu** (navigate `W`/`S`, change value `A`/`D`) |
| `1`–`7` | Dummy **quick modes**: 1 off · 2 guard all · 3 guard after first hit · 4 crouch · 5 wakeup jab · 6 wakeup backdash · 7 wakeup slot-playback |
| `0` | **Reset positions** (both characters to mid-screen, actions cleared) |
| `9` | Cycle **HUD mode**: full → meter only → panel only → off |
| `8` | Toggle **hitbox viewer** |
| `R` | **Record** toggle: arm recording into the current slot (pad-swap turns on; recording starts at your first input) / stop & save |
| `T` | **Playback** toggle: play the current slot (or stop playback) |
| `Y` | Cycle **recording slot** 1–4 (shows length) |
| `U` | Cycle **playback trigger**: manual → loop → wakeup → blockstun → hitstun → random |
| `Q` / `E` | **Save / restore position state** (in-memory savestate — repeatable, survives nothing but the session) |
| `G` | Freeze/unfreeze the **frame meter** (inspect the last exchange; works with pause + frame advance) |
| `P` | Manual **pad swap** (your pad drives P2 until pressed again) |
| `F` | Toggle **startup display convention** (see "Frame data conventions") |

## Pad controls (disable with `TM_CFG.padControls = false`)

| Input | Action |
|---|---|
| hold `R` (shoulder) | **Drive the dummy** while held (momentary pad swap, nothing recorded) |
| `Select` | **Record toggle** — same as keyboard `R`: press once to arm (your next input starts the recording, you're controlling P2), press again to stop & save |
| `Start` | Normal game pause (untouched) |

## The menu (`M`)

| Row | Values | Meaning |
|---|---|---|
| dummy | on/off | Master switch for all dummy layers |
| pose | stand / crouch / jump | Idle stance. **stand = port 2 left free** (a second pad can play the dummy) |
| guard | off / all / afterhit | `all` = hold down-back whenever able; `afterhit` = start guarding after the first hit taken |
| auto tech | on/off | Mash throw-escape while grabbed (2 sampled presses = tech, half damage) |
| wakeup | off / block / jab / backdash / throw / slot | One-shot action on the first actionable frame after knockdown/throw; `slot` plays the current recording (reversal timing) |
| rec slot | 1–4 (length) | Active recording slot |
| trigger | manual / loop / wakeup / blockstun / hitstun / random / gc | When playback fires; `random` picks any non-empty slot (mixup training); `gc` fires the slot on **blockstun entry** — the GC trainer (see below) |
| gc chance | 100 / 75 / 50 / 25 % | Probability the `gc` trigger fires per blockstun entry — lower it to practice hit-confirming against random guard cancels |
| hud mode | 1–4 | Same as key `9` |
| hud scale | 1–4 | ScriptHud overlay resolution |
| hitboxes | on/off | Same as key `8` |
| S display | dustloop / SF6 | Same as key `F` |
| meter | auto / frozen | Same as key `G` |
| timer | frozen / running | Round timer freeze (frozen by default) |
| hp regen | 2s to max / off | Restore the dummy to its character's max HP after 2 s without taking damage (waits until it's actionable and no combo is open); the life bar refills with it |
| ko reset | on / off | On any KO, instantly reload the position state (`Q`) instead of letting the round end — a baseline is auto-captured at session start if you never saved one |
| status | both / combo / meter / off | Where event labels (GC, REVERSAL, PUNISH…) appear: under the combo counter on the earning player's side, as popups above the frame meter, both, or hidden |

Settings persist to `traces/training_settings.lua` when the menu closes.

## Recording workflow

1. Pick a slot (`Y`), press `R` (or pad `Select`) — you now control P2; the recording
   starts on your **first input** (idle lead-in is skipped).
2. Perform the sequence, press `R`/`Select` again — trailing neutral is trimmed, the slot
   is saved to `traces/training_slots.lua`.
3. Play it: `T` (manual), or set a trigger (`U`): **wakeup** replays it the instant P2
   becomes actionable after a knockdown — the classic reversal dummy. `reversal_lead`
   (cfg, default 1) starts playback a frame early so reversal-timed moves come out
   frame-perfect.
4. Recordings store **back/forward relative to facing** — they mirror automatically when
   sides switch.

### GC trainer

Record the dummy's character performing its special once (slot of your choice), then set
`guard = all` and `trigger = gc`: every time the dummy enters blockstun, the recording
fires immediately, the motion completes inside the stun, and the special **guard-cancels
your blockstring** (green `GC` label). Drop `gc chance` below 100% to practice
hit-confirming vs a dummy that GCs unpredictably — the true SMS matchup experience.

## The frame meter (bottom)

Two tracks: P1 above, P2 below; one cell = one frame, newest on the right. It records
while anything is happening and **freezes when both players idle**, keeping the last
exchange readable (SF6 behavior). Colors:

| Color | Class | | Color | Class |
|---|---|---|---|---|
| green | startup | | yellow | hitstun |
| red | **active** | | dark gold | blockstun |
| blue | recovery | | slate | block held |
| light blue | **cancellable recovery** | | rust | knockdown / getting up |
| dark gray | neutral | | purple | thrown / held |
| gray | movement (walk/jump/dash) | | teal | throw tech |

Modifiers: **white strip on top** = invulnerable that frame (empty hurtbox / untargetable);
**pale strip at bottom** = cancel window; **dimmed cell** = hitstop (excluded from all
counts); **thin red sub-row** = that player's projectile is active. Segment counts print at
the start of each run; the **advantage badge** (`+N` green / `-N` red) lands between the
tracks when an exchange settles.

Above the meter, the last-move summary: `P1 2LP  S4 A5 R4 T13  hit +6 (c+12)` — startup /
active / recovery / total, then advantage on hit or block. `c+N` is **cancel advantage**:
your advantage if you cancel the recovery (this game's links live in cancellable recovery —
that's the number that governs the Uranus infinite, for example).

## Frame data conventions (important)

- **S (startup)** counts the frames *before* the first active frame — the convention this
  game's Dustloop wiki uses (2LP = S4). Press `F` for SF6-style display ("hits on frame
  N": S+1). The toggle is display-only.
- **Counts exclude hitstop** — on-hit and whiff numbers match.
- **Active frames follow the hitbox**, including the measured 1-frame persistence into the
  recovery act — "can this frame hit?" is the definition.
- **Advantage** = first-neutral-frame delta (`+` = you recover first), measured only after
  the defender actually reacted, and deferred while any projectile is live.

## Labels

Shown as popups above the frame meter and/or under the combo counter on the earning
player's side (`status` menu row picks the placement; default both).

| Label | Fires when |
|---|---|
| MEATY | A hit connects within 2 frames of the defender leaving stun/knockdown — includes the 1-frame meaty that lands on their first exit frame (hit beats same-frame block) |
| REVERSAL | A move starts on the defender's first actionable frame (±1) after stun/knockdown |
| PUNISH | A hit connects while the victim is in **recovery** of their own move |
| GC | **Guard cancel** — a special canceling blockstun directly (a move starting straight out of a blockstun frame). The game-defining SMS mechanic: if you're new, this is the thing to learn |
| THROW TECH | Throw escaped by mashing (half damage) |
| THROWN | Throw completed (full damage) |
| TRADE | Both players' hits connect on the same frame |

## Combo counter (on-screen overlay)

A big `N HITS` counter appears under the **attacker's** health bar (left when you combo
the dummy, right when P2 combos you) from 2 hits, with the damage total under it, and
lingers ~1.2 s after the chain ends. It counts **true chains only**: a hit landing after
the defender had *any* actionable frame restarts the count — a displayed number is always
a sequence the defender could not have interrupted.

Colors:
- **GOLD** — classic true chain: every follow-up landed while the defender was still in stun.
- **MAGENTA + `1F` tag** — the chain contains at least one **non-bufferable link**: a hit
  that landed on the defender's first possible out-of-stun frame (the 1-frame meaty — the
  canonical Uranus infinite lights up magenta when performed frame-perfectly). One frame
  later and the defender would have been free, so these links cannot be buffered.

## Hitbox viewer (`8`)

Red = attack box (only while genuinely active), green = body hurtbox, yellow = head
hurtbox, blue = collision/push box. Hurtboxes disappear while a character is invulnerable —
that's the actual invulnerability mechanism in this engine, so what you see is what hits.
Box data is read live from the ROM, so box-altering patches render truthfully (patch 7's
Pluto 5HP, patch 9's Deep Submerge). Projectiles draw from their **own** object box tables
(object id 10–27 → bank $8A pointer table), not their owner's — and **only their hit box**
(the hurt/coll pointer tables are roster-only, so a projectile's hurt/coll would read garbage;
projectiles aren't destructible anyway).

## Piano roll (left edge)

Your inputs per frame, newest at the bottom: direction as numpad notation (2 = down,
6 = forward, 3 = down-forward…), then `P K P K` columns = LP LK HP HK (light/dark shades).
Identical consecutive frames compress into one row with `xN`. While you record or the dummy
plays back, the roll switches to P2's inputs and moves to the **right edge** — it always
sits on the tracked player's own side, so it never masks the corner your carry pushes
toward.
