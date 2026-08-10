# SMS engine internals — a subsystem reference

**What this is.** A synthesized, *explanatory* map of how Bishoujo Senshi Sailor Moon S:
Jougai Rantou!? (SFC, Japan) works internally — the knowledge extracted across this project,
organized by subsystem so a human or a future model session can **understand and modify** the
game, not just look up an address.

**How it relates to the other docs** (read in this order for a new topic):
- **This file** — how a subsystem *works* and *why*, with the load-bearing addresses inline.
- `docs/game/sms_data_architecture.md` — **where the data LIVES and what SHAPE it is**: the four
  memory maps (ROM/WRAM/VRAM/ARAM), the object struct byte by byte, and the record formats
  the engine walks. Read it when the question is "where would that be stored?".
- `docs/game/annotations.md` — the flat address→label reference (the "phone book"). Every address
  here is (or should be) there too; that file is the source of truth for exact addresses.
- `docs/game/sms_quickref.md` — the one-page address card; every entry points somewhere longer.
- **The frame, drawn** — one pass of the in-match loop with every address on it, and every
  shipped patch pinned to the stage it changes (§3):
  <https://definitelyfrenchname.github.io/SMS-FrenchName-edition/frame.html>
- `docs/project/patch_notes.md` — per-patch detail (what each patch changed and why; the count grows — docs/project/patch_index.md is the registry).
- `docs/game/sms_all_boxes.json` — extracted per-character/​object hit/hurt/coll box tables.
- `docs/game/sms_acs_system.md` — the A.C.S. stat system, damage matrix and misfire mechanic, complete.
- `docs/game/sms_sound_system.md` — the audio path: APU upload, the SPC driver (stored in
  ROM), sound ids, and the per-sound transpose byte that tunes every fighter's voice.

**Ground truth.** Clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`, **HiROM +
FastROM**, headerless. **File offset = SNES address & 0x3FFFFF.** Banks $C0–$FF map to file
banks $00–$3F; $80–$BF is the FastROM mirror of $00–$3F (code often executes via the $80
mirror even when a routine is written as `$C0:xxxx`). WRAM `$7E:0000–1FFF` is mirrored into
bank `$00`, so Lua memory callbacks on low WRAM **must** use `snesWorkRam` (absolute), not the
CPU-bus view. Roster charIDs: **1 Moon, 2 Mercury, 3 Mars, 4 Jupiter, 5 Venus, 6 Uranus,
7 Neptune, 8 Pluto, 9 ChibiMoon.** Saturn (10) is a *Super S* character — **not in this game**;
tooling inherited from Super S must never be trusted for Saturn or unverified addresses.

**A rule that recurs everywhere:** *measure, don't infer.* Every timing/behavior claim in the
project was validated by frame-advance in Mesen, never derived from disassembly alone.

---

## 1. Memory map (WRAM)

Low WRAM (`$7E:0000–$1FFF`, mirrored in bank $00):

| Range | What |
|---|---|
| `$005C` / `$005E` | raw joypad word, P1 / P2 (SNES pad bit order: B=0x8000,Y=0x4000,…,A=0x80,X=0x40,L=0x20,R=0x10); press edges in `$0060/$0062`, previous frame in `$0064/$0066` — all derived by joy_read (§3) |
| `$0070` | **in-match flag** — 4 while any match runs (VS *and* Practice), 0 outside |
| `$008D` | **game_mode** — **0 = Story**, **1 = VS (1P-vs-2P)**, **2 = 1P-vs-COM**, **4 = Practice (no HP subtraction)**, **5 = Practice with damage / attract demo** (§10). Full map measured 2026-08-03 (`probe_sms_menurows.lua`) after a wrong "0=VS" annotation cost two field bugs — a `$8D == 1` gate hits **2P VS**, not story. The producer self-gates to matches; a strict mode gate reads `$008D` |
| `$01FA` | screen state: 0x80 = match running, **0xE4 = movelist open** (Start in Practice) |
| `$0800` / `$0801` | **displayed** HP bar value P1 / P2 (drains toward struct HP; written only by the HUD producer) |
| `$0802` / `$0803` / `$0804` | **the round clock is THREE bytes**: `$0802` is a 60-frame tick (reloaded `#$3C`), `$0803` the units digit, `$0804` the **tens** digit; both digits index HUD tiles at `+$2C50`. `$C0:D6A6` raises `$1F5C` when `$0804` underflows, and the clock routine skips itself while that is set. So **`$0804 == 0` means under ten seconds left** — the condition the desperation gate reads (§7.x). Measured 2026-08-10; three other rows called `$0802` "the round timer", which it is not |
| `$0806–$0815` | **HUD tile staging** — (VRAM addr, tile) entries the NMI uploader flushes: P1 bar, P2 bar, timer digits |
| `$0816–$08FF` | FREE **in VS matches only** (patch 10 state lives here) — **native Practice mode touches the whole `$0816–$09FF` range**; do not use it for training-mode state (patch 11 found this the hard way) |
| `$0900–$09FF` | FREE in VS only (patch 10 labels) — same Practice caveat as above |
| `$0A00`/`$0A02` | camera scroll X / Y (world→screen: screen = world − camera) |
| `$1000` / `$1080` | **player structs**, P1 / P2 (0x80 bytes each) |
| `$1100` / `$1180` | **projectile slots**, P1's / P2's projectile (same struct layout) |
| `$1B10` | title menu cursor — the menu is a **2-column × 3-row grid** (nav table `$C0:A29D+cursor*4`): left column 0/1/2, right column 3/**4 = Practice**/5; left/right swaps columns (0↔3, 1↔4, 2↔5). Reach Practice headlessly: down (0→1), right (1→4) |
| `$1B40`/`$1B80` | char-select cursors, `$1B42` P1-confirmed |
| **bank `$7F`** | boot's RAM clear zeroes it once; scene loads / round intros use **`$7F:0000–5FFF`** as scratch; **steady-state gameplay touches none of it** → `$7F:6000+` is free for patch state (patch 11 uses `$7F:F000+` for state, `$7F:E000+` for its recording ring). The **WMDATA port `$2180–$2183`** is never touched by the game — safe as a pointer-addressed window into `$7F` for code without indexed addressing |

### Player / object struct (`base + offset`)

Fighters at `$1000`/`$1080`, projectiles at `$1100`/`$1180`, all share this layout:

