# feasibility.md — Route A (Saturn → SMS) vs Route B (SMS → Super S)

Status 2026-07-30: evidence gathered (see `supers_map.md` for every measured fact);
**recommendation at the end**. Decision is the maintainer's.

## Evidence base (all verified this session unless [W])

**The games are the same engine, globally shifted.** Super S's code is SMS's code
relocated by small per-routine deltas (char loader +0x18, on-hit tables +0x12A,
damage matrix +0x148 — with IDENTICAL contents where SMS ground truth is locked),
same WRAM layout (structs, mode vars, char-select — all probed live), same box data
format (5 of 9 shared characters' hit tables byte-identical; Uranus's SMS hurt table
is an untouched 81-entry prefix of her Super S table). Where signatures DON'T match,
they coincide with the sequel's documented gameplay changes (desperation records,
apply-site pattern, hit-resolution head) [W: projectiles/DMs nerfed, no bugfixes].

**Saturn is real and reachable.** She loads into a live match via the standard
char-select poke; her box tables (30 hit / 93 hurt-pairs / 6 coll) are extracted;
her far 5HK is EMPIRICALLY unblockable (hits through held guard at 34-44 px,
blockable only ≥48 px; 5LP control blocks normally) — a per-move guard-proximity
data bug, i.e. tunable data once located.

## Route A — port Saturn INTO SMS (the a-priori preference)

What it takes (from the SMS architecture dossier, measured):
1. **Table relocations** (no dormant slot exists; six 9-char tables are packed):
   manifest ptrs `$E0:0238`, hurt/coll box ptrs `$8A:C229/C23D`, state-proc tables
   `$C1:169B` + `$C1:0881`, charsel nav `$C0:AA4D/AA75` + size `$C0:AF5E` — each
   relocated to an appended bank + ~12 known reader sites repointed. Mechanical,
   provable by byte-audit; the reader sites are already located.
2. **Data port** (formats identical — extraction already works): box tables (~1.6 KB),
   manifest record (d48=1 + palettes + anim payload), palettes (24 KB free at
   `$E8:A000`), portraits/select-screen art (group photo needs a 10th face — real
   pixel work), theme music entry.
3. **Code port — the hard part**: Saturn's per-character move-handler code lives in
   Super S's shifted bank $C1 and references shifted engine routines. Options:
   (a) relocate her handler block to an appended SMS bank and fix up its calls to
   SMS-local equivalents (the call targets are the SAME routines at different
   addresses — the signature hunt shows they exist 1:1 for the core paths);
   (b) reimplement her movelist against SMS conventions using her data tables.
   Either is the project's main effort. Her 8-entry cancellable set and 0x40+ act
   numbering need integrating with SMS assumptions (act ranges, +0x44 classes —
   candidates 0x1C-0x1F are free).
4. **Sprite/CHR**: her animation payload + sprite sheets from Super S banks —
   size/compression to be measured (manifest anim ptr known: `$E0:F328`).
5. Our patches: 10th entries in p12/p13/p14 tables, p3 loops, const.lua, extractors.

**Wins:** every SMS behavior stays bit-exact (the entire verified ground truth, REF
patches, test estate, savestates keep working). Saturn's balance bugs don't ride
along unless we port them — we ADD her with SMS-correct guard data from day one.
**Risks:** the handler-port unknowns (how self-contained is a character's code
block; how many engine-routine fixups; sprite decompression format).

## Route B — port SMS values/patches INTO Super S

What it takes:
1. Re-derive EVERY REF-patch hook for Super S (11 patches; every one currently
   DIFFERS at its SMS offset — all sites must be re-found; the signature hunt shows
   the method works but each patch needs its own investigation + re-verification).
