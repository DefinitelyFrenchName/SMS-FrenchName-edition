# SMS hacking playbook — the rules this game taught us

Game: **Bishoujo Senshi Sailor Moon S: Jougai Rantou!?** (SFC, Japan).
Clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless,
file offset = SNES address & 0x3FFFFF).

This file is METHODOLOGY, not data: the game-specific rules and traps this project paid
for, each with the incident that taught it. It is the human rendition of the agent skill
`.claude/skills/sms-romhacking/SKILL.md` — the two carry identical rule-ID sets
(`[SMS-NN]`), enforced by `tools/checkskills.py`. Deliberately, this file quotes no ROM
addresses: every address-level claim lives in the checked reference docs
(`sms_quickref.md`, `sms_engine_internals.md`, `sms_data_architecture.md`,
`menu_system.md`, `annotations.md`), which `tools/checkdocs.py` re-derives from the
cartridge. Where a rule names a mechanism, the pointer beside it is the authority.
General method and SNES-platform rules referenced as `[RH-NN]` / `[SNES-NN]` live in the
user-level `romhacking-methodology` and `snes-romhacking` skills (same double-rendition
scheme); the donor-port layer is `docs/project/saturn/porting_lessons.md` (`[SSP-NN]`).

## 1. Ground truth

**[SMS-1]** The clean Japanese ROM is the source of truth: SHA-1 above, 2.5 MB (the
3 MB figure that once circulated is the *patched* size). Roster charID runs 1-9;
**Saturn (id 10) has no data in the clean ROM** — decades of community digging found
none, and a pre-2026 extractor that "found" her had invented an entry from
projectile-table bytes. The playable Saturn is data this project ADDS from Super S
(Rev. SS builds only). Never search the SMS image for her.

## 2. Engine laws

**[SMS-2]** The engine is data-driven. A character can ship with the wrong data and the
engine will faithfully do the wrong thing — which is why a 17-patch project has so few
hooks, and why two of Saturn's ground throws could sit on each other's buttons for
thirty years in the donor without the engine caring (`sms_engine_internals.md` §8).

**[SMS-3]** **The nine-wide-table law.** Every per-character table is sized to exactly
nine and immediately followed by unrelated live data; adding a row means relocating the
table and repointing every reader (`docs/project/saturn/memory_and_shell.md` carries the
measured census). It has bitten at least five separate times: throw poses, win
nameplates, movelist pointers, the round-won badge, the in-match nameplate. The symptom
depends on the key: an out-of-range id indexes past the end into whatever follows
(garbage, or by luck blank), while a stand-in character's id returns a
plausible-but-wrong row — which is why the correct fix is a *redirect* of the lookup,
not an out-of-range repair. One extra row in the box tables cost a full 64 KB bank copy
plus nine patch sites: not a space problem, a *layout* problem.

**[SMS-4]** The on-hit tables are global and strength-class indexed. An edit "for one
character's jab" there changes every character's move of that class — proven
per-character indexing is the bar before anyone patches hitstun or damage at the table.

**[SMS-5]** Hit resolution is not a stage of the frame loop. The attacker's own proc
resolves the hit (the resolver has ~192 call sites, all in the proc bank), so the
victim's reaction lands at the top of the *next* pass — one frame later. Frame-data
tooling that assumes a resolution stage reads every advantage number off by one
(`sms_data_architecture.md` §10B).

**[SMS-6]** The step-0 init is a per-handler contract enforced by nothing. Each
character has on the order of 87 hand-written handlers; an omitted init simply ships —
the reversal-dash invincibility bug (patch 2) was exactly a missing engine-standard
clear in one handler's step 0.

**[SMS-7]** Act tables are 107-122 entries per character, not 128 — 128 is the Super S
figure the Saturn port uses, and carrying it back into SMS reasoning produced wrong
bounds until re-measured.

**[SMS-8]** Attacks are processed starting the frame *after* action start, and input is
latched at 30 Hz — both matter whenever frames are counted, and both are why every
timing claim in this repo is emulator-verified rather than inferred ([SNES-40]).

**[SMS-9]** Death is HP underflow, not zero: HP 0 is a survivable state and chip damage
never kills (a throw — chip-class — at 1 HP strands the victim lying at 0 forever, a
state normal play cannot produce). Damage has no RNG: the "modifier jitter" that looked
random was the defender's first-hit-defense byte (`sms_damage_system.md`). Command ids
are computed from table *position*, not stored — scripts are character-independent data
aligned by construction.

**[SMS-10]** There are multiple proc dispatchers — players, the projectile pool, the
effect pool, plus indirect dispatch sites in other banks. Hooking "the dispatcher" is
not hooking dispatch; and a Saturn build carries a full copy of the proc bank on top
([SSP-12]), which is where a documented "exactly two read sites" claim went false in the
shipped image ([RH-37]).

**[SMS-11]** Projectiles occupy their own object slots and select box tables by their
*own* object id, not the owner's charID. Only the hit pointer table was widened to cover
projectiles; indexing the hurt/collision tables with a projectile id runs off the end
into the neighbouring table — harmless in play, a flickering phantom box in a viewer
(`sms_data_architecture.md` §5).

