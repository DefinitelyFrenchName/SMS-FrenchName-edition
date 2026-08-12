# Porting lessons — the rules the Super S → SMS port taught us

Donor: **Bishoujo Senshi Sailor Moon Super S** (SFC, Japan); host: **SMS** (clean SHA-1
`bc0e29ee383574443226695215496eb0d09aaa1c`). This file is METHODOLOGY, not data: the
donor-port rules and traps this project paid for, each with the incident that taught it.
It is the human rendition of the agent skill `.claude/skills/supers-porting/SKILL.md` —
the two carry identical rule-ID sets (`[SSP-NN]`), enforced by `tools/checkskills.py`.
Address-level claims live in the checked corpus (`supers_map.md`, `supers_assets.md`,
`sound_scope.md`, `BUILDS.md`, gated by `tools/saturn/checksaturndocs.py`); this file
quotes no ROM addresses. Layers below: `docs/game/sms_hacking_playbook.md` (`[SMS-NN]`)
and the user-level `snes-romhacking` / `romhacking-methodology` skills
(`[SNES-NN]` / `[RH-NN]`).

## 1. Donor provenance

**[SSP-1]** The two games are the same engine, globally shifted by small per-routine
deltas — twins are found by signature and skeleton, and byte inequality does not imply
code inequality (an identical pad-read routine proved code equality despite shifted
bytes). But nothing may be assumed by analogy: the movelist codec does not exist in
Super S at all, and the two games do not share an audio engine. Both discoveries cost
time precisely because the engine identity had held everywhere else.

**[SSP-2]** Engine object ids are shifted by one between the games (donor id N is host
id N−1 in the upper range). A ported proc whose spawn records kept donor ids ran the
wrong object type — and the failure mode is maximal: the wrong proc can fail to return,
killing the per-frame update. Frozen game, music still playing, screen black.

**[SSP-3]** The inherited tooling came from Super S, so its Saturn references are
statements about the *donor*: never search the SMS image for Saturn data ([SMS-1]), and
validate any inherited map on the emulator before building on it. The port's entire doc
corpus was eventually gated against both cartridges because it was the one body of
documentation the project *built on* and the last one checked — four claims in its
identity paragraph did not survive ([SSP-5]).

**[SSP-4]** Donor fixtures can silently be the wrong game's dumps: a set of ARAM traces
under a host-sounding name hashed identical to the donor's. Hash-check which cartridge a
fixture came from before using it as an oracle.

**[SSP-5]** Cross-game identity claims are measured per subsystem and stated with their
caveats inline. "Universal-act scripts byte-identical" was true only after stripping the
donor's extra command steps (raw: ~26 of 43; stripped: 43/43 for five characters);
"cel records same sizes" was 97 of 98. The doc had asserted each conclusion in one
sentence with the caveat two paragraphs later — which is how the foundation of a port
rots while looking documented.

## 2. The shell rule

**[SSP-6]** **The shell rule.** Saturn wears a host character as a shell, so anything
keyed to *character* data silently works for that shell only and presents as unrelated
bugs on the others. Paid for twice at full price: a hook keyed to one shell's
sprite-list pointer, and the projectile bug below ([SSP-10]) — five build bisections run
on one shell all correctly reported "identical" while the fault lived on another. Test
every such fix with at least two shells; prefer per-player keys, which cover all shells
by construction.

**[SSP-7]** Guard the thing that ARMS, not the things that act. The shell restriction
started life at the transform — but the select voice, the in-match sound remap and the
effect-tile/palette override all key off the summon flag, which is set much earlier. A
disallowed shell therefore armed everything except the one guarded thing. The rule
lives where the flag is set, with the confirmed id recorded so every later consumer can
apply the same test.

**[SSP-8]** Structural locks beat mode interrogation. The story lock works by
restricting which shells may arm her — the three the story roster cannot reach — rather
than by asking what mode the game thinks it is in, which is exactly what a field report
defeated on an earlier build.

**[SSP-9]** A summoned character's reachable palette slots are 4-7 only, because the
L+R summon chord doubles as the palette-modifier buttons. The first cut of the palette
fix *clamped* out-of-range slots to her default and thereby reproduced the original bug
exactly; masking the slot is the fix. The measurement that revealed the whole issue: her
second canon palette, embedded since the earliest builds, had never once been on screen.

**[SSP-10]** Transfers sized from the shell truncate ported data ([RH-39]). Her staged
effect sheet was byte-perfect in WRAM, but the following DMA took its length from the
shell's own sheet — one shell's was 15 tiles smaller, and her projectile drew 7 of its
12 sprites from exactly the missing range. Intact on two shells, broken on the third
([SSP-6] again). The fix forces the length on the armed path; the gate that grew out of
it asserts her sheet is byte-identical in VRAM across all shells — an invariance
property, deliberately not a hardcoded checksum, so it survives future art edits.

**[SSP-11]** A visible character-select slot is the exact surface the story lock exists
to avoid: the visible slot-10 build was retired and deleted, its removal proven inert by
a byte-identical rebuild ([RH-45]). The hidden summon is the only select variant, by
maintainer ruling.

## 3. Graft mechanics

**[SSP-12]** The build grafts a full copy of the proc bank for her ported code, and the
copy is taken before hooks land — so a hook applied to the original bank protects only
half the paths. "The ROM has exactly two reads of this table" was measured on the clean
ROM and false of the artifact; with Saturn as the thrower, her proc ran out of the copy,
the unhooked read indexed a nine-wide table past its end ([SMS-3]), and the throw
corruption survived four sessions. The builder now asserts zero unhooked reads of any
patched table anywhere in the assembled image ([RH-37/38]).