2. **Revert the sequel's gameplay changes** to satisfy "plays like SMS": restore the
   9 characters' SMS projectiles/desperations/damage records (the wiki lists broad
   nerfs; our byte evidence confirms desperation records and apply-sites changed),
   fix the Neptune charge/DP input regression, re-verify every SMS engine invariant
   (the regression suite's ground truths) on the ported build. This is a
   comparison-and-restore effort across the whole cast — bigger than it sounds.
3. Rebuild the verification estate for Super S addresses (fingerprints, fixtures,
   suite expectations), essentially forking the project.
**Wins:** Saturn (and stages/music — the nice-to-have comes FREE) pre-exist; no
character port, no charsel/roster surgery.
**Risks:** "plays like SMS" becomes an open-ended asymptote — every unnoticed
sequel change ships; the SMS test estate doesn't transfer without re-derivation;
the maintainer's verified ground truth (years of it) is mostly invalidated.

## Recommendation

**Route A**, as preferred a priori — the evidence strengthens it:
- The engines' sameness cuts Route A's hardest step (her handler code calls the
  SAME routines, just shifted — fixups are enumerable), while Route B's hidden cost
  grew (documented cast-wide gameplay changes that must all be found and reverted).
- Route A keeps the SMS ground truth + test estate + REF patches live; Route B
  restarts verification nearly from zero.
- Saturn's brokenness is data (guard proximity), so Route A can integrate her
  FIXED, which is the project's stated goal.

**What would flip it:** if the handler-block port proves non-self-contained (e.g.
her code is interleaved with shared routines that themselves changed, or the sprite
pipeline resists extraction), Route B remains viable — and its step 2 can be bounded
by porting the SMS regression suite to Super S addresses first and letting it
enumerate the behavior deltas.

**Next-session probes to de-risk Route A** (in order):
1. Locate Saturn's handler block in Super S bank $C1 (act 0x40+ dispatch) and
   measure its size + count its external call targets (Dispel + the signature map).
2. Decode her anim payload (manifest `$E0:F328`) — LZSS same as SMS's `$C0:916B`
   path? Size?
3. Find the guard-proximity data (the far-5HK bug) — both a balance knob and a
   Rosetta probe for the on-hit/guard tables.
4. Sprite CHR location/size census for the porting budget.

## De-risk probe results (run 2026-07-30, same session)

1. **Handler block**: not sized yet — byte-shingle isolation is defeated by operand
   shifts (see supers_map §Bank $C1). BUT her dispatch integration is now mapped:
   both per-char tables are SMS's structures widened to 11 entries, and her
   recognizer record has the exact SMS shape (5 specials + FFFF). Sizing needs
   Dispel along her act dispatch — mechanical, method known. Route A confidence: up.
2. **Anim/sprite pipeline: RESOLVED.** The manifest anim field is dead in Super S
   (never read; $E0:F328 never read either). Cel graphics stream uncompressed from
   ROM per frame via two fixed streamer routines (P1 $80:A244 / P2 $80:A29F);
   Saturn's 5HP cels located ($DD:7C60-9600). Route A's graphics port unit =
   cel blocks + the per-frame cel-address tables those routines read + the
   animation scripts; remaining work is enumeration (census per move) and
   disassembly of the two streamers — mechanical, methods proven.
3. **Guard-proximity: RESOLVED (same day, later session).** The proximity-guard
   trigger is the pose-record class byte (+0x18, class 9 = threat; system mapped in
   supers_map §Pose records). Saturn's far 5HK/5LK startup poses are the roster's
   only class-0 attack poses → the guard pose loses the race to hit resolution.
   **Fix = 1 byte per move ($84:9289 / $84:927D byte0 00→09), A/B-validated:
   blocked when guarded, still hits otherwise.** Far 5LK unblockable also now
   CONFIRMED empirically (@24px). Balance knob #1 settled; she can ship fixed.
4. **Sprite CHR census**: method proven (DMA census probe, idle/attack windows);
   first data point in saturn_notes §3c. Full enumeration next session.

Also refuted en route: the "attack-class table overflow" hypothesis for her
unblockables (her classes are textbook SMS — see saturn_notes §3b).

Net: recommendation UNCHANGED (Route A); the flagged pipeline unknown is RESOLVED.
Remaining next-session work is enumerative (cel census, streamer disasm, guard-
success location, handler sizing) — no open architectural unknowns.