## 3. Mode and testing caveats

**[SMS-12]** The mode byte in low WRAM reads 0 = story, 1 = 2P VS, 2 = 1P-vs-COM,
4/5 = training. The vendor training-mode Lua documented it backwards (0=VS, 1=story),
the wrong values were carried into a shipped guard, and two field bugs resulted — a
feature blocked in 2P VS that never touched story. The corrected census was taken with
two independent discriminators per row (`docs/project/saturn/BUILDS.md` 0.14.6).

**[SMS-13]** Practice mode draws no HUD and no nameplates, and the in-match HUD
producer never runs there. A combo counter hooked on that producer is dead in the one
mode people train in — measured, and the reason the training-mode counters are separate
implementations. HUD captures need 1P-vs-COM or 2P VS.

**[SMS-14]** In 1P-vs-COM, P1's pad confirms *both* characters at select — P2's pad is
inert. A harness that mashes P2 stalls at character select and reports "never reached
the screen", which reads exactly like the feature under test being broken ([RH-17]).

**[SMS-15]** A live round flag does not mean the players can act: the fighters sit in
the entrance act while the "GO!" banner is up and pads do nothing — "the character never
jumps" was the entrance, not an input fault. On menus, every column has its own row
cursor per player, so the row handler firing proves nothing about the pad you meant to
test; and a two-value row toggled by mashing lands by *parity* — an even press count is
indistinguishable from an inert row (patch 15's regression test exists because of this).

**[SMS-16]** Round transitions re-initialise both player structs on the same frame, so
any per-round mechanic must re-apply itself or keep state outside the structs (patch
13's round reset covers KO *and* timeout — the timeout half was a found bug). Mid-match
savestates carry hit history: first-hit-defense censuses taken from them were wrong
until re-run on boot-fresh rounds.

**[SMS-17]** OBJ palette rows are dynamic — the engine reloads them per effect. An
early "nothing uses rows 5/6" claim came from a practice-only sample that never landed a
hit; had a ported projectile been parked on the wrong row, hit sparks would have broken.
A palette census needs a real match that lands hits, and comparing snapshots taken at
two instants compares nothing (`docs/project/saturn/PROJECT.md` § OBJ palettes).

**[SMS-18]** Reaching the win screen headless is hard for engine reasons: vs-COM has no
round clock (displays 00, never ticks), the COM guards jabs indefinitely, and chip never
kills ([SMS-9]) so throws cannot finish a round. Kill with strikes, and pin HP through
the per-A.C.S. maximum rather than a constant — stat builds move the cap.

**[SMS-19]** The character-name variable names the CHARACTER, not the player. Both the
select-voice work and the win-card work tripped on this: the player must be identified
from the per-player writers of that variable, or a summoned/renamed character routes the
logic to the wrong side.

**[SMS-20]** The win-screen nameplate font is matchup-loaded, not a resident A-Z — which
letters exist in VRAM depends on the two names currently on screen. A record-only name
fix renders correctly in some matchups and shows gaps in others. (The in-match nameplate
alphabet, by contrast, turned out fully resident — the docs record both.)

## 4. Menu and text laws

The mechanisms are `menu_system.md` (authoritative) and the working log
`docs/project/menu_text.md`; these are the rules they were learned under.

**[SMS-21]** **Law 1: a screen transition can clear all 64 KB of VRAM** (fixed-source
DMA, length 0 = 65536 — [SNES-16]) **and the destination reloads only its own asset
list.** "It was in VRAM a moment ago" proves nothing; glyphs that demonstrably reached
VRAM at main-menu entry were gone by the options screen, whose loader never re-uploads
the font. An asset must be added to *every* target screen's loader cluster.

**[SMS-22]** **Law 2: blank ≠ unreferenced.** Three separate screens reference
blank-looking tiles through another background layer's CHR base — the third instance
surfaced as a field report of stray letters on the story pre-fight portrait screen after
"free" tiles were filled ([SNES-18]).

**[SMS-23]** **Law 3: DMA is invisible to CPU write callbacks** ([SNES-14]). Every menu
freedom or arrival claim in this repo is made with snapshots and a write watch together,
cross-checked — a silent watch beside a dirty snapshot indicts the watch.

**[SMS-24]** Runtime records overdraw baked map text. Option *values* (and anything
that redraws per highlight state) cannot be translated in the tilemap at all — the
runtime writer draws self-describing records over whatever the map held. Find the
writer's records; the tilemap edit only ever wins until the first redraw.

**[SMS-25]** Asset records put the upload length two bytes BEFORE the source pointer.
Read the other way, record N's length pairs with record N+1's source — which is why
three attempts to grow a transfer "changed nothing": the write lengthened an unrelated
upload. The proof of the corrected layout was 27 records matching observed transfers on
all three fields, zero matching under the old reading. Corollaries: reach records by
walking both pointer tables — a flat stride scan silently missed 16 of 74 records
([RH-29]) — and remember an asset can be named by more than one record, so repointing
the one you found leaves the other live.

**[SMS-26]** Menu glyphs are 2×2 tiles in a 16-tile-wide sheet (the obvious
four-consecutive-tiles guess renders every cell as two stacked top halves), and the kana
block loads at a different base per screen — chasing one code across captures finds
gradients, borders and katakana in turn. Read the repo's generated code→glyph table
instead of re-deriving from captures ([RH-34]); decoding a screen's tilemap back to the
strings the game actually shows is itself the validation. And tile codes landing in the
font range does not make a block text: 20 of 21 compressed blocks are graphics whose
"kana" is noise.

**[SMS-27]** The stock codec-1 encoder is weaker than the original's — a re-encoded
block usually *grows*, so an edited block is relocated and repointed, never written back
in place (`menu_system.md` §7). The one exception is the optimal-parse encoder
(`encode_lz`), which beat the vanilla stream and let the HUD-sheet edit stay in place.
The stock `encode` is deliberately untouched: shipped patch hashes call it, and a
recorded hash is a claim about a build ([RH-49]).

**[SMS-28]** The bank-`$DF` screen engine (win, tournament, bracket) executes from its
`$9F` mirror: stubs must sit in the ROM half of the bank and the data bank is offset
([SNES-3/4] — the day lost to an open-bus stub is that guide's flagship incident). Its
script entries are 8 bytes for one codec and 7 for the other — a fixed-stride walk
desyncs after the first mixed entry and prints plausible garbage for everything after
(it did, first try).

**[SMS-29]** Stage-name records have no terminator (the trailing zeros are centring
padding — [RH-28]; misreading this shipped a build that hung the game a second after
stage select) and a hard 12-glyph ceiling whatever the row's free space suggests. The
stage-menu bound is an *inclusive maximum*, not a count — reading it as a length inverts
the whole mechanism. And a selected stage's name is queued to VRAM, not drawn on the
spot: a screenshot on the frame the index lands shows the previous stage's name; let
transfers settle (~40 frames).

**[SMS-30]** Verify glyph delivery by dumping ON the font transfer, with the poke
positive control: stamp a pattern past the vanilla transfer's end, expect 0/256 bytes to
arrive on clean and 256/256 on patched. A final-screen dump reads identical on clean and
patched ROMs (a later upload overwrote the region), and without the control a
clean-vs-patched diff proves nothing — both are zero out there.

**[SMS-31]** Check which LAYER a text surface is on before aiming any glyph work. The
bracket names were chased on the 4bpp BG1/BG2 sheet for days while the plate was on BG3
— 2bpp, its own CHR base, its own delivery path — and movelist body text was invisible
until it carried the BG3 priority bit, a failure that only shows on bright stages
([SNES-24]).

## 5. WRAM and free space

**[SMS-32]** Boot-time copy loops spray junk through bank `$7F`. Any flag parked there
must be magic-valued (the project uses `$A5`) so that corruption can only ever *cancel*
a selection, never invent one — a plain boolean flag would arm features off boot noise.

**[SMS-33]** Menu-engine state lives in the `$7E:1F6x` region and menu code runs
*between* character select and round load — flags squatting there were silently armed
and disarmed by the VS-config screen, latent across eight builds. A WRAM freedom claim
needs a watch across the full session — boot → title → select → config → match → KO →
win — not one mode ([RH-31]); the two regions this project claimed were verified
untouched across exactly that sweep.

## 6. Repo harness conventions

**[SMS-34]** Every Lua tool bootstraps `sms_env.lua` — flat `tools/` scripts with
`/sms_env.lua`, `tools/saturn/` scripts with `/../sms_env.lua`. The wrong prefix fails
to load with no error and no output at all, which reads exactly like the emulator
ignoring the script ([RH-15] applies to your own tooling too).

**[SMS-35]** Never hand-edit the regression suite's SIGS detection block — it is
generated (`mksigs.py --write`, `--check` in the build scripts). A hand-pinned
stub-layout byte silently skipped all eleven tests of one patch for a week when a stub
change shifted it ([RH-53]).

**[SMS-36]** Every chained builder step requires `--stacked` (the SHA gate is
unconditional); ROMs resolve through `smspaths.py` (`$SMS_ROM_DIR` → `roms/` →
`../roms/`) and are never tracked — keeping the ROM directory above the working tree is
the maintainer's preferred anti-commit layout.

**[SMS-37]** Savestates are tracked (force-added, deliberately — they are inert without
an emulator and the suites load them by name); screenshots and any game imagery never
are, and `git add -f` is not an escape hatch — nine PNGs reached the public repo that
way before the rule was made repo-wide and history was rewritten. Two sessions must
never run emulator tests concurrently: the shared scratch cfg files drive the same
headless runner.

**[SMS-38]** The button map, empirically: Y=LP, X=HP, B=LK, A=HK — the vendor Lua's
comment has it wrong, and it is the kind of "known" fact worth re-measuring before any
input-driven harness is trusted ([RH-1]).
