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
| **0.9.0** | `e29f41bb…` | (this) | **P2 IN-ROM SELECT**: hold L+R on the **P2 pad** at a round load → P2 becomes Saturn — mirror matches, and **Saturn as the training dummy**, no Lua. The effects-DMA hook now serves both transfers (P1 VRAM $6A00 / P2 VRAM $7300, staging $7F:0000 reused; P2 pad = $421A/B); helper v3 transforms either player with per-player palette rows ($0600/$0620). SELECT on the respective pad reverts. Verified: both-players VS mirror, P1-only VS, practice, vs-CPU, no-L+R stock, smoke, fireball. |

## Known gaps (as of 0.7.0)

- Desperation not yet triggered (its motion is unknown; low-HP requests are
  correctly refused during the danger act — no crash path). KO/round flow
  verified crash-free; win-pose visuals unchecked.
- Sound mapping is approximate (SMS whoosh/starter sfx for her Super S commands);
  refine per-move later if it feels off.
- Fireball art needs the one-time effect-tile dump (see saturn_test.lua header);
  without it the fireball renders with Uranus's effect tiles.
- No char-select portrait/slot — selection is the hidden L+R hold (either pad,
  each player independently). HUD name/portrait show the shell character you
  picked. Bank layout claims $E8-$F0 — REF-patch reconciliation pending.

## How to test

```bash
git pull
python3 tools/saturn/mksaturn_smoke.py          # -> build/saturn/SailorMoonS_saturn_v<ver>.sfc
# one-time, for correct fireball art (needs the Super S ROM):
ROM=<SuperS.sfc> tools/run.sh tools/saturn/probe_supers_effecttiles.lua 60
```
**Since 0.8.0, no Lua needed**: open the ROM, pick any P1, and HOLD L+R as the
round loads — P1 becomes Saturn (SELECT-hold at a round load reverts).
`tools/saturn/saturn_test.lua` remains available (auto-transform + P2 mirror
matches + the on-screen version label).
