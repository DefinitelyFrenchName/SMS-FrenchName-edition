---
name: sms-romhacking
description: Hard rules and traps specific to hacking Bishoujo Senshi Sailor Moon S - Jougai Rantou (SFC). Load before measuring, patching, or probing this game - engine laws (nine-wide tables, global on-hit tables, data-driven procs), mode/testing caveats, the menu/text laws, WRAM free-space rules, and this repo's harness conventions. Sits on the romhacking-methodology and snes-romhacking skills.
---

# SMS (Jougai Rantou!?) romhacking

Agent-facing rules, IDs `[SMS-NN]`; the human rendition with incidents is
`docs/game/sms_hacking_playbook.md` (checked by `tools/checkskills.py` — the two files
must carry identical ID sets). General method: `romhacking-methodology` (`[RH-NN]`);
platform: `snes-romhacking` (`[SNES-NN]`). ROM addresses are deliberately NOT quoted
here — the checked claims live in `docs/game/` (start at `sms_quickref.md`); WRAM
addresses are quoted where they are the stable interface.

## 1. Ground truth

- [SMS-1] Clean ROM: SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`, HiROM+FastROM,
  headerless, 2.5 MB. Roster charID 1-9 (1 Moon … 6 Uranus … 9 Chibi Moon). Saturn
  (id 10) has NO data in the clean ROM — never search for her there; she exists only in
  this project's Rev. SS builds, ported from Super S (see the `supers-porting` skill).

## 2. Engine laws

- [SMS-2] The engine is data-driven: a character can ship with wrong data and the
  engine will faithfully do the wrong thing. Most features are data edits, not hooks.
- [SMS-3] **THE NINE-WIDE-TABLE LAW**: every per-character table is sized to exactly
  nine and immediately followed by live data. Adding a row means relocating the table
  and repointing EVERY reader. Symptom depends on the lookup key: an out-of-range id
  reads garbage past the end; a stand-in character's id reads a plausible-but-WRONG
  row — so the fix is a redirect, not an out-of-range repair. Known bite list:
  throw poses, win nameplates, movelist pointers, round-won badge, in-match nameplate,
  box pointer tables, audio banks, BRR directory (census: `docs/project/saturn/memory_and_shell.md`).
- [SMS-4] On-hit tables are GLOBAL, strength-class indexed — a hitstun/damage edit
  there changes every character's move of that class. Never patch them for one
  character without proving per-character indexing first.
- [SMS-5] Hit resolution is not a stage of the frame loop: the ATTACKER's own proc
  resolves the hit, and the victim's reaction lands at the top of the next pass — one
  frame later.
- [SMS-6] The step-0 init is a per-handler CONTRACT enforced by nothing (~87
  hand-written handlers per character) — an omitted init survives and ships (this IS
  patch 2's bug).
- [SMS-7] Act tables are 107-122 entries per character, NOT 128 — 128 is the Super S
  figure.
- [SMS-8] The engine processes attacks starting the frame AFTER action start, and
  inputs latch at 30 Hz — mind both when counting frames ([SNES-40]).
- [SMS-9] Death is HP UNDERFLOW, not zero: HP 0 is survivable and chip damage never
  kills. Damage has no RNG (apparent jitter is the defender's first-hit-defense byte).
  Command ids are computed from POSITION in the table, not stored.
- [SMS-10] There are MULTIPLE proc dispatchers (players, projectile pool, effect pool,
  plus indirect dispatch sites in other banks) — hooking one is not hooking dispatch.
  Saturn builds additionally carry a full copy of the proc bank ([SSP-12]).
- [SMS-11] Projectiles live in their own slots and pick box tables by their OWN object
  id, not the owner's charID; only the HIT pointer table is widened for projectiles —
  indexing hurt/collision tables with a projectile id runs off the end into the
  neighbouring table.

## 3. Mode and testing caveats

- [SMS-12] `$7E:008D` mode byte: 0 = story, 1 = 2P VS, 2 = 1P-vs-COM, 4/5 = training.
  The vendor Lua's comment (0=VS, 1=story) is WRONG and shipped two field bugs.
- [SMS-13] Practice mode draws NO HUD and no nameplates, and the HUD producer never
  runs there — a hook on it is dead in the mode people train in. HUD captures need
  1P-vs-COM or 2P VS.
- [SMS-14] In 1P-vs-COM, P1's pad confirms BOTH characters — a harness mashing P2
  stalls at character select forever.
- [SMS-15] A live round flag does not mean the players can act: fighters sit in the
  entrance act while "GO!" is up and pads do nothing. Menu screens: every column has
  its OWN row cursor (P1/P2), so one handler firing proves nothing about the other
  pad; and mashing a direction on a two-value row lands by PARITY — an even press
  count is indistinguishable from an inert row.
- [SMS-16] Round transitions re-init both player structs on the same frame — per-round
  mechanics must re-apply or track state outside the structs. Mid-match savestates
  carry hit history: first-hit-defense and similar censuses need boot-fresh rounds.
- [SMS-17] OBJ palette rows are DYNAMIC (reloaded per effect): a palette census needs a
  REAL match that lands hits — a practice-mode sample misses effect rows entirely, and
  snapshot-vs-snapshot at two instants compares nothing.
- [SMS-18] Win-screen reachability (headless): vs-COM has no round clock, the COM
  guards jabs indefinitely, and throw damage is chip-class (chip never kills — a throw
  at 1 HP strands the victim at 0 forever). Kill with strikes; pin HP via the
  per-A.C.S. max, never a constant.
- [SMS-19] `$7E:1B1E` names the CHARACTER, not the player — identify the player from
  the per-player writers of it, or a ported/renamed character breaks the logic.
- [SMS-20] The win-nameplate font is MATCHUP-LOADED, not a resident A-Z — which glyphs
  exist depends on the two names on screen.

## 4. Menu / text laws (patch-16 lineage; mechanisms in docs/game/menu_system.md)

- [SMS-21] **LAW 1**: a screen transition can clear ALL 64 KB of VRAM and the
  destination reloads only its OWN asset list — an asset must be in EVERY target
  screen's loader cluster, not merely "in VRAM" ([SNES-16/17]).
- [SMS-22] **LAW 2**: blank ≠ unreferenced — three separate screens reference
  blank-looking tiles through another BG's CHR base ([SNES-18]).
- [SMS-23] **LAW 3**: DMA is invisible to CPU write callbacks ([SNES-14]) — every menu
  freedom/arrival claim needs snapshots and a watch together.
- [SMS-24] Runtime records OVERDRAW baked map text: option VALUES (and anything
  highlight-dependent) cannot be translated in the tilemap — find the runtime writer's
  records.
- [SMS-25] Asset records are `[vram16][len16][src24][dest24]` — the upload LENGTH sits
  2 bytes BEFORE the source pointer. Reach records by walking BOTH pointer tables
  ([RH-29]), and remember an asset can be named by MORE THAN ONE record — repointing
  the one you found leaves the other live.
- [SMS-26] Menu glyphs are 2x2 tiles in a 16-tile-wide sheet, and the kana block loads
  at a DIFFERENT base per screen — read the generated code→glyph table instead of
  re-deriving from captures; decoding a screen's tilemap back to readable strings IS
  the validation.
- [SMS-27] The stock codec-1 encoder is WEAKER than the original's: an edited
  compressed block must be relocated and repointed, never written back in place —
  unless re-encoded with the optimal-parse encoder (`encode_lz`). The stock `encode`
  stays untouched: recorded patch hashes call it ([RH-49]).
- [SMS-28] The bank-`$DF` screen engine (Win/Tournament/bracket) executes from the
  `$9F` mirror — stubs at `$8000+` only, DB = bank − `$40` ([SNES-3/4]); its script
  entry stride DIFFERS BY CODEC (8 vs 7 bytes) — a fixed-stride walk desyncs after the
  first mixed entry and prints plausible garbage.
- [SMS-29] Stage-name records: NO terminator, centred by zero padding ([RH-28]),
  12-glyph ceiling regardless of apparent free space. The menu bound at `$1F59` is an
  INCLUSIVE max in word units, not a count; a selected stage's name is QUEUED to VRAM,
  not drawn on the spot — let transfers settle (~40 frames) before capturing.
- [SMS-30] Verify glyph delivery by dumping ON the font transfer with the POKE positive
  control (0/256 bytes arrive clean, 256/256 patched) — a final-screen dump reads
  identical on clean and patched ROMs, and without the control a diff proves nothing.
- [SMS-31] Text may be on BG3 (2bpp, own CHR base, needs the priority bit in the
  attribute) — check WHICH LAYER a surface is on before aiming any glyph work
  ([SNES-24]).

## 5. WRAM and free space

- [SMS-32] Boot copy loops spray junk through `$7F` — any flag parked there must be
  MAGIC-VALUED (e.g. `$A5`), so corruption can only ever cancel a selection, never
  invent one.
- [SMS-33] `$7E:1F60+` is menu-engine state, and menu code runs BETWEEN character
  select and round load — WRAM freedom claims need a watch across the FULL session
  (boot → title → select → config → match → KO → win), not one mode ([RH-31]).

## 6. Repo harness conventions

- [SMS-34] Every Lua tool bootstraps `sms_env.lua`: flat `tools/` scripts with
  `/sms_env.lua`, `tools/saturn/` scripts with `/../sms_env.lua`. The wrong path fails
  to load with NO error and no output — indistinguishable from the emulator ignoring
  the script.
- [SMS-35] NEVER hand-edit the regression suite's SIGS block — regenerate with
  `mksigs.py --write` ([RH-53]); a hand-pinned byte silently skipped eleven tests.
- [SMS-36] Every chained builder step requires `--stacked`; ROMs resolve via
  `smspaths.py` (`$SMS_ROM_DIR` → `roms/` → `../roms/`) and are never tracked.
- [SMS-37] Savestates are tracked (force-added, deliberately); screenshots and any game
  imagery NEVER are — `git add -f` is not an escape hatch. Two sessions must not run
  emulator tests concurrently (shared scratch cfg files drive the same runner).
- [SMS-38] Button map, empirically: Y=LP, X=HP, B=LK, A=HK — the vendor Lua's comment
  is wrong.

## Pre-flight checklist

Touching a per-character table: nine-wide? Every reader repointed? Tripwire on the read
count? ([SMS-3], [RH-42])
Touching hit data: is the table global? ([SMS-4])
Testing: right mode byte value? ([SMS-12]) HUD visible in this mode? ([SMS-13]) Boot-
fresh round if hit history matters? ([SMS-16])
Menu text: which BG layer? ([SMS-31]) In the target screen's own loader cluster?
([SMS-21]) Dumped on the transfer with POKE? ([SMS-30])
Claiming WRAM: magic-valued flag? ([SMS-32]) Full-session watch? ([SMS-33])