**[SSP-13]** Take bank copies AFTER other patches' edits when stacking: two shipped
patches edit the real box-data bank, and a copy taken first resurrects vanilla data
under the port.

**[SSP-14]** A donor sentinel record is live data in the host. The donor's "no cel"
record — a size-0 entry no vanilla character ever points at — was skipped by the
builder's rebaser; the host engine does not skip it, and a 0-length DMA is a 64 KB DMA
([SNES-16]) that wiped VRAM from a garbage source.

**[SSP-15]** Truncated grafts fail late and silently. A code graft cut short executed
stale copy bytes mid-handler (garbage act, a projectile that never dies, her wait-state
wedged); a data graft one pair short routed the motion recognizer into a hold path that
never increments at timer 0 — a parked state machine, no crash, nothing to see. Bound
every copied block by the donor's own end markers, not by where the interesting part
seemed to stop.

**[SSP-16]** Lift donor tables rather than authoring where possible — her thrown-pose
list was lifted, not written, and the nine shared lists being byte-identical across the
two games is what proves the step semantics match. Before fixing an inherited fault,
confirm it byte-identical in the donor ROM first: both ground-throw faults were, so the
fix corrects the original game rather than the port. And faithful ≠ bug — her close 5HK
starting with a knee and her missing step-dash are both donor-accurate, verified there
before anyone "fixed" them.

**[SSP-17]** Scene scripts have four parts, and only the sprite-attribute byte may be
carried across from a donor scene — the remaining parts are host-side ids, and porting
them hangs the round load. That one attribute byte, never carried, was why the ported
stage's castle covered the fighters through four rounds of workarounds ([RH-33]).

**[SSP-18]** Stages are swapped, not added: the scene pointer table is exactly ten
entries with the scripts starting immediately after — the nine-wide-table law
([SMS-3]) recurring outside the character tables. Swapping is data-only; adding one is
a project.

## 4. The audio port

**[SSP-19]** The per-character BRR directory is resident from boot and never refreshed
per match — so loading her sample bank was only half the job: under borrowed ids her
audio played cut at the shell's directory offsets. And the borrow must be undone: her
build overwrites one character's per-player half-record for that player only, restoring
it (dirty-flag gated) on any non-Saturn load, or the borrowed character buzzes for the
rest of the session.

**[SSP-20]** The engine's relocating uploader adds a direct-page offset to every
destination it writes — appending a block to that stream lands it 16 bytes high. The
block goes through its own path, not the relocated one.

**[SSP-21]** Her samples have two native rates, not one. The recorded mistake, verbatim
from the sound log: assuming one native rate for everything she has, then treating a
measurement of one set as confirmation for the other ([RH-33]).

**[SSP-22]** The driver plays samples as notes on a scale: "her voice is sharp" is not
one wrong constant but a per-sound signed transpose byte, character-specific across the
roster. And the DSP's SRCN register names the sample that *actually played*, so "which
sound is this?" is a measurement, never an inference — the sound work's own general
lesson records that every wrong turn came from reasoning about where a sample ought to
live. One quoted donor reference value was itself unverified and is flagged as such in
the log ([RH-3]).

**[SSP-23]** Borrowing an existing character's per-player sound ids covers all nine
shells with no per-shell code — the two halves of the record are per player, so a real
copy of that character on the other side can never collide. It dodges the shell rule
([SSP-6]) by construction, which is the best way to dodge it.

**[SSP-24]** Super S ships exactly two palettes per character — the other two manifest
pointers are the icon and effects palettes, not costume colours — so extra selectable
palettes must be authored (rotating only the costume ramp), and the usual donor of
extras has no Saturn to lift from. Two catalogue quirks worth knowing: she is the only
character whose two palette pointers are stored in descending order, and the two
corpora name the same palettes differently (pal1/pal2 vs palette 0/1). Finally, donor
and host can ship the *same* asset in different forms — the in-match HUD sheet is raw
in the donor and compressed in the host, 503 of 512 tiles byte-identical — which is why
every compressed-stream search for her badge tiles came back empty. Search both forms
before concluding an asset is absent.

## 5. Cross-game verification and constraints

**[SSP-25]** Cross-game doc checks run against BOTH cartridges, SKIP loudly when the
donor ROM is absent ([RH-55]), and carry their own negative control: hand the checker
the same image twice and it must fail, or it is comparing nothing ([RH-9]).

**[SSP-26]** Ported code blocks are gated byte-identical (`port_saturn_proc.py
--check`), and the decode table behind the porter is validated against an independent
disassembler by a different author ([SNES-13]) — the porter's original private table
was wrong in two ways that its own workload happened never to reach.

**[SSP-27]** Port bundles are deliberately untracked: they embed donor cels, palettes
and BRR samples, so the repo ships the *recipe* (a named gate script) rather than the
artifact. The verify gate is sanity-checked against known-bad builds — on one retired
build the quick matrix fails 7 of 16, on another the newest check fails — because a
gate that cannot fail is not a gate ([RH-25]); its newest check exists precisely
because the previous 45 passed for two weeks on a build carrying a live bug.

**[SSP-28]** The constraint model, measured: ROM is not scarce (hundreds of KB spare),
ARAM is the only hard wall ([SNES-25]), and the real cost of a true tenth character is
nine-wide *layout* ([SMS-3]) — tables sized to nine and immediately followed by live
data, each needing relocation and every reader repointed. "More ROM" solves nothing
here, which is why she wears a shell (`memory_and_shell.md` carries the budgets).
