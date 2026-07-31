# BUILDS.md — Saturn test-ROM registry (saturn-smoke series)

Builder: `python3 tools/saturn/mksaturn_smoke.py` → writes
`build/saturn/SailorMoonS_saturn_v<VERSION>.sfc` (version = `SATURN_VERSION` in
the builder; bump MINOR per feature batch, PATCH per fix). **The version is
embedded in the ROM ($EE:C040) and shown on-screen by `tools/saturn/
saturn_test.lua`** — quote it (or the SHA-1) in any regression report.
All builds read the clean SMS + Super S ROMs; same inputs ⇒ byte-identical ROM.

Versions before 0.6.0 are retroactive labels for the historical lineage
(rebuild any of them by checking out the commit; SHAs recorded at build time).

| Ver | ROM SHA-1 | Commit | Contents / changes |
|---|---|---|---|
| 0.1.0 | `f9e01364…` | `9c1f86f` | First smoke: Saturn as object id 0x1C; 3 animation layers (scripts CMD-stripped, pose records guard-FIXED, cels); idle/walk animate 228/228 — but INVISIBLE (no OAM layer) and universal acts via a borrowed Uranus proc. |
| 0.2.0 | `4cdec502…` | `9c1f86f` | She RENDERS: 4th layer (OAM sprite layout, $84:8000 system) found + ported; $AE WRAM-mirror fix for the emitter writes. Screenshots: idle/walk. |
| 0.3.0 | `8d1f7dc3…` | `0b4656b`/`8cded65` | PAD-PLAYABLE: her real ~4.4 KB proc block ported (recursive-descent + 384 operand fixups, bank $EF graft); button-map hook; recognizer graft (real qcf motion); box tables (bank $F0 via $B0 mirror) — hits connect both ways. All normals (stand/crouch/air) + 4 special variants. Projectiles self-despawn (invisible); Uranus palette; silent. **= the first build handed to the maintainer.** |
| 0.4.0 | `5cd44404…` | `8cf4adc` | PROJECTILES: objects 0x20/0x21/0x22 fully ported (procs $280B-$2B60 into $EF, scripts/poses/OAM/hit-boxes); fireball travels, hits at range, despawns; wave special both strengths. Effect tiles via runtime VRAM upload (probe_supers_effecttiles.lua dump). |
| 0.5.0 | `4cb02c5f…` | `43dc342` | REAL PALETTE: pal1/pal2 embedded at $EE:C000/C020; tester injects CGRAM shadow $0600 (OBJ pal 0) at transform. |
| 0.6.0 | `601920bc…` | `1beaad9` | VERSIONED BUILDS: version string embedded at $EE:C040, shown on-screen by saturn_test.lua; builder writes versioned filename by default. No gameplay changes vs 0.5.0. |
| 0.7.0 | `a0822027…` | (this) | SOUND: interpreter CMD case back-ported (audit: 757 SMS scripts have no 0xC0+ ctrl bytes — provably neutral); her scripts now CMD-INTACT (exact Super S timing); normals play whooshes (5LP/light 0x05, 5HK/heavy 0x06 via script CMD args), specials play the native starter sfx (0x08), hit sounds already worked; $EF:DB50 translator covers her proc's direct sound calls (throw/desperation acts). VERIFIED this build: throws both directions (her 6HP throw = acts 68/69; she can be thrown, victim acts 1C/1D/1E); low-HP dizzy correctly blocks specials. |
| 0.8.0 | `2b360298…` | `1ee037e` | **IN-ROM SELECT — no Lua needed: hold L+R (P1 pad) while a round loads → P1 becomes Saturn**; hold SELECT at a round load to revert. Persists across rounds. Her effect tiles load in-ROM (embedded at $EE:D000 from the one-time dump; DMA-staging override at the $C0:92A4 VRAM-DMA kick); palette injected in-ROM at transform; live-round gate ($1E04==0 + clock≠0) keeps the intro sequencer safe. P2 still Lua-only. Without L+R the ROM behaves stock. **Known bug: L+R only worked in 2P VS** (the live-round gate required the round clock — training has none). |
| 0.8.1 | `b9d98964…` | `739b9d5` | FIX (field report): **L+R select now works in ALL modes** — training/practice, 1P-vs-CPU, 2P VS (verified headless in each). The live-round gate's clock check replaced with `$01FA==0x80` (0xE1 during the dangerous load window; the p11-proven gameplay signal that holds in clock-less practice mode). |
| 0.9.0 | `e29f41bb…` | `2e13daf` | **P2 IN-ROM SELECT**: hold L+R on the **P2 pad** at a round load → P2 becomes Saturn — mirror matches, and **Saturn as the training dummy**, no Lua. The effects-DMA hook now serves both transfers (P1 VRAM $6A00 / P2 VRAM $7300, staging $7F:0000 reused; P2 pad = $421A/B); helper v3 transforms either player with per-player palette rows ($0600/$0620). SELECT on the respective pad reverts. Verified: both-players VS mirror, P1-only VS, practice, vs-CPU, no-L+R stock, smoke, fireball. |
| 0.10.0 | `9751c585…` | `5eb58c1` | **CHAR-SELECT 10TH SLOT** (placeholder graphic): Saturn is now a visible pick on the select screen — a parked cursor glyph marks a 10th spot at the photo's bottom-right (170,162); Chibimoon-right or Venus-down reaches it, confirming picks her (cursor → shell Uranus + select flag; the proven round-load transform does the rest). Works for P1, P2, and the practice dummy; browsing off the slot clears that player's flag, L+R at load still overrides. Story/1P mode deliberately excluded — its nav table (t2, $AA75) exists to restrict the roster (outer senshi = story bosses; forcing cursor 6 crashes VANILLA — verified), so slot 10 follows the same policy there and 1P Saturn stays L+R. Plus two latent-bug fixes: (1) the $E8 script copy now takes the FULL region 0x0000-0x2800 (vanilla story-scene act pointers reach 0x2780; the old 0x2200 cut clobbered them since 0.1.0 — Saturn's act table moved to $E8:2C00, projectile blob relocated to $E8:3200 with act-table words rebased); (2) transform now arms via per-round latches $1F62/63 set by the DMA stub at the effects transfer — a flag set before load (char-select or stale) can no longer reach the helper during load/dialogue windows. Verified: slot-10 select in VS (mirror) / practice-dummy / story-exclusion + story fight loads, flag-clear browsing, stock no-select, smoke, L+R both, fireball, pad 11/11, attacks, throws/KO/guard flow. |
| **0.11.0** | `3e6a8caf…` (visible) / `433a1857…` (hidden) | (this) | **HIDDEN-CHARACTER BUILD VARIANT** (maintainer request, "like Gouki in SF2" — keeps Saturn concealable if balance stays rough). One builder, two ROMs: default = the 0.10.0 visible slot 10, unchanged; `SATURN_HIDDEN=1 python3 tools/saturn/mksaturn_smoke.py` = `…-hidden.sfc` (version string `v0.11.0H`): NO marker, NO navigable slot — instead **hold L+R while confirming ANY character** at the select screen and that character becomes Saturn at round load (works for P1, P2, and the practice dummy — the code reads the physical pad that drives the confirming cursor, so P1's pad codes the dummy). Every confirm re-decides (no code = flag cleared, stale flags self-clean). L+R-at-load unchanged in both. Verified hidden: VS (P1 Uranus+code → Saturn with code RELEASED before load, P2 no-code stays Jupiter), practice (Moon no-code + Jupiter-dummy+code → Saturn dummy), no marker, no slot leak, story-safe, smoke, L+R-load. Verified visible: identical to 0.10.0 (3-byte diff: version + checksum), all charsel10 modes + smoke + L+R-load re-run green. |


## Known gaps (as of 0.7.0)

- Desperation not yet triggered (its motion is unknown; low-HP requests are
  correctly refused during the danger act — no crash path). KO/round flow
  verified crash-free; win-pose visuals unchecked.
- Sound mapping is approximate (SMS whoosh/starter sfx for her Super S commands);
  refine per-move later if it feels off.
- Fireball art needs the one-time effect-tile dump (see saturn_test.lua header);
  without it the fireball renders with Uranus's effect tiles.
- Char-select slot 10 is a PLACEHOLDER (0.10.0): the marker is a parked cursor
  glyph, not a portrait; hovering it shows no name text and the post-confirm
  portrait/VS/HUD screens show the shell character (Uranus). Real portrait art
  + name pending. Story/1P select intentionally excludes the slot (vanilla
  restricts the story roster the same way) — use L+R there.
- Bank layout claims $E8-$F0 — REF-patch reconciliation pending.

## How to test

```bash
git pull
python3 tools/saturn/mksaturn_smoke.py          # -> build/saturn/SailorMoonS_saturn_v<ver>.sfc
SATURN_HIDDEN=1 python3 tools/saturn/mksaturn_smoke.py   # -> ..._v<ver>-hidden.sfc (0.11.0+)
# one-time, for correct fireball art (needs the Super S ROM):
ROM=<SuperS.sfc> tools/run.sh tools/saturn/probe_supers_effecttiles.lua 60
```
**Hidden variant (0.11.0, `-hidden.sfc`)**: nothing visible — hold **L+R while
confirming any character** at the select screen; that character becomes Saturn
at the round load. Works for P1, P2, and the practice dummy (the code follows
the pad that drives the confirming cursor). Confirming without the code always
un-picks. **Visible variant — since 0.10.0**: in VS or practice char select, go to Chibimoon and press
RIGHT (or Venus + DOWN) — the cursor lands on a marked 10th spot at the
photo's bottom-right; confirm to pick Saturn (shows as Uranus until the round
loads). Works for P1, P2, and the practice dummy. **Since 0.8.0**: hold L+R
as a round loads (either pad) — that player becomes Saturn; SELECT-hold at a
round load reverts; this is also the ONLY way in story/1P mode.
`tools/saturn/saturn_test.lua` remains available (auto-transform + P2 mirror
matches + the on-screen version label).