| Off | Field | Notes |
|---|---|---|
| +0x00 | **charID / object id** | 1–9 fighters; **10–27 projectile/object types** (e.g. 0x18 = Neptune Deep Submerge); 0 or ≥0x80 = empty/despawned |
| +0x01 | **actionID** | current state/move (see §3) |
| +0x02 | action step | 0 on an action's first frame; **attacks are not processed on step 0** |
| +0x04 | actionID the ANIMATION is playing | latched from +0x01 by the handler tail `$C1:0204`, and only on a transition frame (step still 0), together with zeroing +0x06/+0x07 — see §2.x. Differs from +0x01 only within that frame |
| +0x05 | action sprite | |
| +0x06/07 | anim tick / frame | per-step duration counters |
| +0x09 | facing (flip X) | nonzero = facing left |
| +0x18 | action flags | **bit0 = attack** (the engine's own "this act is an attack" discriminator — more reliable than `act ≥ 0x2B`) |
| +0x20–23 / +0x24–27 | X / Y position | 32-bit subpixel; pixel byte at +0x21 / +0x25 |
| +0x30–35 | X/Y velocity, gravity | 16-bit signed |
| +0x40 | **hitbox index** | attack box; 0 = none. Indexes the object's hit table |
| +0x41 | **hurtbox index** | 0 = **invulnerable** (empty hurtbox is the invuln mechanism, not a flag) |
| +0x42 | collision/push index | |
| +0x43 | attack_connected | set on connect; gates hit-confirm cancels (NOT hitstop) |
| +0x44 | attackID / strength class | ≥0x12 super, ≥0x8/0xC special, ≥0x4 heavy, else light |
| +0x45 | attack damage | |
| +0x46 | **hurt_state** | ≥0x80 = invuln/untargetable; 0xA0 = knockdown-untargetable; 0xE0 = thrower during a grab; `%0x40 ≥ 0x20` = in hit/blockstun |
| +0x49 / +0x4A | **HP / max HP** | base 96 (0x60) |
| +0x4D | **hitstop** countdown | nonzero while frozen on hit (≈8 frames); anim ticks stall while nonzero |
| +0x50 | buttons held | 1=back 2=fwd 4=down 8=up 0x10=LP 0x20=LK 0x40=HP 0x80=HK; **press bits latch on a 30 Hz tick** (~1 fresh press per 2 frames) |
| +0x54 | normal-action flags | same bit layout |
| +0x56 | throw mash counter | thrower's; ≥2 → victim techs |
| +0x5B–0x68 | command timer/state pairs | motion recognizers; **+0x5D = the 66 forward-dash frame counter (1..14)** |
| +0x77 | action_strength | 7=LP 8=LK 9=HP 10=HK (the *label* comment in vendor Lua is wrong; trust the mapping **Y=LP X=HP B=LK A=HK**) |

---

## 2. Action-ID taxonomy

Universal states (same across all fighters):

```
00 neutral      01 walk fwd    02 walk back   03 crouch      04 half-crouch
05 prejump      06 jump up      07 jump fwd    08 jump back   09 landing
0C stand block  0D crouch block                (guard HELD)
0E stand blockstun   0F crouch blockstun       (in blockstun)
10 head hitstun L  11 head H   12 body L  13 body H  14 duck L  15 duck H   16 air hitstun
17 flame        18 electric     (special hit reactions)
19 knockdown    1A heavy KD     1B thrown(face up)  1C HELD(grab victim)  1D thrown(feet up)
1E down         1F KO           20 stand-up     21 neutral(low HP)   22 intro
23 THROW TECH   24 victory      25 freeze       26 backdash          27 slip
28 down         29 stand-up     2A embarrassed
```

Per-character **attacks and specials are 0x2B+** (their exact IDs are only fully mapped for
Uranus — e.g. 2LP=0x53, 2HP=0x55, forward dash "Shadow Dash"=0x60). Classify "is this an
attack" by **+0x18 bit0**, not the ID range (char-specific space mixes attacks and movement).

**Constraint sets used by frame-data / combo logic:**
- *hard constraint* (hitstun/KD/thrown): 0x10–0x20, 0x27–0x29.
- *any constraint* (add blockstun): 0x0E–0x20, 0x23, 0x27–0x29.
- *actionable / neutral*: 0x00–0x04, 0x0C, 0x0D, 0x21 — plus each character's **cancellable
  light-recovery set** (this game's links live in these frames):
  Moon {42,48,54,58} · Mercury {41,46,53,57} · Mars {42,49,55,59} · Jupiter {42,47,53,57} ·
  Venus {41,45,51,55} · Uranus {42,48,54,58} · Neptune {41,45,56,5A} · Pluto {41,49,55,59} ·
  ChibiMoon {41,47,53,57}. (No Saturn.)

### 2.x The act table, handler anatomy, and how moves CHAIN (measured 2026-08-10)

> **Drawn:** figure 1 of [how an act is chosen](https://claude.ai/code/artifact/fc6c32ec-753b-459d-bbfe-f69601d766fc) — the dispatch, the
> step-gated handler, the tail, and the chain.

**One handler per ACT, in a per-character table** — not one per move, and not one
shared for all of a character's moves. Each character's proc block opens with a
dispatch, and the table sits immediately after it at **proc + 0x0F**:

```
C1/79F2:  rep #$10 / ldx $88 / lda $01,X / asl A / tax / jmp ($7A01,X)
```

| character | proc | act table | ends at | slots | null | implemented | distinct handlers |
|---|---|---|---|---|---|---|---|
| Moon | `$C1:270B` | `$C1:271A` | `$C1:27FC` | 113 | 21 | 92 | 79 |
| Mercury | `$C1:3779` | `$C1:3788` | `$C1:386A` | 113 | 21 | 92 | 78 |
| Mars | `$C1:47A6` | `$C1:47B5` | `$C1:48A1` | 118 | 21 | 97 | 81 |
| Jupiter | `$C1:5886` | `$C1:5895` | `$C1:597F` | 117 | 21 | 96 | 84 |
| Venus | `$C1:6B0A` | `$C1:6B19` | `$C1:6BEF` | 107 | 21 | 86 | 72 |
| Uranus | `$C1:79F2` | `$C1:7A01` | `$C1:7AF5` | 122 | 21 | 101 | 87 |
| Neptune | `$C1:8DA2` | `$C1:8DB1` | `$C1:8E99` | 116 | 21 | 95 | 79 |
| Pluto | `$C1:9E0A` | `$C1:9E19` | `$C1:9EF3` | 109 | 21 | 88 | 73 |
| ChibiMoon | `$C1:AE47` | `$C1:AE56` | `$C1:AF32` | 110 | 21 | 89 | 75 |

⚠ **The table is 107-122 entries, NOT 128** — it ends where that character's standing
normals table begins (§7.x), and reading past that end returns normals records
misparsed as pointers. 128 is the **Super S** figure the Saturn port uses
(`tools/saturn/port_saturn_proc.py`), and it does not hold here.

⚠ **Every character has exactly 21 null (`$0000`) slots**, and in Uranus they are the
contiguous block `0x2B-0x3F` — so although the per-character space nominally starts
at `0x2B`, *her* character-specific acts actually begin at `0x40`.

**Sharing is deliberate, and it tells you what the acts are.** Uranus's 101
implemented acts use 87 handlers:

```
$C1:813E <- 0x10 0x11 0x12 0x13   the hitstun quad
$C1:81F0 <- 0x17 0x18 0x19        $C1:8442 <- 0x44 0x46 0x4A
$C1:8254 <- 0x14 0x15             $C1:823C <- 0x1A 0x1B
$C1:83D7 <- 0x42 0x48   \
$C1:86EA <- 0x54 0x58    >  her cancellable light-recovery set {42,48,54,58} above:
$C1:8756 <- 0x56 0x5A   /   the pairs share a handler BECAUSE they are one routine
$C1:8957 <- 0x63 0x64   |   entered at two points
$C1:8974 <- 0x65 0x66   |   LP/HP strength variants
```

Blockstun `0x0E`/`0x0F` do **not** share — they are different stances and pass
different normals tables (§7.x).

#### Handler anatomy

Every handler has the same shape, gated on the step byte `+0x02`:

```
rep #$10 / ldx $88 / sep #$20
lda $02,X / bne <body>        ; already running? skip the init
  inc $02,X                   ; step 0 -> 1, so the init runs exactly once
  <STEP-0 INIT>               ; stz $46,X, stz $43,X, +0x44 class, +0x45 damage,
                              ; +0x54 script, velocities, +0x78 sound …
<body>                        ; per-frame work
<start routes>                ; jsr $0459 / $0958 / $055A  (§7.x)
jmp $0204                     ; the tail
```

⚠ **The step-0 init is a per-handler CONTRACT, enforced by nothing.** With ~87
hand-written handlers per character and no shared prologue, an omission survives —
which is exactly patch 2: Uranus's dash handler `$C1:88C8` lacks the `stz $46,X`
that Moon's `$C1:3419` has at `$C1:3425`, so a dash out of knockdown keeps
`+0x46 = 0xA0` and stays untargetable for its whole duration (§6).

#### Chaining — two primitives

**`$C1:0224`, the act setter**, is how every transition happens:

```
C1/0224:  rep #$10 / ldx $88 / sep #$20 / sta $01,X / stz $02,X / rts
```

Setting an act **always resets the step to 0**, which re-arms the next handler's
step-0 init. That single `stz $02,X` is what makes a chain of acts work.

**`$C1:0204`, the tail** every handler jumps to, re-latches the animation:

```
C1/0204:  lda $02,X / bne done      ; only when the step is still 0 …
          lda $01,X / sta $04,X     ; … latch the act into +0x04
          stz $07,X / stz $06,X     ; … and restart the anim tick/frame
```

Step is 1 by the time a handler reaches the tail *unless* something set a new act
during this frame (the setter zeroed it). So the tail fires precisely on a
transition, and its job is to point the animation at the new act and rewind it.
`+0x04` is therefore the act the ANIMATION is playing, and `+0x01` the act the
logic is in; they differ only within the transition frame.

**A move is therefore a chain of acts, not one handler.** Uranus's SPD runs
`0x67`/`0x68` (start) → `0x71` (toss); Jupiter's Giant Swing `0x6D`/`0x6E` →
`0x6F`/`0x70` (carry). Only the entry act is in the special-start table (§7.x);
the later acts are reached by their predecessor calling the setter, which is why
they are neither startable nor guard-cancellable on their own.

---

## 3. Frame lifecycle — main loop and NMI

Two clocks matter: the **main loop** (runs through the visible frame) and the **NMI/vblank**
handler (uploads graphics). Key routines and where they run (measured by PPU scanline):

> **The loop itself is disassembled**, stage by stage, in
> `sms_data_architecture.md` §10B — the in-match loop is `$C0:E255` and its call
> list is read out of the ROM, not inferred. There is a drawn version of the same
> thing (the frame, the six phase loops, where a hit is really resolved, and the
> stage each patch hooks) at
> <https://definitelyfrenchname.github.io/SMS-FrenchName-edition/frame.html>,
> generated by `tools/mkenginepage.py`. Read either before hooking anything
> per-frame: **hit resolution is not a stage of the loop** — the characters' own
> procs call it, which is why a reaction lands a frame after the hit that caused it.

| Routine | Addr | When | Does |
|---|---|---|---|
| joy read | `$80:8353` | once/frame, **NMI scanline 237** (before the uploader in the same NMI) | copies prev held to `$64/$66`, reads pads into `$5C-$5F`, then derives press edges `$60/$62`. Canonical per-frame anchor for tooling. **`$80:8373`** (between held-store and edge-derivation) is the perfect input-override hook: rewrite `$5E/$5F` there and the game derives edges itself — the 30 Hz latch and motion recognizers (44 backdash included) behave exactly as with a real pad (patch 11's dummy) |
| per-object update | `JSL $C1:0000` | main loop | runs each object's state proc (state procs ≈ `$C1:122A`, `$C1:15BD`) |
| box-index writer | `$C0:9CCD` (batch `$C0:9CA4–9CE1`) | main loop | per object, writes +0x40/41/42 from the current anim frame |
| **HUD producer** | `$C0:D5E8` | **main loop, scanline 101, once/frame — VS/story matches only, NEVER in Practice (§10)** | animates displayed HP `$0800/01` toward struct HP, computes bar+timer tiles into `$0806-$0815`, decrements timer `$0802` |
| **HUD uploader** | `$C0:D56F` | **NMI/vblank, scanline 237 (after joy_read), every mode incl. Practice** | flushes the `$0806-$0815` staging to VRAM (`$2116/$2118`); in Practice the staging is always clean and it falls straight through — but it still runs, which is why patch 11 hooks **`$80:D574`** (inside it) for vblank VRAM work |

This **producer → staging → uploader** split is the "Arch A" HUD design: the main loop writes
what to draw into WRAM, the vblank handler pushes it to VRAM. Patch 10 rides both hooks (see
§11) — compute in the producer, draw in the uploader.
**In Practice mode the producer NEVER runs** (§10) — hook it and your code is dead there.

**FastROM headroom.** A frame is ≈40,850 CPU-cycle-counter units as measured; patch 10's added
per-frame work is ~0.6% (counter) to ~2.6% (counter+labels), and clean-vs-patched gameplay RAM
stays **frame-identical** — i.e. the main loop has ample slack before the vblank deadline, so
small per-frame additions never drop a frame. The lag test that matters is *frame identity*,
not the cycle percentage.

---

## 4. Rendering — BG layers, HUD tilemap, tiles

Mode 1. Layer configuration in a match (from PPU state):

| BG | CHR base (word) | Tilemap (word) | Depth | Role |
|---|---|---|---|---|
| BG1 | 0x2000 | 0x0000 | 4bpp | gameplay background |
| BG2 | 0x2000 | 0x0800 | 4bpp | background |
| **BG3** | **0x5000** | **0x1000** | **2bpp** | **the HUD** (bars, nameplates, timer) |
| BG4 | 0x5000 | 0x1000 | 2bpp | (shares BG3) |

So the **HUD is BG3, 2bpp** — tile T's CHR is at word `0x5000 + T*8` (16 bytes/tile), and the
HUD tilemap is at word `0x1000` (32 cells/row). A tilemap word is `flip<<14 | prio<<13 |
palette<<10 | tile`; HUD text uses `0x2C00 | tile` (priority + palette 3).

**HUD tilemap layout** (rows from word `$1000`, 32 cols):
- rows 0–2: blank (above the bars — may be off the top of the visible area)
- rows 3–4: HP bars
- row 5: character nameplates (e.g. "VENUS" = tiles at cells `$10A2+`) + timer digits
- row 6: timer bottom at `$10CF/D0`; **round-won badges** at cols 2-3 / 4-5 (P1) and 26-27 / 28-29 (P2)
- row 7: the badges' bottom halves, same columns — **not blank**, whatever a mid-round census says

**The round-won badge.** The medallion under a life bar is a 2x2 BG3 block whose top-left
cell comes from a **ten-entry table at `$C0:E166`** (index `charID*2`, word =
`prio<<13 | palette<<10 | tile`); the code derives the other three as `T+1`, `T+$10`,
`T+$11`. Ids 1-8 are tiles `$0E0`-`$0EE`, **id 9 reuses id 1's** — Chibi Moon wears Moon's
crescent. P2 ORs `#$0400` after the read, moving BG3 palette 6 to 7, so one entry serves
both players; the four colours come from the manifest's `+7` pointer, loaded at char load
into CGRAM shadow `$0530` (P1) / `$0538` (P2).
⚠ **The table is read from EIGHT sites** — two build the `$0820` descriptor at first draw,
four write `$2118` directly on the redraw, two rebuild the descriptor at match end. Six of
the eight are P2 or redraw paths, so anything keyed on charID must patch all eight or it
will work in exactly the case you test first. Full census: `annotations.md`.

**Resident HUD glyph tiles (CHR at word 0x5000):**
- **Digits 0–9**: big 2-tall glyphs, tile `0x50+N` (top) / `0x60+N` (bottom). Always present
  (the timer draws them). Tilemap word for digit N top = `0x2C50+N`. Patch 10's combo counter
  reuses these.
- **Nameplate letters**: tile-id layout A=0x70 … Z=0x89, **but the glyph bitmaps are loaded
  per-matchup, not a resident A–Z font** — and **"G" appears in no character's name**, so you
  cannot rely on nameplate tiles for arbitrary text. Patch 10's status labels upload their own
  2bpp font (`tools/hudfont.py`) to **free CHR slots 0xC7–0xDF** (verified zero across 5
  matchups) and DMA them in during vblank.

**Layer enable (TM, `$212C`) is written only at scene setup** (zero writes observed over
in-match probes) — a VS match runs TM=0x17 (BG1+BG2+BG3+OBJ); **Practice runs TM=0x13 (BG3
off)** because BG3 there is the pre-staged movelist, shown by flipping TM when Start is
pressed (§10). A patch can therefore own TM mid-scene by writing it per-vblank; the game
won't fight back until the next scene load. `mode1Bg3Priority` is set, so priority-bit BG3
tiles (word `0x2C00|tile`) render **above sprites** — floating-UI friendly.

Title-screen text is a separate pipeline (patch 4): a once-per-load force-blank DMA hook at
`$C3:B81F`; that technique does **not** transfer to per-frame in-match rendering.

---

## 5. Box system (hit / hurt / collision)

Every box is 8 bytes: `[x_off_R, w_R, x_off_L, w_L, y_off(signed), h, flags, unused]`. Origin
is at the character's feet, **+y is down**, so a negative `y_off` is above the feet. `h == 0`
or `w == 0` = no box. Facing selects the (x_off, w) pair. Box `flags` bit0=H bit1=L bit2=J
(guard height / jump property).

**Tables live in bank $8A, selected by pointer tables indexed by `id*2`:**

| Kind | Pointer table | Entry size | Read via |
|---|---|---|---|
| hit (attack) | `$8A:C1F1` | 8 bytes | +0x40 |
| hurt | `$8A:C229` | **16 bytes** (body + head, two 8-byte boxes) | +0x41 |
| collision | `$8A:C23D` | 8 bytes | +0x42 |

The per-frame **box-index writer `$C0:9CCD`** (`sta $41,X`) copies the current animation
frame's box indices into +0x40/41/42 for every object. Patch 6 hooks this writer to force
+0x41=0 (invuln) during specific Uranus dash frames.

**Invulnerability = empty hurtbox (index 0), not a flag.** The backdash is invincible because
its animation uses hurtbox index 0 for all 14 frames. Separately, `+0x46 ≥ 0x80` marks a
character untargetable (knockdown, thrown, etc.).

**Projectiles extend the box system — but only the HIT pointer table.** The hit pointer table
was widened to **28 entries** so object ids 10–27 have their own hit tables (e.g. Deep Submerge
id 0x18 → `$8A:FD51`). The **hurt and coll pointer tables remain roster-only (≈10 entries)** —
so indexing them by `objid*2` runs off the end into unrelated data (obj 0x18 "hurt" resolves to
the garbage pointer `$8A:1DF8`). This is fine for gameplay (projectiles aren't destructible —
nothing reads their hurtbox), but **any tool that draws a projectile's hurt/coll box must skip
it** or it renders a flickering phantom from garbage (this bit the hitbox viewer; fixed by
drawing only the hit box for ids ≥ 10).

`docs/game/sms_all_boxes.json` holds the extracted tables (all 9 fighters complete). Live reads:
`$8A0000 + read16($8A:C1F1 + id*2)` gives the hit-table base.

---

## 6. Hit resolution and combat mechanics

- **Strike hit check** `$C0:BFC0` (vs players; `$C0:C352` vs projectiles; `$C0:C745`
  push/collision). Box-overlap tests `$C0:C959/C9DF`, DB=$8A during them.
- **On-hit tables** `$C0:CDD5+` (**ten** tables, stride 0x40: CE15, CE55, CE95, **CED5**, CF15,
  CF55, CF95, CFD5, D015 — CED5 was missing from the docs until 2026-08-08), 4-byte entries `[damage, hitstun, level,
  flags]`, indexed by `(attackID>>1)*4`. These are **GLOBAL / strength-class-indexed — never
  patch hitstun here** (it changes every character's move of that class). Damage scaling matrix
  `$C0:D081` (lookup `$C0:D055`).
- **Damage application** (patch-13 RE): all strike/chip damage funnels through **8
  identical apply sites** in bank $C0 (one per on-hit-table variant): `lda $0049,Y / sec /
  sbc $00 / sta $0049,Y / cmp #$90` — defender struct in Y, final damage staged in **DP
  $00**, D register = 0. Chip exists for specials (~quarter) and flows through the same
  sites; blocked normals stage 0. Throw damage applies separately: full at `$C1:082F`
  (damage in DP $05), teched at `$C1:084D` (adds the negated half). The 16×16 matrix at
  `$C0:D081` (lookup `$C0:D055`, executed once per landed hit) is a **damage-variance
  table** — the same move rolls different damage by RNG phase (`$0090`); fixed input
  timing ⇒ deterministic rolls (why the test suites see stable values).
- **VS round flow** (patch-13 RE): KO → 0x1F, winner plays victory 0x24, then **both
  structs re-init on the same frame (HP → max, acts → 0)** — no intro act, and
  `$0070/$01FA/$008D` never change across the transition. `$080C` increments on a round
  win.
- **Hitstop** freezes the attacker's anim tick ≈8 frames on a chained hit (`+0x4D` counts it).
  Frame-data counts *exclude* hitstop frames so on-hit and whiff startup/active/recovery match.
- **"Hit beats same-frame block."** A hit landing the exact frame the defender first raises
  block still connects. This is the load-bearing rule behind the **meaty** — a hit on the
  defender's first out-of-hitstun frame is unblockable-by-holding-back (though an invincible
  reversal or jump still escapes it). It's what makes the canonical Uranus infinite (patch 1,
  N=6) real only under frame-perfect execution.
- **30 Hz input latch.** Fresh-press bits in +0x50 latch on a 30 Hz tick, so mashing yields ~1
  useful press per 2 frames — relevant to throw teching and any mash-based dummy.

---

### 6.x Counter-hit bonus, posture tables, and the head/body question (probe_hitzone, 2026-07-18)

- **Counter-hit / punish bonus — EXISTS.** A hit landing while the defender is inside an
  attack-family act (a normal's act from startup through recovery, a misfire/taunt act)
  deals extra damage: Uranus 5HP 8/10 → 12/14 vs Jupiter's 5HP startup; 2HP 7/9 → 11/12
  vs a crouched 2LP startup; Moon 5HP 6 → 9 vs Moon's taunt act, measured at two depths
  into the animation (both 9 — the bonus is flat across the act, startup AND recovery).
  It ENDS when the move chains into the universal recovery act 0x2A: hitting that tail
  deals plain damage (6). Magnitude: exactly **−2 damage-matrix columns** (proven by
  read-watching the matrix at $80:D07B — see docs/game/sms_damage_system.md §3; the percent
  effect varies with row curvature, ≈+30-70%); the apply site/PC is unchanged, so it is
  a modifier input, not a separate table. The matrix itself is 64×16 (file
  0xD081-0xD480), row 48 = the shared single-hit desperation row. Practical reading: "punishing" a whiffed move is rewarded
  with counter-hit damage only while the victim is still in the move's own act — a late
  punish into the 0x2A tail is normal damage.
- **No head/body hurtbox damage split** (community folklore tested): levitating the
  attacker so the same normal contacts the defender 12/24 px higher (torso → head zone)
  leaves damage identical on matched RNG rolls (5LP 3 at all three heights; 5HP 8 at
  both heights that connect). Same result as the desperation projectile-height sweep.
  The dual values community lists likely come from two REAL mechanisms:
  1. **Defender-posture on-hit tables**: same move, crouching defender takes more
     (Uranus 2LP 2/3 → 3/4, 2HP 5/7 → 7/9; desperations Mercury/Jupiter 48 → 62).
     Prejump counts as crouch; air uses the stand-class value.
  2. **Proximity normals**: Uranus close-range 5HP is a different act (0x45, 9/12)
     than far 5HP (0x43, 8/10).
- The 4 melee apply sites are per-(attack, defender-posture) on-hit table variants, not
  a single shared path: Uranus standing normals apply at the $C0:C09C site, her
  crouching normals vs a STANDING defender at $C0:C16F, crouching-vs-crouching back at
  $C0:C09C; Moon's and Jupiter's 5HP apply at $C0:C16F. (Matches the CDD5/CE15…D015
  table-variant family.)
- Attack acts visibly displace hurtboxes: several whiff-punish geometries failed because
  the whiffing character's act pulled their hurtbox out of an attack's reach that hits
  them when idle. Damage measurement rigs must log the defender act at impact.

### 6.y Universal & reaction act taxonomy (T4, 2026-07-19)

Universal acts (all characters; 0x2B+ is per-character move space):

| Act | Meaning | Notes |
|---|---|---|
| 00/01/02/03/04 | idle / walk fwd / walk back / crouch / crouch-transition | |
| 05 | prejump | 5f, throw-vulnerable, backdash/special-cancelable |
| 06 / 08 | jump rise-fall / back-jump | |
| 09 | landing & dash-skid | 5f |
| 0C / 0E | standing blockstun pair | **pairs alternate on consecutive hits so the anim re-triggers**; 0C doubles as the proximity-guard pose (passive, not a lock) |
| 0D / 0F | crouching blockstun pair | crouch-guard pose has its own (lower) hurtbox |
| 11 / 13 | hitstun pair (stand AND low-altitude air) | alternate like the block pair |
| 12 | light-hit stun variant | seen from jabs |
| 15 | crouch hitstun | |
| 16 | hit-during-forward-dash | observed on Uranus's Shadow Dash |
| 19 | knockdown spin (slide/sweep hits) | |
| 1A / 1B | launch/KD reactions (higher hit levels) | 1B seen from class-0x10 hits |
| 1C / 1D / 1E / 1F / 20 | held / thrown / down / dead / wakeup | the grab-KO chain |
| **21** | **DANGER entry** | fires when HP drops to **≤ 0x18** (exact boundary verified: 0x18 yes, 0x19 no) — the same threshold that gates desperations |
| 26 | backdash | invuln per character (14/17/20/26f...) |
| 2A | post-special recovery tail | not cancelable; counter-hit window ends here |

**Reaction dispatch — FULLY ENUMERATED (2026-07-19):** the table at `$C1:0E85` is
three posture sub-tables (STAND / CROUCH / AIR+DASH) × 13 hit-levels of handler
pointers. Every handler follows one template: set pushback velocity (+0x3A) for
ground stuns or X/Y launch velocities (+0x32/+0x34) for knockdowns, set the hit-type
flag +0x46 (0x20 ground / 0xA0 launch-air), then stage the reaction act via $10A9
(which also runs the pair alternation). Level→act maps:
- STAND: block-heavy 0x0E (vel 0x29) / block-light 0x0E (vel 0x24) / 0x10 / 0x12 /
  0x11 / 0x13 / ... / launches 0x19, 0x1B, 0x1A / two dizzy-style handlers (+0x78
  timers 0x19/0x21 frames).
- CROUCH: 0x0F blocks, then 0x14, 0x15 stuns, shared launch tail.
- AIR/DASH: mostly 0x1B launches and **0x16** (×4 slots) — why dash hits show 0x16:
  the dash counts as air posture.
Acts 0x10 and 0x14 exist in the tables but were never observed live (rare levels).
Reaction staging at $C1:0E30-0E51 holds the 16-bit +0x47/+0x48 clear (first-hit-
defense depletion).

**Danger check**: `$C1:0AA9` = `lda #$18 / cmp $49,X / bmi skip / lda #$21 /
jmp $0224` — called on neutral-entry; the exact ≤0x18 boundary in five instructions.
**Shared ochame roll**: `$C1:0AB9` — `lda $90 / and #$0F` → threshold table `$0AF5`
vs the +0x75 stat → on misfire sets flag 0xA0 and stages act **0x27** (the misfire
trip — the RNG's actual consumer in combat code). Act 0x0A = turn-around (observed).

## 7. Movement and input recognizers

Motion inputs are recognized by per-object state machines in the `+0x5B–0x68` timer/state
pairs. The **66 forward dash** ("Shadow Dash", act 0x60) uses `$105D`(timer)/`$105E`(state):
1→2 on forward, →3 on release, dash commits on a second forward. **+0x5D doubles as the dash
frame counter (1..14)** during the dash. From a fresh savestate the recognizer needs a couple
frames to settle — tap fwd/release/fwd around frames 58/60, not immediately after load, or you
get a walk.

The reversal-dash bug (patch 2) was here: Uranus's forward-dash handler `$C1:88C8` omitted the
`stz $46,X` step-0 init every other volitional handler has, so a reversal dash out of knockdown
carried the 0xA0 untargetable status for its whole 14 frames.

### 7.x Move initiation — the START ROUTES each act offers (measured 2026-08-10)

> **Drawn:** [how an act is chosen](https://claude.ai/code/artifact/fc6c32ec-753b-459d-bbfe-f69601d766fc) — this section as seven figures, one
> per route. Private artifact, not generated from the repo (see `README.md`).

**There is no global "what can I do now" logic.** Every act handler ends by offering
a fixed, ordered set of START ROUTES — what may be begun from that state — and each
route is a *starter* routine called with a table address in `Y`. This is the mechanism behind the whole
move taxonomy — what makes a normal a normal, a command normal a command normal,
and a special a special is *which of these lists it is in and which acts pass that
list*. Uranus's stand-guard handler offers all three:

```
jsr $0459    Y = $7AF5    normals, for THIS stance
jsr $0958    Y = $7B25    special-start table            (see sms_specials.md)
jsr $055A    Y = $7B39    close throws                   (§8)
```

plus, for the characters that have them, a per-character movement call (below).
Order matters: **normals are read before specials, and both commit through the act
setter `$C1:0224`**, so a special input landing on the same frame overwrites the
normal that was just set.

**Normals — `$C1:0459`, four 3-byte records `[distance threshold, far act, close act]`.**
Selected by the fresh attack-button press in the high nibble of `+0x50`, falling
back to `+0x52`. Button bits, measured on the running game: **Y `0x10`, B `0x20`,
X `0x40`, A `0x80`** — so with the standard map (Y=LP, X=HP, B=LK, A=HK) the record
order is **LP, LK, HP, HK**, *not* LP/HP/LK/HK. Close/far comes from `$C1:0439`,
which returns `abs(opponent +0x21 − self +0x21)`: threshold ≥ distance picks the
close act, otherwise the far act; a threshold of `255` means the move has no
proximity variant.

⚠ **The "command" in a command normal is the STANCE, not a direction+button combo.**
There is no table keyed by direction. Holding down has already moved you into the
crouch act, and *that act nominates a different normals table* — which is the whole
of what makes 2HK a distinct move. Uranus has four:

| table | nominated by | LP | LK | HP | HK |
|---|---|---|---|---|---|
| `$C1:7AF5` standing | idle, walk fwd/back, land, stand-guard, danger | thr 36: far `0x40` / close `0x41` | `0x47` | thr 36: far `0x43` / close `0x45` | `0x49` |
| `$C1:7B01` crouching | crouch, stand-up, crouch-guard | `0x53` | `0x57` | `0x55` | `0x59` |
| `$C1:7B0D` neutral jump | jump up | `0x4B` | `0x4C` | `0x4D` | `0x4E` |
| `$C1:7B19` directional jump | jump fwd, jump back | `0x4F` | `0x50` | `0x51` | `0x52` |

Two things fall out that are easy to miss: **neutral and directional jumps get
DIFFERENT tables**, so j.LP in place and j.LP moving are genuinely different moves;
and the crouch row independently reproduces the long-published Uranus IDs
(2LP `0x53`, 2HP `0x55`, 2HK `0x59` the sliding sweep).

**Command movement is per-character CODE, not data** — generic helpers in the shared
low-`$C1` region, called only from the proc blocks that own them:

| routine | callers | what it gates on |
|---|---|---|
| `$C1:11E2` double jump | 3, all ChibiMoon's jump acts | UP bit in `+0x50`, and an **apex window** `|+0x32| < 0x0200` so it cannot fire while rising or falling fast; picks base / base+1 / base+2 by direction vs facing |
| `$C1:0BDD` triangle jump | 2, Mercury's jump fwd/back only — **not** neutral jump | `+0x16` bit6 (wall contact), direction held into the wall, sign of `+0x31`; flips facing `+0x09` |

That per-character-code split is why neither appears in any table, and therefore why
neither is a special: the special-start table is one of the routes, and it is the
only one a blockstun act offers.

**Blockstun offers exactly ONE route** — measured on all nine characters, acts
`0x0E`/`0x0F` call `jsr $0958` and nothing else: no normals table, no throws. That is
the whole of the guard-cancel rule, and it is why *table membership* rather than
anything about the move itself decides what can be guard-cancelled into. Compare
guard-HELD `0x0C`, which offers all three.

#### "Special" is encoded TWICE, and the two could disagree

Two independent things in this engine both mean "special", they are written by
different code in different places, and in the retail data they always coincide:

| | where it is decided | what consumes it |
|---|---|---|
| **startable from guard** | membership in the special-start table (§ above) | the special starter `$C1:0958`, i.e. the guard-cancel rule |
| **strength class** | `+0x44`, written by the ACT HANDLER at its step 0 | the on-hit tables and the damage path (§6; ≥`0x08` = special class) |

Nothing links them. A handler sets its own `+0x44` regardless of which route
started the act — Uranus's 2LP opens `lda #$03 / sta $45,X` … `lda #$00 / sta $44,X`
— and the tables carry no class information at all.

**The consequence is worth stating because it is a property of the design, not an
observation about the retail ROM** (nothing below has been built or tested; it is
what the code permits): moving a move's act out of the special-start table and into
a stance's normals table would make it un-guard-cancellable — and therefore not a
special by the game's own criterion — while leaving `+0x44` untouched, so it would
still hit with special-class damage. It would be a normal by input and by guard
rules, and a special by damage. Two further asymmetries fall out of the same split:

* **What follows the act** is everything the handler owns — animation, boxes,
  damage `+0x45`, `+0x44`.
* **What follows the table** is only the gating flags, and the normals record has no
  flags field. Ground/air restriction, the desperation gate, and in particular the
  projectile-slot check (flag `0x04` → `$C1:04E8`) would simply cease to apply.

Also note the special-start table is indexed positionally, `(nibble − 2) × 2`, so
removing an entry shifts every later one; and `$C1:0459`'s four records sit at fixed
offsets `+0/+3/+6/+9`, so a stance has exactly four slots and no room for a fifth.

---

## 8. Throw system

Throws are **mash-escaped, not one-press-teched.**

1. **Connect** `$C1:0612`: victim → act 0x1C (HELD), victim +0x46=0xA0, thrower +0x46=0xE0;
   an ~8-frame engine freeze follows.
2. **Hold script interpreter** `$C1:06E5`: runs an 8-byte-per-step script (indexed by thrower
   +0x07). During steps whose **entry byte5 ≠ 0**, the sampler `$C1:07CF` checks the victim's
   fresh attack presses (+0x50 & 0xF0, 30 Hz latch) and increments the **thrower's mash counter
   +0x56**.
3. **Toss decision** `$C1:0823`: `+0x56 ≥ 2` → victim act 0x23 (tech, HALF damage); else act
   0x1D (thrown, full). The threshold (2) and the halving are global; **the only per-throw
   variable is which hold-steps sample** (their byte5). Venus's 6HP sampled only 6 frames vs
   Jupiter's standard 15 — patch 8 flipped one script byte to make it 13.

Per-character throw scripts (call sites `ldy #imm / jsr $06E5` in bank $C1): Moon $2884/$28AC,
Mercury $38EE/…, Mars $4925/…, Jupiter $5A07/…, Venus $6C53, Uranus $7B59/…, Neptune $8F19/….

### Which throw comes out, and which way it goes (measured 2026-08-05)

Both questions are answered by **data**, which is why a character can ship with them
wrong (Saturn did — see `docs/project/saturn/BUILDS.md` 0.16.0).

**Selection — `$C1:055A`.** A character's proc calls it with `Y` = the address of a
**4 × 8-byte table, one record per attack button**. The routine derives a button index
from the fresh-press bits in **+0x50** (`0x10`→0, `0x20`→1, `0x40`→2, `0x80`→3; those
bits are assembled at `$C1:02CC` from `$6A`/`$6B`), reads the record at `Y + index*8`,
and the record's **last byte is the thrower's act**. `$FF` in the first word = this
button has no throw. Record word 0's low two bits gate on the opponent's state
(`$0016,y & 0x80`): `%11` = no condition, `%01` = required set, `%00` = required clear.
So **index 2 is HP and index 3 is HK** — swapping two records moves each throw, with
its own range/gating fields, to the other button.

**Direction — `$C1:07E5`.** The toss reads a 5-byte record from `Y`
(`b1-b2` = X velocity, `b3-b4` = Y velocity, both 8.8), **negates X when the thrower
faces left** (`lda $09,x` → `eor #$FFFF / inc a`), and stores it as the victim's
velocity at `+0x30`; `$C1:01B0` then integrates `+0x30/+0x36/+0x38` into the position
at `+0x20`. So the record always holds the **forward** velocity and the sign of that
one word is the whole "forward throw vs back throw" question. Uranus's HP throw record
(`$C1:7B81`) is `FF 80 01 80 FA 18` → X `+$0180`, Y `−$0580` (the word `$FA80`),
damage 24.

Note the direction is chosen *before* this, at `$C1:061B`: `lda $50,x / and #$01 /
eor #$01 / sta $09,x` — the thrower's facing is set from the direction held at contact,
and everything downstream (including the negation above) follows facing. A throw whose
record holds a negative X therefore comes out **backwards on 6 and forwards on 4**.

---

## 9. Projectile system

Each player has **one** projectile slot (`$1100` P1's, `$1180` P2's) sharing the fighter struct
layout. A projectile's **+0x00 is its object type id (10–27)**, which selects its box table
(§5) — *not* the owner's char table. It occupies the same slot for its whole life; there is no
second slot for a "wave," so a projectile that morphs does so in place (its actionID changes).

**Case study — Neptune Deep Submerge (obj 0x18, hit table `$8A:FD51`):** the fireball arcs
down-forward (act 0x01) with attack boxes cycling indices 1→2→3→4 (small boxes that follow the
ball), then reaches head level and enters a fade-out phase (act 0x02) where the attack box goes
to index 0 (it has already threatened; it's dissipating). The box table also holds tall
head-level columns (entries 6–8) that appear only as (vestigial) hurtbox values, never as the
attack. Patch 9 fixed the *descent* boxes: they were authored at y_off −27/−60 (stuck at head
level) while the ball fell below them; patch 9 set entries 1–4 to y_off −11 so the box tracks
the ball. The residual "blink" reported afterward was **not** a ROM issue — it was the hitbox
viewer drawing the projectile's phantom hurtbox from the roster-only table (§5).

---

## 10. Practice mode (game_mode 4/5) — how the native trainer works

Entered from the title menu (down, right → Practice; `$008D` becomes 4 already at char
select). Everything here was probe-verified on this game in the patch-11 session
(`tools/probe_p11_*.lua`; flat facts in `annotations.md` "patch 11 RE").

**The damage switch is the whole difference between modes 4 and 5.** In mode 4 a hit
resolves *completely* — connect latch (+0x43), hitstun act, hitstop, pushback — and only
the HP subtraction is skipped. Poking `$008D = 5` mid-match turns HP loss on; 4 turns it
back off. Nothing else observable changes. Two corollaries:
- The **attract demo is a real match running at mode 5** — any patch gating on
  "mode ∈ {4,5}" will also fire during the demo unless it distinguishes (patch 11 accepts
  5 only when its own flag says *it* set the value).
- Desperation moves (HP ≤ 0x18 gated) are additionally skipped when `$8D == 4` (the cancel
  table's bit-8 check is bypassed), and can never trigger anyway since HP never drops.

**No HUD, no timer, no round flow.** The HUD producer `$C0:D5E8` never executes in Practice
(mode 4 *or* 5): no bars, no timer decrement (`$0802-04` stay 0), no displayed-HP animation.
And a KO in mode 5 goes knockdown → down (0x1E) → KO pose (0x1F ≈ 66f after death) and then
**nothing** — no round-end flow ever fires; the match keeps running with a body on the floor.
The KO decision is **latched at damage-apply**: refilling struct HP (or `$0800/1`) during the
knockdown does *not* prevent 0x1F. The proven way to cancel a death (patch 11's REFILL):
refill HP during the KD **and force the engine's own standup act** (+0x01/+0x04 = 0x20,
+0x02 = 1, +0x06/07 = 0) when the body reaches act 0x1E — recovery is then fully normal.

**BG3 is the movelist layer.** In Practice the whole BG3 tilemap holds the pre-staged
command list for P1's character, invisible because TM=0x13. **Start** flips the movelist on
(`$01FA` 0x80 → 0xE4) and — key fact — **restages the entire layer on every press**, so a
patch may paint BG3 freely mid-match and the native movelist repairs itself. **Select exits
the match** (~60f fade, `$0070` → 0). The BG3 CHR still contains the resident HUD digits and
the free glyph window 0xC7–0xDF; palettes are identical to VS.

**Screen-state bytes for gating:** in-match = `$0070 == 4` (also 4 in VS — combine with
`$008D`); actually-running = `$01FA == 0x80` (movelist = 0xE4).

**The input-override surface** (how the in-ROM dummy works, and the ROM-side equivalent of
the Lua trainer's `setInput`): joy_read stores fresh held words at `$5C-$5F` *before* it
derives press edges. Code hooked at `$80:8373` that rewrites P2's `$5E/$5F` gets everything
downstream for free — edges next frame, the 30 Hz +0x50 press latch, motion recognizers
(an injected back/neutral/back fires the 44 backdash), blocking, throw-tech mash counting.
Holding down-back = `$5F = 0x04|back-bit` where back is 0x01 (Right) if P2.x ≥ P1.x else
0x02. Zeroing P1's `$5C/$5D` at the same point "eats" the pad invisibly (used by patch 11's
menu; note the release-edge leak when you stop eating — hold the eat 2 extra frames).

Patch 11 (`tools/mkpatch11.py`, `docs/project/trainingplus.md`) builds the full in-ROM trainer on
these facts: L+R menu, dummy layers, native damage switch, no-KO refill, WMDATA recording
ring, input/advantage displays — hooks at `$80:8373` + `$80:D574`, state in `$7F:F000+`.

---

## 11. Modding playbook

**Append-a-bank + hook pattern** (patches 3, 4, 10): grow the ROM to the next 64K boundary,
put your code/data there (SNES bank = `0xC0 + (fileoffset>>16)`), and repoint an existing call
site or overwrite a routine's entry with a `JML`/`JSL` into your stub. The builder computes the
bank from the input ROM length so patches **stack** (each appends past the previous). Always:
- assert the vanilla bytes at every hook site before writing (catches a wrong/So-stacked input);
- keep edits **byte-disjoint** from other patches (see the edit-region map in patch_notes.md);
- recompute the SNES checksum (`_fix_checksum`, identical across mkpatch3/4/9/10).

**JML trampoline into a routine you don't own** (patch 10 hooks the HUD producer/uploader):
overwrite the routine's first bytes with `JML yourstub`; your stub runs your code, then
replicates the displaced instructions and `JML`s back to the instruction after the overwrite.
No stack frame is added, so the routine's own `RTS/RTL` still returns to its real caller.
Two refinements from patch 11:
- **Hook mid-routine, not just at entries** — patch 11 hooks `$80:8373` (joy_read tail) and
  `$80:D574` (*inside* the uploader, right after patch 10's continuation point), so both
  patches coexist with **no chaining and no order sensitivity**: each asserts only its own
  vanilla bytes, which the other never touches.
- **Displaced instructions that can't be reassembled** (direct-page ops, or a branch): splice
  the original bytes raw after the assembled stub (dp case), or replay branch-aware — preserve
  the caller's flags with `php…plp`, then re-execute the displaced `beq/sta` with two JML
  exits, one per branch arm (patch 11's UPL2 hook does exactly this for `beq $D596/sta $2116`).

**Free resources inventory** (for a new patch):
- *ROM code*: the verified-unused zero region at end of bank $C1, `0x1BE0E–0x1BE47` (patches
  1/2 use `0x1BE20–31`, patch 6 uses `0x1BE85+`) — only a few dozen bytes; anything bigger goes
  in an appended bank.
- *WRAM scratch*: `$0816–$08FF` and `$0900–$09FF` are free **in VS matches** (patch 10 uses
  them) but **NOT in Practice** (the native mode touches the whole range — re-probe freedom
  in every mode your patch is active in).
- *Bank `$7F`*: `$7F:6000+` untouched in steady-state play (loads use `$7F:0000-5FFF`); the
  WMDATA port `$2180-83` is game-free (pointer-addressed `$7F` access without indexing).
  Patch 11's state (`$7F:F000+`) and recording ring (`$7F:E000+`) live here, reached with
  long addressing (`lda.l/sta.l/cmp.l`).
- *VRAM CHR (BG3, 2bpp)*: free glyph slots `0xC7–0xDF` (25 tiles), zero across matchups.
  Patches 10 and 11 both upload fonts there — same tile slots, different colors (3 vs 1
  white), safe because their visibility domains never overlap (VS vs Practice).
- *BG3 tilemap in Practice*: the whole map is paintable (it's the TM-off movelist layer;
  the movelist restages itself on Start — see §10).

**The mini-assembler** `tools/asm65816.py` handles the hand-written stubs. It tracks the M/X
processor flags through `rep/sep` and sizes immediates accordingly — the load-bearing subtlety
is that `ldx #$00` must emit a **16-bit** immediate when X is 16-bit (a hex-length heuristic
gets this wrong and silently corrupts everything after). It only has 8-bit relative branches,
so for a far conditional target write `bne skip; jmp far; skip:`. Patch 11 added `eor`
(imm/abs) and **long addressing** `lda_l/sta_l/cmp_l` (24-bit operands, DBR-independent —
how the `$7F` state is reached with no indexed modes).

**⚠ The tracker-vs-runtime width trap** (two real crashes in patch 11): the assembler's M/X
tracking is *linear through the source*, but control flow isn't — a label whose fall-through
predecessor ended in `rep #$20` is *emitted* 16-bit even if the *jump* into it arrives in
8-bit mode (or vice versa), and the CPU then decodes garbage. Rule: at **every label that can
be reached by a jump/branch, re-assert the width explicitly** (`sep #$20`/`rep #$20` as the
first instruction) unless every path provably matches. The `rep`-before-branch idiom is safe
(`rep`/`sep` preserve Z and C, so `cmp` in 8-bit, then `rep #$20`, then `beq` works).

**Gotchas that cost real time** (also in HANDOFF.md §5): `emu.setInput` port is the **3rd** arg;
savestate load/save only inside an exec callback on `$80:8353`; the GUI refuses a savestate
whose embedded ROM tag ≠ the open ROM (headless is permissive); `takeScreenshot` does **not**
composite the ScriptHud overlay surface (console-surface draws do show); button map Y=LP X=HP
B=LK A=HK.

---

## 12. Frame-data semantics (as implemented, oracle-validated)

- **Startup S** = frames from an attack's step-0 frame up to but *not including* the first
  active frame (this game's Dustloop convention; e.g. Uranus 2LP S4). Active **follows the
  hitbox** (index ≠ 0 with a real box, step ≥ 1) and can span an act boundary — the 2LP box
  persists one frame into its recovery act and can still hit there. Recovery = post-active to
  the first neutral-act frame. Counts exclude hitstop frames.
- **Advantage** = defender-neutral-frame − attacker-neutral-frame at interaction settlement
  (both actionable, no live projectile); `+` = attacker first. A secondary "cancel advantage"
  uses the attacker's first *cancellable-recovery* frame — that's the number that governs links
  in this game (the Uranus infinite lives there).
- **Event labels** (all computable from act transitions + HP deltas): GC = attack act with
  previous act in blockstun (0x0E/0F); REVERSAL = attack ≤2f after leaving hard constraint;
  PUNISH = hit while the defender is in its own move's recovery (move-phase active-seen,
  hitbox gone); TECH = act→0x23. No counter-hit system exists in this engine (a "COUNTER"
  label would be informational only). A MEATY label (hit ≤2f after the defender left
  constraint) shipped through v0.20 and was removed 2026-07-20 on player feedback — the
  detection rule stays valid engine knowledge.

The reference implementations are `tools/training/framedata.lua`, `combo.lua`, `labels.lua`;
patch 10 transliterates the same logic into 65816 and is validated *against* the Lua as oracle.

---

## 13. Cross-reference — subsystem → patches → tools

| Subsystem | Key addresses | Patches | Probe/analysis tools |
|---|---|---|---|
| HUD render | `$C0:D5E8`, `$C0:D56F`, staging `$0806-$0815` | 10 | `probe_hudre/hudnmi/upl/ctx/vram/ppu.lua` |
| Box tables | `$8A:C1F1/C229/C23D` | 7, 9 | `extract_sms_hitboxes.py`, `sms_all_boxes.json` |
| Hit resolution | `$C0:BFC0`, `$C0:CDD5+` | 1 (meaty) | `demo_link.lua`, `react_test.lua` |
| Dash / recognizers | `$C1:88C8`, `$105D/E`, +0x5D | 2, 5, 6 | `trace.lua` |
| Throw / tech | `$C1:0612/06E5/07CF/0823`, +0x56 | 8 | `techsweep.lua`, `techfind.lua` |
| Projectiles | slots `$1100/1180`, `$8A:FD51` | 9 | `probe_ds*.lua`, `extract_proj_boxes.py` |
| Title text | `$C3:B81F` | 3, 4 | `texttiles.py`, `mockup.lua` |
| In-ROM combo/labels | hooks above + WRAM `$0900+`, CHR 0xC7 | 10 | `mkpatch10.py`, `hudfont.py`, `perf_patch10.lua`, `test_labels.lua` |
| Practice mode / in-ROM trainer | `$80:8373`, `$80:D574`, `$008D` 4↔5, `$0070`, `$01FA`, `$7F:E000/F000`, TM `$212C` | 11 | `mkpatch11.py`, `probe_p11_*.lua`, `test_p11_tier1.lua`, `perf_patch11.lua` |
| Taunt / ochame misfire | `$C1:0B49`, RNG `$0090`, roll `$C1:0AB9`, act `0x27` | 12 | `mkpatch12.py`, `test_p12_taunt.lua` |
| Damage apply + Guts | 8 apply sites in `$C0` (§6), throw sites `$C1:082F/084D`, matrix `$C0:D081`, state `$7F:F800+` | 13, 14 | `mkpatch13/14.py`, `test_p13_guts.lua`, `probe_p13_timeout.lua`, `docs/game/sms_damage_system.md` |
| Front-end menus / asset pipeline | job table `$C3:BE08` (`[vram16][len16][src24][dest24]`), uploader `$C0:92D2`, decompress `$80:927D`, clusters `$C3:A4DD`/`AF8A`/`9CF2`, bank-`$DF` screen engine `$DF:83CE`, config dispatcher `$C3:BB60` | 15, 16, 17, 18 | `mkpatch15/16/17/18.py`, `menufont.py`, `probe_p16_*.lua`, `probe_acs_select.lua`, `docs/game/menu_system.md` |
| A.C.S. stats | `$1C02`, menu state `$8A`, wheel cluster `$C3:9CF2` | 18 (removal) | `docs/game/sms_acs_system.md`, `probe_acs_select.lua` |

**Builders** `tools/mkpatch{,2..18}.py` (all take `(src,out)` positionals and stack on any
input; every stacked step needs `--stacked` since 2026-07-30). The 100-series (Saturn) is
built by `tools/saturn/` instead.
**Frame-data engine + training mode** `tools/training/` (Lua; also the patch oracles).
**What to test against:** the two release builds, `release/Rev.S-02.bps` → ROM `41d93a53…`
and `release/Rev.SS-02.bps` → `b96f3fe8…` (one recipe, `tools/build_rev.sh both`). The
newest all-patches *development* ROM is `build/SailorMoonS_FrenchName_v0.22_ALLPATCHES.sfc`
(SHA-1 `e6b999b5…`, BPS `build/sms_allpatches_v0.22.bps`); the v1.x ROMs named in older
notes were pruned in 2026-07-19.
