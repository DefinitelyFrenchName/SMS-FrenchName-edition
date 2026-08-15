# Training mode internals — a developer's guide to `tools/training.lua`

This explains **how the training-mode script works and how to extend it**, for a
programmer who has never written Lua and never scripted an emulator. It complements
(does not repeat) the other three training docs: `training_install.md` (setup),
`training_usage.md` (the user manual: hotkeys, menu, workflows), and `trainingplus.md`
(patch 11's separate in-ROM training menu, which shares no code with this).

The code itself is the source of truth — this file explains the ideas and quotes only
what the checker can hold to account: the module map and load order below are verified
against the package by `tools/checktrainingdocs.py`, and every behavioural claim
carries the module name so you can read the real thing. Line numbers are deliberately
not cited; they rot.

---

## 1. The 30-second picture

Mesen (the emulator) runs the game exactly as a console would. The training mode is a
**pure Lua script** riding on top: the ROM is never modified. Once per emulated frame,
Mesen calls back into the script at three points, and everything the trainer does
happens inside those calls:

1. **When the game is about to read the controllers** (`inputPolled`): the script reads
   the physical pads, lets its features override them (dummy behaviour, recording
   playback), and hands the final result back to the emulator. This is how the "dummy"
   plays: it is literally pressing buttons.
2. **When a specific game instruction executes** (an "exec callback" on the game's
   joypad-read routine): the one place savestate operations are legal (see §5.4).
3. **At the end of each frame** (`endFrame`): the script reads the game's RAM — both
   fighters' state — into a snapshot, derives everything it shows (frame classes,
   move data, combos, labels), and draws the HUD.

So the data flow each frame is:

```
game RAM ──read──▶ snapshot ──classify──▶ frame classes / events ──▶ HUD drawing
controller ──read──▶ pipeline stages (menu, recorder, dummy) ──override──▶ game
```

Nothing is inferred from the ROM ahead of time except one generated table of hitbox
heights (§7, `hitbox_h.lua`); everything else is read live from work RAM, which is why
the same script works on every ROM build in this repo.

---

## 2. Just enough Lua

Lua is a small dynamically-typed language. The ~10 idioms below cover essentially
every line of this package.

**Tables are the only data structure.** A table is a hash map that can also act as an
array. `{ 1, 2, 3 }` is an array (indices start at **1**, not 0); `{ a = 1, b = 2 }`
is a map; `t.a` and `t["a"]` are the same thing. `#t` is the array length.
`ipairs(t)` iterates array entries in order; `pairs(t)` iterates all keys in no
particular order. Deleting is assigning `nil`.

**`local` matters.** `local x = 1` is a proper scoped variable. Assigning to a name
*without* `local` creates a **global** — visible to every script in the emulator. The
package uses locals everywhere; the only deliberate globals are `TM` (the entry script
publishes the context for console poking) and `TM_CFG` (the user's optional config
file publishes overrides).

**Functions are values; closures are the architecture.** `local function f(x) … end`
defines a function; functions can be stored in tables, passed around, and — crucially
— they capture the variables in scope when created (a *closure*). Every module here is
built on this: `init(ctx)` creates local state, then registers inner functions that
still see that state:

```lua
function M.init(ctx)
  local counter = 0                        -- private to this module instance
  local function step() counter = counter + 1 end
  table.insert(ctx.hooks.frame, step)      -- runs every frame, still sees `counter`
end
```

There are no classes and no `self` anywhere in the package — just tables of functions
and closures over locals.

**The module pattern.** Each file ends in `return M` where `M = {}` collects the
module's public functions. `dofile(path)` loads and runs a file and yields that return
value. (Standard Lua has `require`; this package uses `dofile` with explicit paths
because Mesen's script search path is not the repo.)

**Multiple returns and multiple assignment.** `return a, b, c` and
`local x, y = f()` are ordinary. `classify` in `framedata.lua` returns four values at
once (class, invulnerable, frozen, cancellable).

**`nil` and `false` are the only falsy values.** `0` and `""` are TRUE. Hence
patterns like `x = x or default` (use `default` when `x` is nil/false) and
`cond and a or b` (Lua's ternary — safe only when `a` can't be false/nil).

**`pcall` is try/catch.** `local ok, result = pcall(f, args)` runs `f` and returns
`false, error` instead of crashing. The package wraps every emulator call that can
throw — see §5.6 for why this is load-bearing rather than defensive boilerplate.

**No bitwise operators are used — modulo arithmetic instead.** You will see this
everywhere:

```lua
local band = function(b) return mask % (b + b) >= b end   -- "is bit b set in mask?"
```

`mask % (b+b)` keeps only the bits below the one above `b`; if the result is `≥ b`,
bit `b` was set. Likewise `v % 256` is the low byte and `math.floor(v / 256)` the high
byte. This keeps the scripts portable across Lua versions with different bit APIs.

**Strings.** `..` concatenates; `string.format("%02X", n)` is printf; `#s` is length;
`("%q"):format(s)` (used as `string.format("%q", v)`) writes a quoted, reloadable
string — which is how settings files are round-tripped as Lua source (§6.10).

---

## 3. Just enough Mesen scripting

Mesen 2 embeds Lua with an `emu.*` API. What the package uses:

**Callbacks.** `emu.addEventCallback(fn, emu.eventType.endFrame)` and
`(fn, emu.eventType.inputPolled)` register the two per-frame entry points.
`emu.addMemoryCallback(fn, emu.callbackType.exec, addr, addr, cpu, memType)` calls
`fn` when the CPU *executes* the instruction at `addr` — the package registers exactly
one, on the game's joypad-read routine (see §5.4).

**Memory access.** `emu.read(addr, memType)` / `emu.write(addr, value, memType)`.
The `memType` chooses an address space, and choosing correctly is a recurring trap
([SNES-6] in the `snes-romhacking` skill):

| memType | what it is | used for |
|---|---|---|
| `snesWorkRam` | the console's 128 KB work RAM, addressed from 0 | all game-state reads/writes (`0x1000` = the address docs write as `$7E:1000`) |
| `snesMemory` | the CPU's 24-bit bus view | reading ROM tables live (hitboxes in bank `$8A`) |
| `snesVideoRam` | VRAM bytes | the HP-bar tilemap repaint (§6.8) |

**Input.** `emu.getInput(port)` returns a table of booleans
(`{a=…, b=…, x=…, y=…, l=…, r=…, up=…, down=…, left=…, right=…, start=…, select=…}`).
`emu.setInput(padTable, 0, port)` overrides the pad — **the port is the THIRD
argument**; a Mesen quirk discards the second, so `(tbl, port)` silently drives P1
([SNES-35]). Probe-verified pipeline fact: at the top of `inputPolled`, `getInput`
returns the *physical* pad, unpolluted by your own `setInput` from the same frame —
so the rule is: read first, then override.

**Drawing.** `emu.drawString(x, y, text, fgColor, bgColor)` and
`emu.drawRectangle(x, y, w, h, color, filled)`. Colors are `0xRRGGBB`; a leading
alpha byte makes them translucent (`0xC8000000 + color` is a faint fill — HIGHER
alpha = MORE transparent in Mesen). There are two canvases, selected with
`emu.selectDrawSurface`:

* `consoleScreen` — 256×224, aligned with game pixels (used for hitboxes and the big
  combo counter, so they scale chunky with the window);
* `scriptHud` — a high-resolution overlay whose size comes from the video renderer
  (used for the frame meter, panels, piano roll). Its size must be re-queried per
  frame with `emu.getDrawSurfaceSize()`, and **headless it is degenerate** (width 0)
  — every drawer must cope with "no surface" (§6.7).

`takeScreenshot` does NOT composite the scriptHud overlay ([SNES-39]) — which is why
the visuals have a manual smoke checklist in `training.lua`'s header instead of
screenshot tests.

**Savestates.** `emu.createSavestate()` returns the state as a Lua string;
`emu.loadSavestate(data)` takes that string back. Both **throw unless called from a
CPU-exec context** ([SNES-38]) — an `endFrame` callback is not one. Hence the anchor
pattern in §5.4.

**Misc.** `emu.displayMessage(tag, text)` shows a toast in the GUI.
`emu.isKeyPressed("M")` polls the host keyboard — it **errors on every key name in
the headless testrunner** (no keyboard exists), which is why every call sits behind
`pcall`. Fonts are ~6 px/char, 9 px line height.

**The frame-ordering contract** (probe-verified, quoted from `main.lua`'s header):

```
inputPolled  (sees ctx.t = N)
  → exec @ $80:8353  (the game's joy_read; savestate ops happen here)
  → game logic for frame N
  → endFrame  (frame hooks see post-frame state at ctx.t = N, then ctx.t increments)
```

A consequence used by the recorder: a trigger detected at `endFrame` N can first act
at `inputPolled` N+1 — and that is *frame-perfect* for move starts, because the
engine latches a press on the first free frame's poll.

---

## 4. Just enough game

The full references are `docs/game/sms_quickref.md` (addresses),
`sms_engine_internals.md` (mechanisms) and `sms_hacking_playbook.md` (the rules this
game taught us — bracketed `[SMS-n]` tags below refer to it). What the trainer
actually relies on:

* **Player structs.** Each fighter is a 0x80-byte record in work RAM: P1 at `0x1000`,
  P2 at `0x1080`; projectiles use twin slots at `0x1100`/`0x1180` with the same
  layout. Every field the trainer reads is named in `const.lua`'s `C.OFF` table —
  the important ones: `act` (+0x01, the current action ID), `step` (+0x02, the
  step within the action), `hb/hub/coll` (+0x40..42, this frame's hit/hurt/collision
  box indices), `connected` (+0x43, a *latch* — only its 0→1 edge means anything),
  `hp` (+0x49), `maxhp` (+0x4A), `hitstop` (+0x4D, counts down while the hit-freeze
  is on), `btnHeld` (+0x50), `mash` (+0x56).
* **Action IDs.** 0x00–0x2A are universal states (walk, jump, blockstun, hitstun
  variants, knockdown, thrown…) — named in `C.ACT_NAMES`; ≥ 0x2B are per-character
  moves. `const.lua` also carries the derived predicates (`isHitstunAct` etc.) — note
  hitstun runs to 0x18: the flame/electric reactions constrain the defender exactly
  like ordinary hitstun, and twelve hand-rolled copies used to stop at 0x16 (#99).
* **Hitstop.** When a hit connects, both fighters freeze for ~8 frames
  (+0x4D counts down). All frame counts the trainer shows **exclude** frozen frames,
  which is what makes whiffed and connecting moves report identical S/A/R.
* **30 Hz input latch.** The engine samples held buttons every other frame — a
  scripted press must span ≥ 2 frames, and "mash" means a fresh press every other
  frame ([SNES-40]; the dummy's throw-tech layer does exactly that).
* **Buttons.** Y=LP, X=HP, B=LK, A=HK ([SMS-38] — the vendor doc had it wrong).
  The trainer normalises pads to a bitmask (`C.M_*`) that is *facing-relative*
  (back/forward, not left/right), so recordings mirror correctly when sides swap.
* **Boxes.** Hit/hurt/collision boxes are 8/16/8-byte records in ROM bank `$8A`,
  reached through pointer tables indexed by character ID — the viewer reads them
  live off the bus, so ROM-hack box patches render truthfully. Projectiles select
  their box table by their **own** object id, not the owner's, and only the hit
  pointer table covers projectile ids — hurt/coll would index garbage ([SMS-11]),
  so the viewer draws projectile hit boxes only.
* **Two WRAM conveniences** found for the regen module: the round timer is BCD at
  `0x0802`, and the HUD bars have their own latched values at `0x0800`/`0x0801`
  that only the damage routine updates (§6.8 for why that matters).

---

## 5. Architecture

### 5.1 Boot

`tools/training.lua` is a 5-line launcher: it locates the repo through
`sms_env.lua` (every Lua tool does — the bootstrap path differs between `tools/` and
`tools/saturn/` and getting it wrong fails with *no output at all*, [SMS-34]), loads
`training/main.lua`, and calls `main.run(ROOT, {})`. The returned context is
published as the global `TM` so you can poke at a live session from Mesen's console
(e.g. `TM.ui.hudMode = 3`).

### 5.2 The ctx table

`main.run` builds one shared table, `ctx`, and passes it to every module. It is the
whole architecture — there is no other coupling between modules:

| field | meaning |
|---|---|
| `ctx.C` | constants (`const.lua`): addresses, offsets, act tables, colors |
| `ctx.cfg` | config: hotkey map, HUD scale, meter length — defaults overridable by `tools/training_cfg.lua` (a plain file setting the global `TM_CFG`) |
| `ctx.frame` | frames since script start (monotonic) |
| `ctx.t` | the **local frame clock**: −1 until the game first executes the anchor, reset to 0 on every savestate load. All timestamps use `ctx.t` |
| `ctx.hooks` | four ordered lists — `input`, `frame`, `draw`, `reset` — that modules append functions to |
| `ctx.actions` | name → function registry; hotkeys and menu rows dispatch through it |
| `ctx.ui` | shared UI switches (menuOpen, hudMode, padSwap, hitboxes, sConvSF6, meterMode) |
| `ctx.anchor` | savestate plumbing: `posState` (the saved position), `savereq`/`loadreq` (requests the anchor fulfils) |
| `ctx.snap`, `ctx.prev` | this frame's and last frame's RAM snapshot (gamestate) |
| `ctx.hist` | ring buffer of the last 600 snapshots |
| `ctx.pads`, `ctx.out` | input pipeline state (§5.5) |
| `ctx.events`, `ctx.lastMove`, `ctx.lastAdv`, `ctx.combo` | per-frame events and derived results (framedata/combo) |
| `ctx.mod` | name → module table, so modules can call each other's public functions |
| `ctx.headless` | true under the test runner: no keyboard, no toasts, no real pads |

### 5.3 Modules and load order

A module is a file in `tools/training/` that returns a table with an optional
`init(ctx)`. `main.lua` loads, in order:

```lua
{ "gamestate", "input", "recorder", "dummy", "framedata", "combo", "labels", "regen",
  "hud", "hud_panel", "hud_bar", "hud_pianoroll", "hud_boxes", "hud_combo", "menu" }
```

**Order is behaviour**, because each hook list runs in registration order:

* `gamestate` registers the first *frame* hook, so every later frame hook sees a
  fresh `ctx.snap`; `framedata` registers next, so `combo`/`labels`/`regen`/HUD
  steps see classified frames.
* `recorder` registers its *input* stage before `dummy`, and playback wins because
  `dummy` yields when `ctx.out` is already set.
* HUD modules register *draw* hooks after everything computes; `menu` draws last
  (on top).

Three files are not in that list: `main.lua` (the orchestrator), `const.lua` (loaded
directly into `ctx.C`), and `hitbox_h.lua` (a generated data table `framedata` loads
itself). The full inventory (checked against disk both ways):

| Module | Loaded via | Role |
|---|---|---|
| `main.lua` | entry script | ctx, module loading, the three callbacks, hotkeys, built-in actions |
| `const.lua` | `ctx.C` | addresses, offsets, act names/predicates, masks, palettes, probe-verified platform facts |
| `hitbox_h.lua` | `framedata` | GENERATED attack-box heights per character (from `docs/game/sms_all_boxes.json`) |
| `gamestate.lua` | MODULES | per-frame RAM snapshot of both fighters + projectiles; 600-frame ring buffer; `onLeft`/`ago` helpers |
| `input.lua` | MODULES | the input pipeline: physical pads → pad-swap → stages → `setInput` |
| `recorder.lua` | MODULES | 4 recording slots (facing-relative masks), triggers (wakeup/blockstun/hitstun/random/gc), slot persistence |
| `dummy.lua` | MODULES | dummy behaviour layers: wakeup one-shot, throw-tech mash, guard, pose; keyboard quick modes |
| `framedata.lua` | MODULES | the correctness core: frame classes, move instances (S/A/R), connects, advantage settlement |
| `combo.lua` | MODULES | combo state per defender: TRUE chains vs DROPPED, tight-link (1F) detection |
| `labels.lua` | MODULES | event popups: GC / REVERSAL / PUNISH / THROW TECH / THROWN / TRADE |
| `regen.lua` | MODULES | timer freeze, dummy HP auto-restore (+ HUD bar repaint), KO auto-reset |
| `hud.lua` | MODULES | draw dispatcher: surface selection/caching, hudMode visibility rules |
| `hud_panel.lua` | MODULES | status panels: char/act/class/HP, distance, last-move summary + advantage line |
| `hud_bar.lua` | MODULES | the SF6-style frame meter: cell strip, freeze model, segment counts, advantage badge |
| `hud_pianoroll.lua` | MODULES | per-frame input history strip (numpad notation + button columns) |
| `hud_boxes.lua` | MODULES | hitbox/hurtbox/collision overlay, read live from ROM bank `$8A` |
| `hud_combo.lua` | MODULES | big on-screen combo counter + per-side status labels |
| `menu.lua` | MODULES | the M menu (rows + values), settings persistence, pad conveniences (hold-R, Select) |

### 5.4 The exec anchor — why savestates go through requests

`main.lua` registers one memory callback, on the execution of the game's joypad-read
routine (bus address `0x808353`). It does three things there and only there: starts
the local clock (`ctx.t: −1 → 0`), and fulfils `ctx.anchor.loadreq` /
`ctx.anchor.savereq`. Modules never call `emu.loadSavestate` directly — they set a
request and the anchor performs it next frame, because savestate operations throw
outside a CPU-exec context ([SNES-38]). On every load the clock resets to 0 and all
`reset` hooks fire — the rule that history must not survive a reload (issues #15,
#96; see §6.4's reset discipline).

### 5.5 The input pipeline

`input.lua` owns the `inputPolled` callback:

1. read physical pads for both ports (via `ctx.padSource` — a function the headless
   harness replaces to inject scripted pads);
2. apply pad-swap: when `ctx.ui.padSwap` is on, your pad becomes P2's and P1 gets a
   neutral pad;
3. run every `ctx.hooks.input` stage in order (recorder, dummy, menu's pad
   conveniences). A stage that wants to drive a player sets `ctx.out[i]` to a pad
   table; later stages that respect `ctx.out` yield (that is the whole priority
   scheme: recorder playback > dummy layers);
4. `emu.setInput(out or eff, 0, port)` for both ports.

One subtlety bites every new stage: at `inputPolled`, `ctx.snap` is the **previous**
frame's (last classified) snapshot — the current frame hasn't run yet. Both
`recorder` and `dummy` carry comments about the ordering trap: a *frame* hook
placed before `framedata` would see unclassified frames, so trigger detection lives
at the top of the input stage instead, where the last frame is fully classified.

### 5.6 Headless mode and why pcall is everywhere

The same package runs under Mesen's GUI and under the headless test runner
(`tools/training_test.lua`, self-tests T1–T11). Headless: there is no keyboard
(`isKeyPressed` errors on every name), no visible scriptHud (degenerate size), no
toasts wanted, and pads come from the harness. Hence: every `isKeyPressed` behind
`pcall`, every drawer tolerating a nil surface, every `displayMessage` behind
`if not ctx.headless`, and `ctx.padSource`/`opts.modules` as injection points. And
one platform law colors everything: **anything thrown inside a memory callback dies
silently** ([SNES-36]) — code reachable from the exec anchor must not throw.

---

## 6. Module walkthrough

The one-line roles are in §5.3's table; this section explains only what is not
obvious from reading each file top to bottom.

### 6.1 `gamestate.lua` — the snapshot

`samplePlayer` reads ~20 struct fields into a plain table; two projectile slots get
a smaller sample (`alive` = object id nonzero and < 0x80). The snapshot also grabs
the raw pad words and the camera X. Snapshots go into a 600-entry ring buffer;
`ago(k)` walks it backwards. Entries are **enriched in place** later by `framedata`
(class/invuln/frozen tags) — which is what lets the frame meter hold *references*
into history and have retroactive repaints (multi-hit gaps) appear on screen for
free (§6.6).

### 6.2 `framedata.lua` — the correctness core

Read this one file completely before extending anything that consumes classes. The
concepts:

* **Class, per player, per frame** — NEUTRAL/MOVEMENT/STARTUP/ACTIVE/RECOVERY(_C)/
  HITSTUN/BLOCKSTUN/BLOCKHOLD/KNOCKDOWN/THROWN/TECH/OTHER, plus three booleans:
  invulnerable (hurtbox index 0 or hurt-state ≥ 0x80), frozen (hitstop ≠ 0),
  cancellable (this act is in the character's cancellable-recovery set).
* **A move instance** is tracked per player: S/A/R counts (non-frozen frames only),
  the act chain it passed through, active phases with gaps. It ends into a summary
  (`ctx.lastMove[i]`, `moveEnd` event) on: reaching neutral, being hit/thrown, or
  cancelling into a new move.
* **The pending-start dance.** The engine's "this is an attack" flag (+0x18) only
  rises at step 1 — one frame *after* an attack act starts ([measured; `const.lua`
  header]). So a fresh act ≥ 0x2B at step 0 is classified STARTUP *optimistically*
  and recorded as pending; if the flag never confirms, that one history frame is
  repainted MOVEMENT (dashes take this path). If it confirms, the move is backdated
  to its step-0 frame.
* **ACTIVE needs a real box**: hitbox index ≠ 0 AND that box's height > 0 — the
  generated `hitbox_h.lua` table exists because some box indices are placeholder
  zero-height entries. A box persisting into the recovery act's first frame stays
  ACTIVE (measured: it can still hit there).
* **Multi-hit moves**: a gap between active phases is recorded (`phases`), and the
  gap frames — classified RECOVERY while being lived — are retroactively repainted
  STARTUP once the next active phase proves the move wasn't over.
* **Projectile moves never go active on the body** (the hitbox lives on the
  projectile slot), so a return to neutral closes the instance even with no active
  frames seen — without this the attacker sticks in STARTUP forever and downstream
  consumers (regen's gating, T10) break.
* **Connects** are detected from the defender's side: HP drop = hit, blockstun
  entry = block, held-act entry = throw. `viaProj` marks hits where the attacker's
  body wasn't active but their projectile is alive.
* **Advantage settlement**: after a connect, wait until the attacker reaches
  neutral and the defender — who must first have actually *been* constrained,
  because their reaction starts a frame after the connect — reaches neutral, with
  no projectile alive (a live fireball means nobody is "at advantage" yet).
  `adv = defenderNeutralT − attackerNeutralT`. `cAdv` additionally treats the
  attacker's cancellable-recovery frame as free — in this game the links live
  there, so the panel shows both (`hit +6 (c+12)`).
* **Discontinuity guard**: any HP *increase* (regen refill, harness pokes) resets
  all cross-frame state. The `reset()` clears everything — issue #96 was exactly
  three fields missed by #15's fix (a stale pending start backdating across a
  reload, and stale lastMove/lastAdv satisfying a later test phase).

It also exposes the package's event bus: `framedata.on.moveStart / moveEnd /
connect / settled` — arrays of listener functions, `(event, ctx)` each. `combo`,
`labels` and `hud_bar` are consumers; your extension can be too.

### 6.3 `combo.lua` — TRUE vs DROPPED

A combo (per defender) counts connects; it is *fresh* if the defender had an
actionable frame since the previous hit, in which case the count restarts flagged
`reset` (the HUD shows the pressure string wasn't a true combo). A continuing hit
that lands with the defender already out of stun **on the connect frame** — zero
free frames recorded — is a *tight link*: a non-bufferable 1-frame meaty (the
Uranus-infinite case), flagged `tight` and shown magenta with a "1F" tag by
`hud_combo`. A combo closes after ~10 free frames with no live threat (attacker
not in STARTUP/ACTIVE, no projectile).

### 6.4 `labels.lua` — event popups

GC (guard cancel — this game's defining mechanic) is a move starting ≤ 1 frame from
a BLOCKSTUN frame; REVERSAL is scoped to *hard*-constraint exits (hitstun/
knockdown/throw) so the two never overlap; PUNISH is a hit landing on RECOVERY.
THROW TECH / THROWN come from act transitions, TRADE from both players connecting
the same frame. Labels dedupe (same text within 30 frames), live 90 frames, blink
out, and render in two places (above the meter and/or per-side under the combo
counter) per `ctx.ui.labelMode`. A MEATY label existed through v0.20 and was removed
on player feedback — the removal is itself pinned by a test (T-series) and by
`checktrainingdocs`, which is why you will find the *detection rule* still
documented in the engine doc but no label here.

### 6.5 `regen.lua` — timer, HP, KO

Three conveniences with one non-obvious piece: the HP refill writes the struct HP
*and* the latched bar value (`0x0801`), then **repaints the bar's VRAM tilemap
cells directly** — because the game's HUD producer only repaints the single
boundary tile per frame during a *drain* animation, has no fill path, and shows
fill level by palette. An instant refill without the repaint leaves the emptied
cells red ("disjointed red parts", the original field report). KO reset triggers on
`hp == 0` while in a knockdown act — death is underflow, and waiting for the KO act
(0x1F, ~130 frames later) would let the round end ([SMS-9]). A baseline position
state is auto-captured at `ctx.t == 30` if you never pressed Q, so KO reset always
has a target.

### 6.6 `hud_bar.lua` — the frame meter

Cells are **references to history snapshots**, not copies — so when `framedata`
retroactively repaints a class (pending starts, multi-hit gaps), the meter shows it
automatically. The SF6 freeze model: cells append only while there is *activity*
(either player non-idle or a projectile alive) plus a 20-frame grace, so the last
exchange stays readable while both idle. Segment counts print non-frozen frames at
run starts; the advantage badge lands on the settlement column between the tracks.

### 6.7 `hud.lua` + drawers

`hudSurface()` selects the scriptHud surface at the configured scale and returns its
size — cached per frame, nil when degenerate (headless, or width < 300). Every
drawer starts with `if not hud.show(part) then return end` (the hudMode visibility
matrix) and copes with a nil surface; `hud_panel` falls back to a terse console-
surface layout. `hud_boxes` and `hud_combo` draw on the console surface on purpose
(game-pixel alignment / chunky scaling).

### 6.8 `recorder.lua` and `dummy.lua` — driving P2

Covered by the user doc for behaviour; the implementation notes that matter:
recordings are arrays of facing-relative masks, so they mirror when sides swap;
slot persistence survives restarts via `traces/training_slots.lua` (written as Lua
source, reloaded with `dofile`; a corrupt file flips persistence read-only rather
than letting a later save wipe it — #31). The `random` trigger uses `math.random`,
not frame-parity (#17 — frame-modulo was deterministic under the harness). The
dummy resolves each frame through a priority stack (wakeup one-shot → tech mash →
guard → pose), returns nothing when playback already set `ctx.out`, and "stand"
means *no override* so a second human pad can drive the dummy. The throw-tech
layer presses HK every other frame — the 30 Hz latch counts that as a fresh press
each time, and two sampled presses escape a throw for half damage (patch-8
measured mechanics).

### 6.9 `hud_pianoroll.lua`

Tracks what the player's character *actually received* (`ctx.out` if overridden,
else the effective pad) — so during playback it shows the recording, which is the
point. Rows compress consecutive identical inputs (`x12`), directions render as
numpad notation, and the strip anchors to the tracked player's screen side so it
never covers the action it documents.

### 6.10 `menu.lua`

Two tables rule it: `rows` (label + getter + changer per menu line) and `PERSIST`
(key + getter + setter per persisted setting). They are deliberately separate but
**must stay in step**: a menu-visible setting missing from PERSIST is the one-way
persistence drift of issue #32, and `checktrainingdocs` counts them against each
other. Settings save on menu close to `traces/training_settings.lua` (same
Lua-source round-trip as slots). The pad conveniences (hold-R momentary pad swap,
Select = record toggle) read *physical* pads and edge-detect.

---

## 7. Testing

`tools/training_test.lua` runs the same package headless (`opts.headless`, injected
`padSource`, scripted scenarios on a fixture savestate) and asserts T1–T11 — each
test's subject is listed in its header; several pin regressions by number (T10:
projectile specials must close their move instance, else HP regen never fires
again; T11: a savestate reload clears framedata's cross-frame state). Run:

```bash
ROM=<v0.7-family rom> tools/run.sh tools/training_test.lua 400
```

`tools/checktrainingdocs.py` (no ROM needed; in `health.sh` and CI) verifies the
user docs — hotkeys, menu rows and their order, value lists, labels, file
inventory, self-test ids — against the Lua both ways, and verifies THIS file's §5.3
module map and MODULES load order against `main.lua` and the package on disk.

What cannot be tested headless is the visuals themselves ([SNES-39]); the GUI smoke
checklist in `training.lua`'s header is the manual gate.

---

## 8. Worked example: adding a module

Goal: an **act logger** — show the last few action-ID transitions per player, with
frame stamps; toggled by a hotkey; the toggle remembered across sessions. Useful
when reverse-engineering a move's act chain.

**1. The module** — `tools/training/actlog.lua`:

```lua
-- actlog.lua — rolling log of act transitions per player (RE aid).
local M = {}

function M.init(ctx)
  local C = ctx.C
  local hud = ctx.mod.hud            -- ok: hud loads before us in MODULES
  M.enabled = false
  local log = { {}, {} }             -- per player: { {t=, from=, to=}, ... }
  local KEEP = 6

  local function step()
    local s, q = ctx.snap, ctx.prev
    if not s or not q then return end
    for i = 1, 2 do
      local a, b = q.p[i].act, s.p[i].act
      if a ~= b then
        local l = log[i]
        l[#l + 1] = { t = ctx.t, from = a, to = b }
        if #l > KEEP then table.remove(l, 1) end
      end
    end
  end

  local function draw()
    if not M.enabled then return end
    local surf = hud.hudSurface()
    if not surf then return end
    local w = surf.visibleWidth or surf.width
    for i = 1, 2 do
      local x = (i == 1) and 8 or (w - 150)
      for k, e in ipairs(log[i]) do
        emu.drawString(x, 60 + k * 10,
          string.format("t%-5d %02X>%02X %s", e.t, e.from, e.to,
                        C.ACT_NAMES[e.to] or ""),
          C.COL.text, C.COL.black)
      end
    end
  end

  ctx.actions.actlog = function()
    M.enabled = not M.enabled
    if not ctx.headless then
      emu.displayMessage("training", "act log " .. (M.enabled and "on" or "off"))
    end
  end
  ctx.cfg.keys.actlog = ctx.cfg.keys.actlog or "L"

  table.insert(ctx.hooks.frame, step)
  table.insert(ctx.hooks.draw, draw)
  table.insert(ctx.hooks.reset, function() log = { {}, {} } end)
end

return M
```

**2. Register it** — add `"actlog"` to `MODULES` in `main.lua`, after the modules
it uses (here: after `"hud"`; before `"menu"` if a menu row should find it).

**3. If it gets a menu row, it gets a PERSIST entry** — add BOTH to `menu.lua`
(the #32 rule; `checktrainingdocs` counts rows against PERSIST entries, and the
usage doc's menu table must gain the row or the checker goes red — that is the
system working).

**4. Update the docs and gates** — the new file must appear in
`training_install.md`'s package listing and in §5.3's table here (both are checked
against disk), the hotkey in `training_usage.md`'s table (checked), and a headless
T-test in `training_test.lua` if the module has any logic worth pinning.

The checklist distilled — every stateful module MUST:

* register a **reset hook** clearing all cross-frame state (#15/#96 — state
  surviving a savestate reload is this package's most-repeated bug);
* guard every `displayMessage`/`isKeyPressed` for headless (§5.6);
* tolerate a nil HUD surface;
* read game state from `ctx.snap`/`ctx.prev` (never `emu.read` in a frame hook
  unless the field isn't sampled — then add it to `gamestate` instead);
* remember input stages see the previous frame's classification (§5.5).

---

## 9. Where the bodies are buried (quick trap index)

| Trap | Where it's handled | Rule |
|---|---|---|
| `setInput` port is the 3rd arg | `input.lua` | [SNES-35] |
| throws inside memory callbacks die silently | anchor design, §5.4/§5.6 | [SNES-36] |
| savestates need a CPU-exec context | `ctx.anchor` requests | [SNES-38] |
| scriptHud degenerate headless; screenshots don't composite it | `hud.lua`, smoke checklist | [SNES-39] |
| 30 Hz input latch | dummy tech mash, oneshot ≥ 2f holds | [SNES-40] |
| attack flag rises at step 1, not 0 | framedata pending starts | `const.lua` header |
| hitstop freezes counts | every S/A/R increment gated on `not frz` | §6.2 |
| projectile moves never body-active | framedata close-at-neutral | T10 |
| state surviving reloads | reset hooks everywhere | #15, #96 |
| one-way persistence | menu rows ↔ PERSIST symmetry | #32 |
| corrupt slots file | read-only latch | #31 |
| deterministic "random" | `math.random`, not frame parity | #17 |
| flame/electric are hitstun too | `C.isHitstunAct` to 0x18 | #99 |
