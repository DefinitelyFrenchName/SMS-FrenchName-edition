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
| 0.11.0 | `3e6a8caf…` (visible) / `433a1857…` (hidden) | `08d7b03` | **HIDDEN-CHARACTER BUILD VARIANT** (maintainer request, "like Gouki in SF2" — keeps Saturn concealable if balance stays rough). One builder, two ROMs: default = the 0.10.0 visible slot 10, unchanged; `SATURN_HIDDEN=1 python3 tools/saturn/mksaturn_smoke.py` = `…-hidden.sfc` (version string `v0.11.0H`): NO marker, NO navigable slot — instead **hold L+R while confirming ANY character** at the select screen and that character becomes Saturn at round load (works for P1, P2, and the practice dummy — the code reads the physical pad that drives the confirming cursor, so P1's pad codes the dummy). Every confirm re-decides (no code = flag cleared, stale flags self-clean). L+R-at-load unchanged in both. Verified hidden: VS (P1 Uranus+code → Saturn with code RELEASED before load, P2 no-code stays Jupiter), practice (Moon no-code + Jupiter-dummy+code → Saturn dummy), no marker, no slot leak, story-safe, smoke, L+R-load. Verified visible: identical to 0.10.0 (3-byte diff: version + checksum), all charsel10 modes + smoke + L+R-load re-run green. |

| 0.11.1 | `e6c5d511…` (visible) / `75bbfc8c…` (hidden) | `251fb6d` | **FIELD-REPORT FIXES** (all three repro'd + verified headless): **(1) j.632K crash** — the air special (act 0x74→0x76) spawns projectile id 0x21, whose proc's post-dispatch `jmp $024D` was never operand-fixed (the port's walker treated `jsr (abs,X)` as non-returning, so the continuation was unreached): it entered the SMS twin routine 2 bytes late, skipping its `rep #$30`, and the 16-bit `cmp #$00C0` misdecoded into cmp+**BRK** → engine wedge, black screen, music alive. Walker now falls through `jsr (abs,X)`; two new EXT_MAP twins ($024D→$024B, $0231→$022F — the id-0x20 proc had the same latent hole). Air special now completes and its projectile flies/despawns. **(2) red fireballs** — both games draw projectiles with OAM palette 2; Super S loads a blue effects palette there ($E0:B208) which SMS lacks → embedded at $EE:C060, injected into shadow $0640 at transform (both players; tradeoff: a non-Saturn opponent's own projectile art recolors while a Saturn is in play). The in-line copy loops overflowed the $EF helper's REAL slot (DB70–DC00, 0x90 bytes — the old 0x100 assert was too loose and briefly wedged everything) → palette copying moved to an $EE subroutine (EE_PALCOPY), helper assert tightened. **(3) backdash silent** — her movement sounds are script-CMD driven: args mapped to natively-measured SMS values (backdash/dash 0x2D, jump 0x0C, landing 0x0D; hit-reaction/starter args left to the engine paths to avoid doubling); also fixed a latent cmd-stub compare cascade (a matched entry kept comparing with A=sfx — harmless with 4 entries, colliding with 8). NOTE: Saturn has NO forward step-dash — verified identical in Super S (66 walks); port is faithful. Full suite green on both variants. |
| 0.11.2 | `fcb39406…` (visible) / `c5b5c2d3…` (hidden) | `c27a729` | **DESPERATION WORKS — Death Drive Break**: `412364+HP` at HP≤0x18 (≈8f per direction; HP specifically — the spec's button mask 0x40 is heavy punch only). Startup act 0x78; on hit act 0x79 = a full-screen 8-hit rushing sequence, verified frame-identical to Super S. Root cause of the long-standing "recognizer freezes at step 5" mystery: the graft's spec-payload copy was one pair short (HI 0x1616 vs the true end 0x161B) — spec5's 6th direction read leftover SMS bytes that parked the matcher's hold path at timer 0. One-line bound fix. Also decoded along the way: the full request-nibble map (2=dash-back, 4/5=qcf, 6/7=632K air, 8/9=qcb, A/B=desperation) and the complete matcher semantics (hold/bitmask/timeout pair types, commit-on-FF). Full suite green both variants. |
| 0.11.3 | `917428eb…` (visible) / `b26eb0e5…` (hidden) | `8d127b4` | **WIN-SCREEN HANG FIXED** (found by the win-pose verification pass): the round-result sequencer loads per-WINNER-id far pointers from packed bank-$82 tables (name-plate records $82:E008+id*2 — 4 sites; win-quote pointer arrays $82:E01C+id*2 — 2 sites) and long-DMAs the records to VRAM; Saturn's id indexed far past both tables → a garbage row-count word became a monster DMA loop = **black-screen hang after any round Saturn won** (invisible in practice mode, which never runs the win sequence). All 6 sites hooked with two $EE stubs serving her ported Super S records (name plate + 4 win quotes; tile indices verified present in SMS's shared win tileset). Verified: her win pose animates in-field (Silence Glaive victory stance, screenshot), round 2 loads frame-identical to a vanilla control, full 2-round match completes into the report-card screen. Known cosmetics: report card shows the shell portrait; story-mode quote card eyeball pending. |
| 0.11.4 | `7ff62baa…` (visible) / `d62c1304…` (hidden) | `086cd24` | **SELF-CONTAINED BUILD — fixture dependency dropped**: the graphics LZSS decompressor + its job table are fully decoded (`$C0:EE30`, table `$80:EEF1`; Python twin `tools/saturn/supers_lz.py`, validated byte-exact against a live staging dump and the full per-ctrl-byte trajectory). Her effect tiles now decompress from the Super S ROM at build time (source `$E3:FA09`, job idx 57/67 = P1/P2) — no more `supers_effecttiles.bin` requirement, and the embed is the FULL 0x1040-byte sheet (the old dump was 0x440 bytes short; the staging-override MVN count fixed to match). Verified: in-game VRAM after a real L+R load is byte-identical to the decoder output; suite green. Bonus: the per-char effect-source pointer table mystery (open since 0.4.0) is closed. |
| 0.11.5 | saturn: `36e7da45…`/`70dfefff…` (vis/hid); REFsaturn: `a7e31ed0…`/`0a12c892…` | `de9317f` | **REF v.1 RECONCILIATION — the project-goal artifact exists**: the builder is now bank-agnostic (every $E8-$F0 literal + WRAM-mirror byte derives from the actual first-free bank; refactor proven BYTE-IDENTICAL on the clean base) and accepts `SATURN_BASE=<rom>` to stack on the REF v.1 bundle — Saturn occupies $F0-$F8 there. One real collision, resolved by chaining: patch 5's char-select confirm hook (JSL at $C0:A630) is called from the tail of Saturn's confirm stub, preserving both (alt palettes + slot 10). Byte audit: the stacked build touches exactly the 40 known Saturn sites in the REF image, nothing else; Saturn's C1/$8A/$82 bank copies inherit REF's patched engine (consistent behavior incl. taunt/Guts mechanics for her). Full suite green on the combined ROM. **`tools/saturn/build_refsaturn.sh`** = the committed recipe (REF v.1 chain + stack; SATURN_HIDDEN=1 supported → `…REFsaturn_v0.11.5-hidden.sfc`). On-screen version tells: plain `v0.11.5` = clean base, `v0.11.5R` = REF base (+`H` hidden). |
| 0.11.6 | saturn: `7f4a56d4…`(vis)/`ad4aebdd…`(hid); REFsaturn: `a6301f3f…`(hid) | `0ef98b0` | **WRAM COLLISION FIX — the select flags were squatting on live game memory.** Found while REing the config screen: `$7E:1F60-$1F63` is bank $C3 menu state — the game itself writes all four (`$C3:B904` sets `$1F60`=1, `$C3:B973`/`$B9F5`/`$BA57` the others) and reads them. Our P1/P2 select flags + per-round latches lived exactly there, and the VS-config screen runs BETWEEN the char-select code and the round load — i.e. a menu path could silently arm or disarm Saturn between picking and playing. Relocated to `$7F:F100-F103` (empirically verified untouched across a full vanilla session — boot/charselect/config/match/KO/win — and a page clear of patch 11's `$7F:F000-F065`); all stub accesses converted to long addressing. **This was latent in every build since 0.8.0 and is the top suspect for any "the code didn't take" oddity in field testing.** Suite green on both variants + REF-stacked. |
| 0.11.7 | saturn: `17c870dc…`(vis)/`86171a8e…`(hid); REFsaturn: `1b48fa5b…`(hid) | `817f310` | **THE SELECT MECHANISM ACTUALLY WORKS NOW — field report root-caused.** Chain of three real bugs, each masking the next: (1) the DMA stub read the pad registers with **DB-relative** addressing (`lda $4218`) but is JSL'd with the caller's data bank, so it sampled WRAM garbage — **the L+R arming never worked at all**; it only *appeared* to because the game's own menu code writes 1 to `$1F62` (`$C3:B9F5`), which was our old latch address, so menus armed Saturn by accident (and explains why it worked in some modes and not others, e.g. the maintainer's PvC failure). Pads now read long. (2) Junk: `$C0:9251` is a generic pointer-driven copy loop that was observed spraying `7F/3F/7F` into our block at boot — so "nonzero = selected" could arm Saturn at random. Flags are now **magic-valued (`0xA5`)**: junk reads as not-selected (fail-safe), and the latch is rewritten every load so it can never go stale. (3) The rewritten stub outgrew 8-bit branch range; all jumps to the tail are `brl` now, with build-time range asserts so it cannot recur silently. Verified: hidden select in **VS, practice AND vs-CPU**, L+R-at-load both pads (effect tiles 256/256), visible slot in all three modes, REF-stacked build, smoke/fireball/airspecial/pad suites. |
| 0.11.8 | saturn: `42ef2a0c…`(vis)/`c2a56fdb…`(hid); REFsaturn: `b466909c…`(hid) | `c15bcc1` | **THE IN-MATCH FREEZE IS FIXED** (maintainer's "crashed while fighting"). Reproduced deterministically with a randomized stress harness: **any KO where Saturn is the VICTIM** froze the game — everything stops, music keeps playing, screen fades to black. Root cause: the two games' ENGINE object-id tables (`$C1:00A6`) differ by one entry in the effect range — **Super S id N is SMS id N−1 for N ≥ 0x31** (verified by proc byte-match: SUP 31/32/33/34 → SMS 30/31/32/33 at 35–42 of 48 bytes). Saturn's proc spawns engine effect objects from records in her data pocket, and her KO handler (act 0x1E) spawns two id-`0x34` objects; under SMS that id is a *different object type* whose proc never returns, so the whole frame update dies. Her three spawn records are now id-shifted (`SPAWN_ID_FIX`, asserted at build time). Verified: KO chain completes (1A→1E→1F, she lands, `$1E05` advances, winner does her pose), 8 mirror + 3 solo randomized stress runs play full matches to completion, plus smoke/lrboth/fireball/airspecial/pad/flow/charsel-all-modes/winpose. Also in this build: Saturn's proc-table entry is filled and routed through the id trampoline, so the engine's OTHER dispatchers (`$C1:1708`, `$C1:259E`, and the ones in other banks) can reach her instead of jumping to `$0000`; the trampoline moved to `$EF:DA60` after outgrowing its slot. |
| 0.11.9 | saturn: `e23130fc…`(vis)/`aceacdd4…`(hid); REFsaturn: `0abc15d8…`(hid) | `54ae3dd` | **SAFETY FIX for the 0.11.8 proc-table entry** (suspect for the field-reported screen-wide tile corruption and the doubled 5LK sprite). 0.11.8 pointed Saturn's proc-table entry at the id trampoline so the engine's other dispatchers could reach her — but those iterate the projectile (`$1100`) and effect (`$1200`) pools, so ANY pooled object carrying id 0x1C would have run her FULL character proc against a non-player struct: a second copy of her sprite from bogus state, and her per-frame cel streaming DMAing from garbage addresses. The trampoline now gates the Saturn branch on the two real player slots (`$1000`/`$1080`) and self-clears anything else, exactly like the projectile placeholder. Suite green incl. mirror KO + 4 stress runs. |
| 0.11.10 | saturn: `33e683c0…`(vis)/`421bdb6c…`(hid); REFsaturn: `671f6b14…`(hid) | `a022296` | **WRONG HIT SFX FIXED** (field report: a "Sonic ring"-ish tone on hit, trivially reproducible in a Saturn mirror with LP/LK). My own v0.11.1 regression: the interpreter's CMD-sound stub compares the script's sound argument against the mapping table, but the NO-MATCH path fell through into the shared `sta $78`, so every argument we deliberately leave UNMAPPED (her hit-reaction args `0x05/0x11/0x12/0x16` — the engine already plays those sounds itself) was written to the one-shot sfx slot RAW and played as whatever effect that id happens to be. Traced live: a mirror LP hit produced `SFX $78 <= 12` from our stub right as the victim entered act 0x12. Unmapped arguments are silent again (matches branch to the store; the fallthrough skips it), verified against a vanilla hit's sfx pattern. The CMD stub also outgrew its 0x80-byte slot, so the DMA stub moved to `$E8:2A00`. Suite green. |
| **0.11.11** | saturn: (vis)/`ac2186fd…`(hid); REFsaturn: (hid) | (this) | **SCREEN-WIDE GRAPHICAL CORRUPTION FIXED — reproduced, root-caused, proven.** The maintainer's clue (survives a round, gone by the win screen) said the damage sat in VRAM that is only rebuilt at match load. Caught live with a calibrated corruption detector (vanilla's own animation moves ~4% of sampled VRAM; corruption moves 85%+): the offending transfer is `VRAM 6000 <- DD:0D40 len 0000`. Two compounding faults: (1) **cel record 0 is her "no cel" sentinel** (`40 0D DD 00 00` — a live Super S address with size 0) and the builder SKIPPED rebasing zero-size records, leaving a Super S bank; (2) SMS's engine does **not** skip such a record — and a DMA length of 0 means **65536 bytes** on the SNES, so it wipes all of VRAM from a garbage source. It fires whenever a pose resolves to cel 0 — which is **six of her poses (0x7E-0x83)**, the invisible frames used by the hit/throw reaction states, hence "always after a hit". No vanilla character has a single pose pointing at cel 0, which is why the sentinel is harmless for them. Fix: record 0 now points at a real, cel-sized run of zeros in bank `$EE` (build-time asserted zero-filled), so those frames render blank — Super S's intended "invisible" — with no oversized transfer. Verified: 6 mirror stress seeds that all corrupted before now play full matches clean, while the same detector still trips on 0.11.10. Suite green + the 0.11.10 sfx fix re-verified (0 spurious writes). |
| **0.12.1** | saturn: `155b730e…`(vis)/`8c970ec6…`(hid); REFsaturn: `f26a7eb3…`(hid) | (this) | **REPORT-CARD PORTRAIT COMPLETE** — art, layout and palette. Three findings made it work. (1) **The composition is per-character**, not universal (census: Moon 18 sprites/66x64, Mercury 26/63x64, Mars 16/64x64, Uranus 31/71x72), and the list pointer is not a stored literal — the renderer reads it from the portrait object's own fields `+0x64/+0x66` every frame at `$C0:9E86`. Her art needs more room than any SMS layout offers (x 8-96 / y 40-120 vs the vanilla box x 19-90 / y 48-120), which is exactly the clipping the maintainer reported, so she now gets her OWN list: 67 8x8 sprites/67 tiles (only cells containing art cost anything), substituted by a stub at `$EE:CA00` gated on the pointer being the card's (`$9F:CBEC`) AND the slot's Saturn flag. (2) **WRAM-mirror trap**: `$14` becomes the emitter's data bank and the emitter stores the OAM shadow with plain absolute stores, so handing it bank `$EE` (pure ROM, no WRAM mirror) sent every sprite to ROM and the portrait vanished entirely — fixed by passing the `$AE` alias of the same ROM. (3) **The palette must be re-seeded every frame**: CGRAM is DMA'd whole from the `$7E:0500` shadow, a one-shot copy is overwritten by the engine's own refill, and that refill is invisible to write callbacks; the list stub now re-seeds row 8 (`$7E:0600`) on every drawn frame. Verified in-emulator: art pixel-exact vs the capture, CGRAM `$100-$11F` == our palette and the ONLY CGRAM bytes that differ, and a card won by Uranus on the same ROM still draws the vanilla list `$9F:CBED` with vanilla colours. `SATURN_PORTRAIT` is now ON by default (`=0` to opt out). **(4) The card carries no player identity** — caught before shipping by testing a P2 win: it builds the winner's portrait through the `$1000` slot and uploads to VRAM `$0000` whoever won, so both obvious keys (the object slot, the upload destination) are constants. Gating on them put Saturn's face under a "2P WIN" banner in a Saturn-vs-Uranus match. The winner is `$7E:1E14` (1 = P1, 2 = P2), found by diffing all 8 KB of WRAM at the card between a P1 and a P2 win; both hooks now gate on it. Acceptance: P1-Saturn win -> her list+palette; P2-Uranus win with P1 Saturn -> vanilla list+palette; P2-Saturn win -> her list+palette. |
| **0.12.2** | saturn: `de7fd03c…`(vis)/`c446cdba…`(hid); REFsaturn: `18bbb005…`(hid) | (this) | **NO PUSH COLLISION — FIXED** (field report: Saturn walks straight through the opponent; hitboxes still applied). A builder layout bug, not an engine one: bank $F0 wrote her 48-byte COLLISION block at `0x8910` and the projectile hitbox blob at `0x8920`, so the projectile boxes landed 16 bytes into the collision data and destroyed entries 2-5 — entry 2, the one both fighters actually use in neutral (`+0x42 = 02`, confirmed live for Saturn AND Uranus), became all zeros = no push box. Collision data now lives at `0x8960` and every data block in the bank is asserted pairwise-disjoint at build time, so this class of overlap cannot recur silently. Her six boxes now match Super S byte-for-byte. Suite 42/42. |
| **0.12.3** | saturn: `33495fe2…`(vis)/`86e2d5dd…`(hid); REFsaturn: `3679d99e…`(hid); +stage: `…-stage.sfc` | (this) | **CARD PORTRAIT: SCRAMBLED TILES FIXED** (field: her win portrait is random tiles, different every match — seen in 1P-vs-COM and 2P VS alike, neither reproducible in the harness). The symptom decomposes: the SPRITE LIST is re-read every frame and substituted fine, while the TILE BLIT ran ONCE at card-build time gated on the winner (`$7E:1E14`) — so when the winner is not latched that early, her 67-sprite layout draws whatever the portrait VRAM window still holds (leftover tilemap data), which is exactly "different every time". The blit is now a shared idempotent routine (`$EE:CB00`, destination via `$7F:F104`, scratch in `$7F` not DP since the per-frame caller sits inside the sprite renderer) called by BOTH hooks, with a marker (`$7F:F105`) so it happens exactly once per card: the card-build hook clears the marker and blits if it can, and the per-frame hook rescues it on the first card frame otherwise. Proven by simulating the failure — blanking `$1E14` at the card-build hook so only the rescue path can work — after which the tiles and palette still land byte-exact. Suite 42/42. Also ships `tools/saturn/build_saturn_stage.sh`, the committed recipe for Saturn + the Pluto-slot stage PoC in one ROM. |
| **0.12.4** | saturn: `80263f9e…`(vis)/`eac07435…`(hid); REFsaturn: `ebc01725…`(hid); +stage variant | (this) | **CARD PORTRAIT, SECOND PASS — the destination was the real fault.** 0.12.3 made the blit self-healing but the field still showed a mosaic, with the decisive clue that the stray tiles belong to the SHELL character ("select Uranus with L+R and a few tiles are definitely Uranus"). That means the vanilla upload landed and ours did not, under our own 67-sprite layout. Cause: the portrait loader is called **five times per card** and the wrapped call site does not always receive the portrait window — a destination of `$7800` is logged in a normal card. The wrapper blitted her tiles there and still set the done-marker, which suppressed the per-frame rescue. Fix: the card-build wrapper now ONLY resets the marker; the per-frame hook performs the blit and always targets VRAM `$0000` (measured: the card builds the winner portrait there whoever won), so a wrong destination is impossible. Verified both normally and with the winner blanked at build time; tiles and palette byte-exact in both. Suite 42/42. |
| **0.12.5** | saturn: `06252268…`(vis)/`2a0ae4db…`(hid); REFsaturn: `2b762c40…`(hid); +stage variant | (this) | **CARD PORTRAIT — ROOT CAUSE: THE GATE ONLY EVER MATCHED ONE SHELL.** The sprite-list hook required the loaded pointer to be `$9F:CBEC`, *Uranus's* portrait list. But Saturn is summoned with L+R over ANY of the nine slots, and the card draws the SHELL character's list — so for every shell except Uranus the gate failed and the card rendered that character's untouched portrait, which is exactly what the field reported. (The earlier garbled-mosaic reports were the Uranus case, where the gate passed and only the tiles were missing — two different symptoms of the same over-narrow key, which is why chasing timing and destinations kept half-explaining it.) Found by shipping a gate-less diagnostic build (`SATURN_PORTRAIT_FORCE=1`): the shell portrait STILL appeared, proving the hook was not acting at all rather than acting on bad inputs. Fix: key on the pointer's BANK (`$9F`) only — measured safe, since across a full boot-to-card run `$C0:9E86` loads exactly one pointer, the card's, and nothing in-match reaches that renderer. Verified with two different shells (Uranus AND Moon): our 67-sprite list, tiles and palette all byte-exact on the card. Suite 42/42. |
| **0.12.6** | saturn: `f555f2ce…`(vis)/`d1c99cdd…`(hid); REFsaturn: `b9b4347f…`(hid); +stage variant | (this) | **BLACK CARD FIXED + STAGE LAYERS RE-CUT.** (1) Field: Saturn's card is black with correct music, then renders correctly for a few frames on exit. The blit force-blanks to do its DMA and restores the INIDISP it saved — if it runs while the screen is legitimately dark (brightness 0 during a fade) it saves 0 and hands the screen back black, and nothing else rewrites that register on a static card, so it stays black until the player leaves. It now refuses to restore a blank INIDISP and hands back full brightness instead (a fade in progress overwrites it next frame anyway). Measured `INIDISP=00` around that phase, which is what made this the leading candidate. (2) Stage: the ground was hidden behind the palace. Super S composes this stage ACROSS both planes using per-tile priority — map0 holds sky (behind the palace) and ground (in front), the ground being exactly the high-priority cells, rows 10-13. SMS cannot copy that, because a high-priority BG tile also draws over the fighters (the original occlusion report). So the layers are re-cut rather than re-prioritised: every high-priority cell of map0 is MOVED onto the other tilemap and the priority bit is stripped everywhere, giving front = palace + ground, back = sky — correct order with no priority bits, so the fighters stay in front. Verified: card correct with TWO shells (Uranus and Moon), suite 42/42. |
| **0.12.7** | saturn: `dd064bfa…`(vis)/`2a544c3c…`(hid); REFsaturn(on REF v.2): `9ba883f5…`; +stage | (this) | **SFX MAPPING CORRECTED — by parsing which ACT requests each sound arg, instead of inferring from when a sound was heard.** Her scripts carry Super S sound ids that our CMD stub translates; dumping arg->act for every script gives the ground truth: **arg `0x22` is requested by act `0x24`, her WIN POSE** — it is her laugh. v0.11.1 had mapped it to the dash whoosh `0x2D` alongside `0x06` (which really is the dash, act `0x26`), which is exactly the field report "her win sfx is the backdash sound". Now unmapped/silent, because silence beats an obviously wrong effect while the real voice sample is unported. **Args `0x23`/`0x24`/`0x25` are requested by her SPECIALS** (acts `0x6E/0x6F`, `0x3E/0x6A/0x6B`, `0x3F/0x6C/0x6D/0x70-0x75`) = 236P, 214P and j.632K — left unmapped since v0.11.1 on the assumption the engine plays the starter sound itself, which the field disproves; they were silent. Mapped to the heavy whoosh so the throws are audible. All three are VOICE samples in Super S, so faithful audio still needs the sample import. Suite 42/42. |

| **0.13.0** | saturn: `0aa44e7b…`(vis)/`aefa5c12…`(hid); REFsaturn(on REF v.2): `3b835d0c…`; +stage `fe98dfe1…` | (this) | **HER REAL VOICE (task #44).** Her four Super S samples now play in SMS: win laugh, 236P, 214P, j.632K. Loading the bank turned out to be only half of it — the earlier scoping note ("she keeps the same ids and simply speaks in her own voice, no id remapping needed") was right about the bank and wrong about the DIRECTORY. Measured: sound id `49 + (charID-1)*5 + k` resolves to BRR directory entry `48 + (charID-1)*8 + k` (+4 when the NMI sets bit 7 for P2), and that directory is a complete nine-character table resident from BOOT at ARAM `$34C0 + (charID-1)*32` — never refreshed per match. So her bank under a shell's ids would play her audio cut at the shell's offsets. Also answers the Phase-1 open question: P2's bank reaches `$DB00` because `$C0:EC5E` is a RELOCATING uploader that adds dp `$10` to every block destination — the same knob that steers her directory block from `$34C0` to `$34D0`. Implementation: five IPL streams in a tenth appended bank, reached through five spare records in the audio table (ids 47-51 land in the 64-byte zero run at `$C0:EE00`, proven unread across a full boot→select→match→KO→win session before being claimed). She uses CHAR 1's ids on whichever side she plays and the build overwrites char 1's half-record for that player only — the halves are per player, so a P1 Moon cannot coexist with a P1 Saturn and a P2 Moon reads the untouched half. One fixed id set covers all nine shells with NO per-shell code. Non-Saturn loads restore char 1's record (DIRTY flag `$7F:F107/F108`), because the boot-resident directory would otherwise leave Moon buzzing for the rest of the session. Her CMD args `0x22-0x25` map to ids 49-52 via a bare `sta $78,X` — X is already the interpreter's object base; an `ldx $88` first (copied from the proc helper, where $88 IS the object) sent her voice out of P2's slot while she was P1. The arg→sample mapping is not by ear: Super S's own command table (`$80:FC32`→`$FC48`) gives cmd `$22/$23/$24/$25` → directory entries 30/31/32/33, which is exactly our ordering — and explains why arg `0x25` also fires on the ground specials' second phase (Super S does that too). Acceptance: voicecheck 8/8 both players, voicerestore 4/4 both halves, voicefire shows the right ids in the right slot, smoke 228/228, regression ALL PASS (57). NOT yet listened to — the cues' placement in play is a field question. `SATURN_VOICE=0` builds without it. |

| **0.13.1** | saturn: `f7555a61…`(vis)/`258f591e…`(hid); REFsaturn(on REF v.2): `ccf7240b…`; +stage `b2795457…` | (this) | **HER CHARACTER-SELECT LINE ("Yoroshiku").** Field: the v0.13.0 in-match voices are confirmed right ("a bit weird but definitely the right ones"), so #44 closed and this is the nice-to-have on top. Located in Super S at ROM `$EC:C12F`, 2610 bytes, by diffing every voice start's SRCN across select→confirm→versus→match for two characters: the only character-dependent sample is a SHARED streamed slot (ARAM `$4D00`, dir entry 16) whose LENGTH changes with the character. Ruled out first, by measurement: no per-character bank is resident at Super S's select screen, and moving the cursor streams nothing in. Plays at PITCH `$03FE` = 7984 Hz, same ~8 kHz as the rest of her voice. **Delivery was easy because SMS already does exactly this**: on confirm, `$C0:AE4C` indexes `$C0:AE75` (bank id = 21+charID, one sample to ARAM `$B700` + a 4-byte directory write) and `$C0:AE7F` (sound id 48/53/58/…). Every one of those ids resolves to directory entry 48 whose start is `$B700`, and the sample is a one-shot ended by its own end flag — so she needs NO id change and NO directory patch, just the bank swapped. Player identity is not in `$1B1E` (that is the CHARACTER — the card-portrait trap again), so the three per-player writers of it (`$C0:AEF3`/`$AF34` = P1, `$C0:AF12` = P2) each record the player in `$7F:F109` and the bank hook reads it. Ordering confirmed by accident: poking the Saturn flag by hand FAILS because the confirm stub re-decides every press — which proves it runs before this load, so held L+R is already latched here. Acceptance: her bank for the armed player and vanilla for the other, on TWO shells (Uranus and Moon), both player slots, her 2610 bytes byte-identical at `$B700`, and nobody-armed loads pure vanilla; plus the 0.13.0 suite re-run green (in-match 8/8 x2, restore 4/4 x2, smoke 228/228, regression 57). |

| **0.13.2** | saturn: `2e572a6e…`(vis)/`5baa575e…`(hid); REFsaturn(on REF v.2): `8f44dbc1…`; +stage `03a77692…` | (this) | **HER MOVELIST (task #41).** Own list at last: SAILOR SATURN + サイレンス バスター (236+P), プレス クラッシャー (JUMP中 632+K), デス リボン レボリューション (214+P). Required decoding SMS's SECOND codec ($C0:916B, the movelist one — Super S has neither it nor these tilemaps, so nothing could be lifted): 16-bit control word LSB-first, bit 1 = literal, bit 0 = back-reference in a short (2 length bits + byte distance) or long (16-bit word: 3-bit length, 13-bit distance, escape byte where 0 ends the stream) form. tools/saturn/sms_lz.py decodes and encodes it; all nine vanilla lists decode to exactly 0x800 and both encoders round-trip. The trap: the refill happens INSIDE the bit fetch, so the 16th bit's payload lands AFTER the next control word — a lazy refill decodes 0x14F bytes perfectly and then desynchronises, which looks like a data bug; a live trace of the ROM's own decoder named it. Font: BG3 CHR base is word $5000, read from $210C after inference kept contradicting itself; roman caps are a REDUCED alphabet (no K/Q/X/Z), katakana are gojuon at $100+(i//16)*$20+(i%16), dakuten reduced, small kana $180-$186, and the arrows are only ⬇↘➡ — left/up are flips, which for a 2-tile glyph also swap its halves. Her tilemap is built from MOON's (the only vanilla 3-move list) so the frame already fits, keeping the shared 右向きの時 line. **Body text is attribute $2D, not $0D** — $2105 sets the mode-1 BG3-priority bit, so an unprioritised BG3 tile renders behind the stage; the first build's title showed and its body did not, visible only on a bright stage. Wiring: 595 bytes at $F9:3400, with $C0:8B59/$C0:8B81 hooked per player. Acceptance: right bank on TWO shells with the staged tilemap byte-identical to the authored one, vanilla untouched when nobody is armed, in-game screenshot with all three moves, regression 57, smoke 228/228, voice + select voice green. |

| **0.13.3** | REFsaturn+stage: `746183bd…` | (this) | **THE PORTED STAGE'S JUMP SLIDE FIXED (#43).** Root cause measured, not guessed: objects are placed at the FULL camera (dummy's top sprite Y tracks camY 1:1 with her idle pose held constant), while the scroll routine the port borrowed from stage 0 (`$C0:B40A`) gives the ground plane only camera/4 — so a 12 px jump drops the fighters and their shadows 12 px and the ground 3, and undoes it on landing. Vanilla stage 0 does exactly the same (its trace, OAM and WRAM are byte-identical across the jump); it is invisible there because that stage's ground is flat grass with no feature at the fighters' feet, whereas the ported stage has a hard perspective floor line right there. Fix: stage 2's own vortex routine at `$C0:B454` — the only routine that stage selects — is rewritten in place (35 B, ahead of its HDMA table at `$B4C1`) with B40A's horizontal treatment and stage 2's original **1:1 vertical**; the pointer at `$C0:B32F` is no longer repointed. Verified: BG1 vscroll follows camY 1:1, background pixel shift +3 → **+11** = the sprites' +11, scene `$00` byte-identical on the same ROM, regression **57/57**. The horizontal rate is the same question and was measured too (ground moves camera/4 while walking) — left alone deliberately: also vanilla, not in the field report, one `lsr` pair from 1:1 if wanted. Detail: `supers_assets.md` §#43. |

| **0.13.4** | REFsaturn+stage: `0c3403af…` | (this) | **PALACE PARALLAX (#43, field round 2).** The slide fix held; what remained was the palace moving with the ground instead of a fraction as far. Measured Super S itself (`probe_supers_stagejump.lua`): its palace band shifts **+4 px** at a jump apex while its ground stays put — done on ONE plane, per SCANLINE, by enabling an HDMA channel onto `$210E` (BG1VOFS) for the duration of the jump. SMS has no such machinery (a vanilla stage runs no scroll HDMA at all), so the port splits by PLANE instead: Super S marks the ground — and only the ground — with the priority bit, in a clean band of whole rows, so `PLANE_SPLIT` puts **the ground alone on BG1 at camera 1:1** (fighters stay planted, better than either original) and **sky + palace on BG2 at camera/4** (Super S's rate). Horizontal is camera/4 on both, so they cannot drift sideways. Supersedes MERGE_GROUND + SWAP_MAPS. Result: palace **+3** vs Super S's +4, ground 1:1 by register. One trap paid: the palace is in the SECOND source map and the first (sky) has no blank cells, so a fill-the-gaps merge threw the whole palace away and rendered bare sky — nothing errored, only a screenshot caught it. Regression **57/57**. |

| **0.13.5** | REFsaturn+stage: `6239b8ea…` | (this) | **PALACE TRANSPARENCY + THE HORIZONTAL DRIFT (#43, field round 3).** Field on 0.13.4: scrolling right, but black blocks around the palace outline and the furthest layer "again left shifted". Root cause is one constraint, not two bugs: Super S composes this stage in THREE depths (sky BG1.0 < palace BG2.1 < ground BG1.1) and gets away with it because **its fighters are OBJ priority 3**; SMS's are **OBJ 2** (measured), so a priority-1 BG tile draws over them — the original occlusion report, and why the port strips priority. Stripped, two depths must hold three layers, so one pair shares a plane AND a scroll rate: palace+ground gives the parallax bug (0.13.3), sky+palace gives the black blocks (0.13.4), sky+ground is impossible. 0.13.5 keeps sky+palace and fixes transparency in the DATA — where a palace tile is partly opaque the sky it covers is baked in (`TileComposer`: 111 tiles from the 272 slots the tileset leaves unreferenced; sky pixels remapped to the nearest colour in the palace's palette row, the two ramps nearly identical). Black pixels over the palace **2141 → 270** (the rest is the stage's own dark art). Compositing is only sound because the pair shares a plane — split them and the "sky cell behind this palace cell" stops being constant, which produced holes when tried. Drift: both planes now scroll **h = 0** (Super S's own rate for its sky+ground plane) and the palace is shifted **2 cells left in the data** to land where its camera/4 put it — palace band verified against a Super S capture at offset **+0**. Regression **57/57**. Trap: a 64x32 tilemap is TWO 32x32 screens (+0x800), not 64-wide rows — reading it wrong made three analyses of this stage disagree. Remaining gap vs Super S: no horizontal parallax, and the sky rides the palace's vertical rate (3 px at an apex); both return if sprites are raised to OBJ3 on this stage — hook point already located (`$7E:0200` shadow, DMA kick `$80:8476`). |

| **0.13.6** | REFsaturn+stage: `50645f06…` | (this) | **THE STAGE, DONE — and v0.13.5 REVERTED.** v0.13.5 broke scrolling speed and input in the field; it and every clever workaround before it are deleted. The maintainer's steer found the answer: **SMS already ships this stage** (scene 1 = its own Silver Millennium), so read what it does instead of reasoning about what SMS "cannot do". It composes exactly like Super S — sky BG1.0, palace BG2.1, ground BG1.1, fighters drawn OVER the priority-1 ground. That contradicted the port's founding assumption, so it was measured: SMS's fighters are at **OBJ priority 3 on nine of ten stages** and at **2 only on stage 2 — the slot the port targets**. Source: the scene script has FOUR parts, not two (`[records..FF][palettes..FF][third list..FF][$6F][$8F][$A2]`, read at `$C0:85C8-85FC`); `$8F` is the sprite-attribute byte (`0x18` = OBJ3, `0x10` = OBJ2), mirrored into each player's `+0x08`. The port never carried the tail, so the art ran under the one configuration that puts the fighters *below* the background's priority tiles — which is why the castle covered them, why the priority bits were stripped, and why three layers then had to share two depths. Now: `$8F` 0x10→0x18 and the scroll entry repointed to **`$C0:B42F`** (SMS's own Silver Millennium routine), with **no** priority stripping, layer merge, plane swap, tile compositing or rewritten scroll code. Matches SMS's own version measurement for measurement: BG1 `0,0` fixed, BG2 `16, camera/4`, sprites priority 3, 270 black pixels over the palace (identical). Only `$8F` is copied — porting the third list or the other tail bytes hangs the round load (they are SMS-side ids). Regression **57/57**. |

| **0.14.1** | REFsaturn+stage: `4a398add…` | (this) | **SHE ARRIVES BEFORE THE ROUND (the last extended-scope item).** Field ask: the shell must not be visible while the fighters walk in — the swap moment was "distracting and downright penalizing". Measured on v0.14.0 (`probe_sms_transform_timing.lua`): the latch arms at f=1809 (the effects DMA), the round goes live at f=1855 with the ENTRANCE act `$22` running to f=2040, and the helper's gates only let the transform through at **f=2099** — so the shell played the entire entrance and Saturn popped in exactly as control was handed over. `EARLY_TRANSFORM` drops the `$1E04` (intro-sequencer) gate and accepts act `$22` alongside act<3, **keeping** the latch and the live-round gate, which are what actually prove a real fight load. It also **preserves the act** across the transform (pha/pla around the state clear) so **her own entrance script runs from step 0** — the nice-to-have, not just the must-have. Result: transform at **f=1856**, one frame after the round goes live, 243 frames earlier; she is on screen for STAGE 01 / FIRST BATTLE / READY / GO. Verified: regression 57/57, smoke PASS, a full randomised mirror match ends cleanly (no wedge), and **story mode is unaffected** — `charsel10` in `vscpu` mode is ALL PASS and byte-identical to v0.13.9, which matters because the `$1E04` gate existed to protect the story sequencer. |

| **0.14.2** | REFsaturn+stage: `ee20d99b…` | (this) | **STORY GUARD** (maintainer's call: "we can just prevent Saturn from being selectable [in story] … already Uranus, Neptune and Pluto are not selectable in story mode"). The DMA stub now refuses to arm when `$7E:008D == 1` (story), and **forces the latch to 0** rather than merely skipping, so a stale arm from a previous VS round cannot survive into a story fight. This removes the only risk the v0.14.1 early transform carried, since the `$1E04` gate it drops existed to protect the story sequencer. Verified: **VS (`$8D=00`) and practice (`$8D=04`) still transform** — and still EARLY (VS: first `id=1C` at f=2100 with act `$22`, against f=2325 on v0.13.9, so the entrance gain holds outside story too); story refuses; regression 57/57; smoke PASS; randomised mirror match clean. ⚠ **CORRECTION (0.14.6): every mode label in this row is wrong.** `$8D == 1` is **2P VS**, not story (story is 00), so this guard blocked 2P VS — field bug 2 — and never touched story — field bug 3. The "VS (`$8D=00`)" that "still transforms" was story. And `probe_sms_lrboth.lua` navigates to row 1 = 2P VS, so its FAIL here was reporting the real bug, not "the guard working by design"; it PASSES from 0.14.6. |

| **0.14.3** | REFsaturn+stage: `f1611041…` | (this) | **FIELD FIX: inputs dead in 2P VS and 1P-vs-COM.** Field on v0.14.2: training perfect (immediate, no shell frame, all correct), but in VS and vs-COM she appeared with **no entrance animation and no inputs — until she was hit**, after which commands worked. Diagnosis from that last clue: v0.14.1 preserved the entrance act `$22` across the transform so that HER entrance script would play, but her act-`$22` script never completes, so the intro sequencer never hands control over; a hit is what forces her out of the state. Training was clean only because it has no entrance. **Fix: stop preserving the act** (`EARLY_KEEP_ACT=0`) — the transform still happens during the entrance, she is still visible from the first frame with no shell, but she stands at neutral instead of running an entrance that cannot finish. Reproduced and verified headless (`probe_sms_inputcheck.lua`, new): on v0.14.2 the act stays `22` with x frozen at `$80` for 24+ frames until act `17` (she is hit); on v0.14.3 the act goes `00→01` and x runs `80→88→94→A0` within 18 frames of holding RIGHT. Regression 57/57, smoke PASS, randomised mirror clean, input OK in both practice and vs-COM. **The entrance animation is dropped as not achievable** with her data — the must-have (on screen before round start, no shell) stands. |

| **0.14.4** | REFsaturn+stage: `8d2d33be…` | (this) | **FIELD ROUND: three reports, one reproduced, none fixed yet — read this before touching the port again.** Behaviour is v0.13.9's/v0.14.3's (regression 57/57); what this build adds is the *investigation*. (1) **THROW CORRUPTION (the important one, present since long before this session): REPRODUCED HEADLESSLY** — `probe_sms_throwbug.lua` (new) puts a Saturn dummy in practice, has P1 throw her, and captures it: acts `1C→1D→1E→20` run normally, her cels DO stream (`$F3/$F4`, valid lengths), stage-tile VRAM is untouched (0/128 samples) for a normal throw, and her downed sprite is nevertheless drawn from tiles that are not hers (another character's hair is visible in it). RULED OUT: cel-record validity (115 records, banks all rebased, no oversize, only record 0 zero-size), cel sizes (her max 0x900 vs SMS's own 0x9a0), dropped act-table entries (none), missing cel DMA, and — tested and disproven — the blank-cel size theory (poses `$7E-$83` do use the sentinel and it was only 0x480 against a 0x900 max payload, but enlarging it changed nothing). Note the `+0x18` byte reads `$F8` during the throw; that is the pose-record CLASS, not a pose index, and no SMS character's pose table reaches `$F8` either, so it is not an out-of-range index. (2) **2P VS: shell not replaced although her sfx play** — not reproduced yet; the harness's "vscpu" flow is mode `$8D=00` and works, so the failing case is specifically two human players. (3) **STORY: the `$8D`-based guard does NOT hold in the field.** The maintainer's fallback — only arm on Uranus/Neptune/Pluto shells, which story cannot select — is implemented behind `SHELL_GUARD` but **defaults OFF because it does not work yet**: in the DMA stub nothing arms at all (the player struct is not populated at the effects transfer), and in the helper it blocks every shell including 6/7/8, which is unexplained. Next step: log `$00,x` at the helper's gates and find what the id actually reads there. |

| **0.14.5** | REFsaturn+stage: `c74b2cdc…` / hidden: `b09f28da…` | (this) | **STORY LOCK, DONE PROPERLY — field bug 3 closed.** `SHELL_GUARD` now **defaults ON**: the helper transforms only when the shell's charID is **6/7/8** (Uranus/Neptune/Pluto), the three the game's own story roster cannot reach. This locks story *structurally* rather than by asking what mode the game thinks it is in — which is what the field defeated on v0.14.2. **The previous session's "it blocks EVERY shell including 6/7/8" was a harness artifact, not a code fault.** The measurement it called for (`tools/saturn/probe_sms_shellguard.lua`, new — an exec hook on the guard's own `lda $00,x`) shows D=0, X=`$1000`/`$1080` and `$00,x` reading the true shell (`06` for a Uranus shell, `04` for a Jupiter one); the guard had always read the right byte. What was wrong was the *flow*: it pokes `$1B40` once and then mashes A/Start through a second selection screen that reuses that cursor, so the fight loaded charID **1** while the probe believed it had selected 6. Measured on this build — practice 6/7/8 → transforms, practice 1/4/9 → refused (`xforms=0`), vs-COM 6 → transforms, vs-COM 1 → refused, story → refused; and with `STORY_GUARD=0` the story latch still **arms** and the guard refuses it every frame, which is the proof that the shell test alone is sufficient. `STORY_GUARD` is kept as a second layer. ⚠ **CORRECTION (0.14.6):** the mode labels in this row are swapped — `$8D=01` is 2P VS, not story, so the rows this build recorded as "story" were 2P VS and the ones recorded as "vscpu" (row 0) were story. The shell-guard result stands exactly as measured (story with a legal shell IS refused, which is what closed bug 3), but the claim that `STORY_GUARD` covered the forced-charID-6 residual was false until 0.14.6 repointed it to `$8D == 0`. Side effect, welcome: with the guard on, a non-6/7/8 opponent no longer transforms alongside her (previously, holding L+R through both practice confirms turned the dummy into Saturn as well — that is by design per cursor, and with a Uranus dummy it still gives a Saturn mirror). Regression 57/57. **Naked-eye tell: only Uranus/Neptune/Pluto respond to L+R now.** |

| **0.14.6** | REFsaturn+stage: `876983ff…` / hidden: `84c963c0…` | (this) | **FIELD BUG 2 FIXED — and it had the SAME root cause as bug 3: one wrong constant.** `$7E:008D` is **0 = story, 1 = 2P VS, 2 = 1P-vs-COM, 4/5 = training** — MEASURED from the game with `probe_sms_menurows.lua` (new), which reads two independent discriminators per menu row: how many cursors move, and which charIDs each can reach. Row 0 = one cursor, roster 1-5 only = story. Row 1 = TWO independent cursors, full roster 1-8 = 2P VS. Row 2 = one cursor + fixed opponent = vs-COM. `docs/annotations.md` carried both "0=VS, 1=Story" (from the training Lua — **wrong**) and "VS 1P-vs-2P = 01" (right); the story guard was written against the wrong one. So `STORY_GUARD`'s `$8D == 1` test had been **blocking 2P VS** (bug 2 — the flag still gets set by the char-select confirm hook, which is what the sound remap and the select voice key off, hence "her sfx play and the confirm sfx is hers"; the palette is hers for the same reason on any mode that DOES transform) **and never touching story** (bug 3). Fix = one byte, `cmp #$01` → `cmp #$00`. Bug 2 is now reproduced headlessly for the first time (`probe_sms_shellguard.lua MODE=vs`, which drives a REAL two-pad VS — P1 and P2 each confirm with their own pad, which no previous probe did): on v0.14.5 it reports `gate_hits=0`, i.e. the helper is never even reached because the latch was forced to 0. Acceptance on v0.14.6 — vs / vs-COM / practice: shells 6/7/8 transform, 1/4 refused; story: refused for every shell **and** with charID 6 FORCED in (`gate_hits=0` — the mode guard now covers the one residual the shell test cannot). Two-pad coverage: L+R on P1 → P1 only, on P2 → P2 only, on both → Saturn mirror. Regression 57/57. |

| **0.14.7** | REFsaturn+stage: `c4f51fe7…` / hidden: `d45dc1da…` | (this) | **THE THROW CORRUPTION IS FIXED (field bug 1) — a third nine-wide table.** When a character is thrown, the THROWER's script drives the VICTIM's pose: `jsr $C1:03DC` returns the *other* object's base, so `$0E` is the victim's charID, and `$0E*2` indexes a pointer table at **`$C1:0881`** that has exactly TEN entries — idx 0 dead (the read is 1-indexed) and idx 1-9 the nine characters' 21-byte pose lists. Saturn is id **0x1C**, so the read lands 0x38 bytes past the table, *inside character 2's pose data*, and the "list pointer" is two bytes of pose values. Measured consequence, end to end: garbage poses (**`$F6`**, against her table's last real pose `$83`) → an out-of-range index into her pose→spritelist table in the OAM layer, whose first byte is a sprite **COUNT** → the emitter writes **102 identical sprites and floods OAM (127 visible, against ~50 for the same throw with a vanilla dummy)**. That is the "random tiles". **Fix**: hook the list read at BOTH sites (`$C1:0740` normal throws, `$C1:0C5C` command/carry — byte-identical in shape) and, for victim id 0x1C only, read her own 21-byte list. Her list is **LIFTED, not authored**: Super S's twin table at `$C1:0883` has ELEVEN entries and its idx 10 is hers, and the nine shared lists are **byte-identical across the two games**, which is what proves the step semantics match. A/B (`probe_sms_throwoam.lua`, new — the same throw with the dummy as Saturn and as the plain shell): v0.14.6 Saturn = poses `95/78/46/F6`, MAX-SPRITES **127 OAM FLOOD**; v0.14.7 Saturn = poses `73/74/75/6F/70`, MAX-SPRITES **57 healthy** against vanilla's 60 — and those are list indices 12/13/14/8/9, exactly the indices vanilla uses into its own list. Stage-tile VRAM 0% changed. Regression **57/57**, including `base-spd-uranus-toss32` / `base-spd-jupiter-carry30`, the two command-throw tests that cover the second hook site's vanilla path. ⚠ **Not exercised in this build: Saturn as the victim of a COMMAND throw** — RESOLVED IN 0.14.8 once the maintainer supplied the minimum SPD input (6 2 4 8 + P at contact); the fix is correct there too and the pre-fix build corrupts 92% of the stage tiles. Two bugs paid for on the way, both caught by the A/B rather than by reasoning: a `plb` in a JSL'd stub pops the RETURN ADDRESS, not the saved DB (it stalled every throw, vanilla victims included), and **`lda long,Y` does not exist on the 65816** — `$BF` is long,**X**, so the read indexed with the thrower's object base and returned her list[0] every frame. |

| **0.14.8** | REFsaturn+stage: `3ea03a21…` / hidden: `b3524b04…` | (this) | **FIELD FIX: L+R on a DISALLOWED shell was still half-arming her** — "you don't get Saturn (correct) but you still get her confirm sfx, her palette on most tiles and her sfx". Cause: v0.14.5 put the shell restriction in the **helper**, i.e. at the transform, but the **FLAG** is set earlier by the char-select confirm stub, and the select voice, the in-match sound remap AND the effect-tile/palette override in the DMA stub all key off the FLAG, not off the transform. So an illegal shell armed everything except the one thing that was guarded. **Fix: apply the rule where the flag is armed.** (a) The confirm stub now reads the cursor's charID (`$0000,y`, where the visible variant already reads it) and only sets the flag for 6/7/8; (b) it records the confirmed charID per player in `$7F:F10A/F10B`, so the OTHER arming route — L+R held as the round loads, where the cursor is gone and the player struct is not yet populated — can apply the same test in the DMA stub, failing closed on a stale value. The helper guard stays as the last line. Measured A/B (`probe_sms_shellguard.lua`, which now reports flag/latch, not just the transform): v0.14.7 practice shell 1 = `SATURN=none` but **`flag=A5/A5 latch=A5/A5`** (the bug); v0.14.8 shell 1 = `flag=00/00 latch=00/00` (inert), shell 6 = `flag=A5/00 latch=A5/00`. Full matrix across vs / vs-COM / practice / story × shells 6/7/8/1/4/9 is correct, story refuses even with charID 6 FORCED (flag arms, latch does not — the mode guard), and 2P VS gives P1-only / P2-only / mirror for L+R on p1 / p2 / both. **COMMAND-THROW GAP FROM 0.14.7 NOW CLOSED**, using the maintainer's minimum SPD input (**6 2 4 8 + P**, 8 and P allowed on the same frame, at contact range — the suite's longer 6321478 motion comes out but its up-steps make Jupiter jump and it always whiffed). It confirms `$C1:0C5C` is the command/carry site (`site1=0 site2=136`) and reproduces the worse field symptom: **v0.14.6 = poses `20/E2/17/C2`, 127 sprites OAM FLOOD, stage-tile VRAM 92% changed**; **v0.14.8 = poses `02/01/07/76` (all inside her list), 51 sprites, stage-tile VRAM 0%**. Regression 57/57. |

| **0.14.9** | REFsaturn+stage: `03b73cdd…` / hidden: `76ba6d8c…` | (this) | **HER PROJECTILES GET THEIR OWN OBJ PALETTE ROW** — field report: fighting *against* Saturn, the projectiles and only the projectiles come out wrong. This was a knowingly-accepted tradeoff from v0.11.1, now removed. Mechanism, re-measured: both games pick a projectile's palette **per SLOT** — the setup routine writes palette 2 for slot `$1100` and 3 for slot `$1180` into the object's `+0x08`, then ORs the priority bits from `$8F` (giving the `$1A`/`$1B` measured live; OAM attr byte = `+0x08 << 1`, so palette = `+0x08 & 7`). Since v0.11.1 the transform overwrote CGRAM shadow row `$0640` = OBJ pal 2 with Super S's blue effects palette so her fireballs would not be fire-orange — but pal 2 is the **opponent's** projectile row too. pal 3 is not free either: it is slot `$1180`'s row, a *different* authored palette (verified by dumping both). Measured over a full match with projectiles firing (`probe_sms_objpal.lua`, new — it dumps all eight OBJ rows and accumulates a full 3-bit OAM palette histogram): only pals **0/1/2/4** are ever used by any sprite; rows 5 and 6 hold authored ramps that nothing drew, and **row 7 is all zeros in both a Saturn and a vanilla match — never loaded, never used**. Fix: her projectile procs select **row 7** (two immediates in HER copy of the setup routine, inside the ported PROJ block — the engine's own `$C1` copy that every vanilla projectile runs is untouched) and the transform's palette copy targets row 7 instead of row 2. Verified: her projectile `+08=1F` (pal 7), a vanilla Neptune projectile in the same match `+08=1A` (pal 2, unchanged); CGRAM rows 2 **and** 3 now identical to vanilla, row 7 carries her effects palette; her fireball is visually unchanged. Regression 57/57, throws still clean (normal + command), stress harness identical to v0.14.8 (clean, 6 suspect DMAs — HUD digit writes). *Observation, pre-existing and not introduced here:* OBJ rows 5 and 6 also differ between a Saturn and a vanilla match, on v0.14.8 as well; nothing drew with them in the sample, so it is recorded rather than chased. |

| **0.14.11** | REFsaturn+stage: `b180790a…` / hidden: `dacb1c65…` | (this) | **214P PROJECTILE FIXED — the effects DMA was sized from the SHELL, not from her.** Her 0x1040-byte effect sheet is staged over the shell's in `$7F:0000`, but the DMA that follows takes its length from the **shell character's own** sheet, and they differ: Uranus `$11C0`, Pluto `$10C0`, **Neptune `$0E60`** (measured at the kick site, dp+`$32`, D=`$0000`, `probe_saturn_fxdma.lua`). On a Neptune shell the last `$1E0` bytes — 15 tiles, `$113-$121` — never reached VRAM and kept whatever the previous match left there; her 214P travel pose is 12 sprites and **7 of them draw from exactly that range**, so the five 16×16 tiles survived and the seven 8×8 tiles vanished. That is the field report verbatim: *two disconnected blue pieces instead of one shape*, on Neptune, intact on Uranus — and it is why every build bisection came back "identical", since they all compared builds on ONE shell (HANDOFF trap #1). Fix: the DMA stub's armed path now also forces the length (`lda #FX_SHEET_LEN / sta $004305`, long store — DB there is the caller's). Safe in both directions, from the full round-load DMA map: P1 `$6A00`+`$1040` ends at word `$7220` and the next transfer starts at `$7300` (Pluto's own already reaches `$7260`); P2 `$7300`+`$1040` ends at `$7B20`, next starts at `$7C00`. Where a shell's sheet is larger, this also stops its leftover art trailing into tiles past hers. **Byte footprint: 7 inserted bytes + 9 `brl` displacements (each exactly +7) + checksum + version string — nothing else moved**, and the pre-fix rebuild reproduces `7db39c48…`/`3120d75a…` byte-for-byte. Verified: her sheet is byte-identical to `supers_lz`'s decoder output in VRAM on shells 6/7/8 (130/130 tiles; Neptune was 115/130), the composed projectile is one continuous flame, gate 46/46, regression 57/57. New gate check (`probe_saturn_fxsheet.lua`): her effect sheet must be **identical across shells** — sanity-checked against v0.14.8, where it fails. |

## Field verification, v0.13.2 [P 08-03]

- **Movelist: clean.** Her own list renders correctly in normal play — the
  priority-bit trap (`$2D` attribute) is confirmed fixed, on the maintainer's
  screen and not just in the harness. #41 closed.
- **Character-select voice: no regression.** v0.13.1's bank-id swap behaves in
  normal play, with no effect on the other characters' confirm lines.
- **v0.14.3 field round:** training good; **1P-vs-COM good**; **2P VS broken**
  (shell not replaced, though her sfx play); **Saturn still reachable in story
  via L+R** despite the `$8D` guard; and a long-standing **throw corruption**
  surfaced — her sprite becomes random tiles when thrown, and a command throw
  (Jupiter SPD+P) spreads it into the stage tiles.
- **Kanji font relocation (v0.14.0): clean** — no corruption seen anywhere in
  the field, so the block move and the repointed `$C3:BEF2` are sound.
- **Story mode with Saturn forced in (pre-guard): confirmed bad** — graphical
  corruption, unresponsiveness at the stage start, broken framing. The maintainer
  agrees she should simply be unselectable there, which v0.14.2 does.
- **The ported stage's jump slide (v0.13.3) is gone**, confirmed on the pad —
  leaving only the palace's parallax rate, fixed in v0.13.4.
- **v0.13.4 field round:** all scrolling correct; black masks on the palace
  outline and the furthest layer left-shifted at max scroll.
- **v0.13.5 field round: BAD BUILD** — "improved some of the rendering without
  being perfect and has broken scrolling speed, character input and more".
  Reverted; superseded by v0.13.6, which is simpler than any build before it.
- **Maintainer's steer that solved it:** SMS has its own Silver Millennium
  (scene 1), so its data answers every question the port was guessing at.
- **Not every Super S stage is worth porting**: the maintainer's call is that
  several look poor in SMS and only a few are worth adding. The port pipeline is
  per-stage (`SUPERS_SCENE`), so this is a selection question, not a code one.

## Field verification, v0.12.6 [P 08-02]

Maintainer testing, recorded because several of these close long-running items:

- **Win screen / card portrait: clean.** The INIDISP fix holds.
- **close 5HK is NOT a bug.** Super S also starts that move with a knee that
  becomes a kick depending on spacing and pushback, so the port is faithful.
  (The investigation is kept in the task history because it re-verified the
  whole normals chain: selection thresholds, act table, script bytes, and the
  pose->cel mapping.)
- **The stage's jump-slide is stage-specific.** No other stage slides on the
  same ROM, nor on the REF-stacked build — so it is our ported stage's
  configuration, not an engine-wide regression.
- **Taunts work with Saturn**, and the other patches behave on the stacked REF
  build.
- **AUTO/ACS still active on REF was EXPECTED**, not a bug: REF v.1 is patches
  1b/2/3/4/5/7/8/9/12/13/14 — patch 15 (Auto removal) was never part of it.
  **RESOLVED 2026-08-02: REF v.2** (`tools/build_ref_v2.sh`, ROM `6d79fb5f…`)
  = v.1 + patch 15, regression 57/57. `tools/saturn/build_refsaturn.sh` now
  builds on v.2 by default (`REF_VERSION=1` for the old base); REFsaturn
  v0.12.6 on v.2 = `372d2642…`. v.1 is left byte-identical on purpose.
- **Movelist**, refined: it shows mostly *Uranus's* list (not Jupiter's, as
  first reported) and is INCOMPLETE — two specials and no desperation. Tracked
  with the shell lesson from the card portrait: Saturn can be summoned over any
  of the nine, so anything keyed to one character's data silently works for
  that shell only, and any fix must be tested with at least two shells.


## Known gaps (as of 0.7.0)

- ~~Desperation~~ RESOLVED in 0.11.2 (412364+HP at low HP). ~~Win pose~~
  verified + win-screen hang FIXED in 0.11.3 (full match completes).
- Sound mapping is approximate (SMS whoosh/starter sfx for her Super S commands);
  refine per-move later if it feels off.
- ~~Fireball art fixture~~ RESOLVED in 0.11.4 (decompressed from the Super S
  ROM at build time; builds are fully self-contained).
- Char-select slot 10 is a PLACEHOLDER (0.10.0): the marker is a parked cursor
  glyph, not a portrait; hovering it shows no name text and the post-confirm
  portrait/VS/HUD screens show the shell character (Uranus). Real portrait art
  + name MOOT since 2026-08-04 (the visible variant is retired and deleted;
  hidden is the only char-select). Story/1P select intentionally excluded the slot (vanilla
  restricts the story roster the same way) — use L+R there.
- ~~REF-patch reconciliation~~ DONE in 0.11.5 (build_refsaturn.sh).

## How to test

```bash
git pull
python3 tools/saturn/mksaturn_smoke.py          # -> build/saturn/SailorMoonS_saturn_v<ver>.sfc
SATURN_HIDDEN=1 python3 tools/saturn/mksaturn_smoke.py   # -> ..._v<ver>-hidden.sfc (0.11.0+)
# one-time, for correct fireball art (needs the Super S ROM):
ROM=<SuperS.sfc> tools/run.sh tools/saturn/probe_supers_effecttiles.lua 60
```
**Character select — the hidden code is the ONLY variant since 2026-08-04**
(`-hidden.sfc`): nothing visible — hold **L+R while confirming Uranus, Neptune or
Pluto** at the select screen (any other shell is refused since 0.14.5 — that
restriction IS the story lock, and since 0.14.8 an illegal shell does not even
arm her sfx/palette); that character becomes Saturn at the round load.
The v0.10.0 VISIBLE slot-10 variant is **retired and its code deleted**: a
placeholder (parked cursor glyph, no portrait or name) that added the one
char-select surface the story lock exists to avoid. Removal is byte-identical to
the last hidden build, so no ROM changed. The rows below are history. Works for P1, P2, and the practice dummy (the code follows
the pad that drives the confirming cursor). Confirming without the code always
un-picks. **Visible variant — since 0.10.0**: in VS or practice char select, go to Chibimoon and press
RIGHT (or Venus + DOWN) — the cursor lands on a marked 10th spot at the
photo's bottom-right; confirm to pick Saturn (shows as Uranus until the round
loads). Works for P1, P2, and the practice dummy. **Since 0.8.0**: hold L+R
as a round loads (either pad) — that player becomes Saturn; SELECT-hold at a
round load reverts; this is also the ONLY way in story/1P mode.
`tools/saturn/saturn_test.lua` remains available (auto-transform + P2 mirror
matches + the on-screen version label).

## FIELD BUG: 214P projectile sprite — BISECTION RETRACTED (2026-08-05)

Reported as "corrupted since v0.14.6 — some tiles missing, some in the wrong
place". Measured with `tools/saturn/probe_saturn_projtiles.lua`, which fires 214P
and, 20 frames after the projectile slot populates, records every OAM entry
within 32 px of the projectile object plus whether the VRAM tile each one
references is blank:

| build | sprites near the projectile | blank VRAM | with data |
|---|---|---|---|
| 0.14.5 | 7 | 2 | 5 |
| 0.14.6 | 7 | 2 | 5 |
| 0.14.7 | 7 | 2 | 5 |
| **0.14.8** | **8** | **6** | **2** |
| 0.14.9 | 8 | 6 | 2 |

⛔ **RETRACTED — the table above measures the FIGHTER, not the projectile.**
A control run with **plain Neptune and no Saturn at all** produces the same tile
indices ($05D/$066/$069/$06A/$06E/$070), the same `pal=1`, and the same blank
count. "OAM entries referencing blank VRAM" is therefore NORMAL here and says
nothing about the bug; the 32 px window around the projectile also contains the
character, and that is what the numbers moved with. The v0.14.8 boundary is an
animation-phase difference, not a regression.

The maintainer also reproduced the bug on **v0.14.6**, and this measurement calls
0.14.5 and 0.14.6 identical — so whatever is wrong predates the boundary the
table claimed, which was the first sign the metric was invalid.

⚠ Two caveats on the attribution. The report says 0.14.6; the measurement says
0.14.8. v0.14.6 is the build that made **2P VS transform at all**, so if the
maintainer plays 2P VS, 0.14.6 is simply the first build where Saturn appears
there — first VISIBLE, not first broken. And this probe samples one instant in
practice mode on shell 6, so it bounds when the OAM/VRAM state changed, not
necessarily when the visible artefact started.

**What the field capture does establish** (maintainer, 2026-08-05): the 214P
projectile renders as **two disconnected blue pieces instead of one shape**, on a
Neptune shell. So the defect is real and visual, and it is about sprite
composition — pieces present but not forming the whole — rather than obviously
about colour.

**What is NOT established:** when it started. v0.14.6 is the earliest build the
maintainer TRIED, not a proven boundary.

**Blocker for the next attempt: the probe cannot yet identify her projectile's
own OAM entries.** Filtering by projectile-slot palette (2/3/7) plus a 64 px
window returns ZERO sprites, which means the coordinates read from the slot
($1121/$1122 x, $1125 y) are probably not its screen position — those offsets
were taken from the Deep Submerge notes and may not apply to her object.

### The window is now BOUNDED, and a known-good build exists (maintainer, 2026-08-05)

The bug cannot have started before **v0.14.2** and is present by **v0.14.6**:

* **v0.14.1 — projectile INTACT**, and Saturn was usable, so this is a genuine
  known-good reference.
* **v0.14.2-v0.14.5** — the shell was not replaced in the modes the maintainer
  plays, so the projectile could not be seen at all. Silent, not proven good.
* **v0.14.6** — 2P VS transforms again, and the projectile is visibly broken.

That pair (0.14.1 good / 0.14.6 bad) is the **control any future metric must
pass**: a measurement that cannot separate those two builds is measuring the
wrong thing, which is exactly how the retracted OAM metric went wrong.

### Attempt 2 also failed — recorded so it is not repeated

The right metric is the RENDERED FRAME (`emu.takeScreenshot()` at the moment the
projectile is live), since that is literally what the maintainer sees. Captured
on 0.14.1 and 0.14.6 at the same scripted instant — and **neither frame contains
the projectile at all**. So the trigger is wrong: it fires when slot `$1100`
becomes non-zero with `id=$22`, but that object is not her fireball, or it is
gone by the +20f capture point.

Incidentally confirmed in those captures, and NOT a bug: on 0.14.1 the dummy
transforms too (a Saturn mirror), on 0.14.6 it does not — that is the shell guard
working as designed.

**What would unblock this fastest:** the exact input and range that reliably
produces her 214P projectile, or a savestate with it on screen. The same thing
unblocked the throw corruption in 0.14.8, where the maintainer's minimum SPD
input (6 2 4 8 + P at contact) succeeded after the suite's own longer motion kept
whiffing. Guessing the trigger from here has now cost two attempts.

### 214P projectile: it is MODE-DEPENDENT, not build-dependent (2026-08-05)

Reproduced her 214P on v0.14.1 (known-good) and v0.14.6 (known-bad) in **practice
mode**, same scripted input, captured at the same frame, and compared the
projectile pixel by pixel over an identical crop window:

    projectile-blue pixels:  both = 641   only-0.14.1 = 0   only-0.14.6 = 0

**Pixel-identical.** The corruption does not reproduce in practice mode on the
build that demonstrably shows it in the field. So the defect is conditioned on
something other than the build alone — mode, matchup or shell — and the maintainer's
capture (health bars, timer, Neptune shell vs Moon) is from a real match, not
practice.

That kills the whole "bisect the builds" approach as run so far: a build A/B in a
mode where the bug does not occur can only ever return "identical", which is
exactly what the retracted OAM metric and this render comparison both did.

**Two things this run did establish, both useful:**

* **Her inputs are dead in vs-COM on v0.14.1** — act `$22` for all 702 frames of
  the window, no projectile slot ever populated. `BUILDS.md`'s own v0.14.3 row
  records this ("no entrance animation and no inputs — until she was hit"), so
  practice is the only mode that works across the whole 0.14.1-0.14.6 range, and
  it is also the mode where the bug does not appear. Those two facts together are
  why every automated attempt so far has come back clean.
* Earlier practice captures that showed "no HUD" were not mistimed — **practice
  draws no HUD at all**.

**Consequence:** the maintainer's savestates are not a convenience, they are the
only reliable route — they hold the exact mode, matchup and moment where the bug
manifests. Fixing the savestate loader (copy `tools/ds_trace.lua` exactly) is now
the highest-value next step, ahead of any further build bisection.

### 214P projectile: ROOT SIGNATURE FOUND (2026-08-05)

⛔ **Correction to the entry above:** the practice-mode A/B was pixel-identical
because BOTH frames were broken, not because neither was. The maintainer spotted
it in the captures — part of the shape is missing and one piece sits detached. So
the bug is NOT confined to a mode, and v0.14.1 is **not** a known-good reference.
It reproduces on the current build, in practice, with no savestate needed.

That also means the earlier "pixel-identical, therefore mode-dependent"
conclusion was wrong in the same way as the OAM bisection before it: comparing
two broken things and reading the absence of a difference as information.

**The measurement.** With her projectile live, every OAM entry on **OBJ palette
7** — exclusively hers since v0.14.9, which is what makes this filter valid where
the earlier palette-2 one was not — against whether the tile it points at holds
any data:

| y | x | tile | VRAM |
|---|---|---|---|
| 137 | 101 | `$0CE` | **blank** |
| 145 | 117 | `$113` | **blank** |
| 153 | 93 | `$0E2` | **blank** |
| 153 | 109 | `$0E4` | **blank** |
| 169 | 93 | `$114` | data |
| 169 | 101 | `$115` | **blank** |
| 169 | 109 | `$0E6` | **blank** |
| 177 | 85 | `$0E0` | **blank** |
| 177 | 101 | `$116` | data |
| 185 | 101 | `$117` | data |
| 185 | 109 | `$118` | data |
| 185 | 117 | `$119` | data |

**7 of 12 sprites reference tiles with no data.** Two ranges, behaving
differently:

* `$0CE`, `$0E0`, `$0E2`, `$0E4`, `$0E6` — **every one blank**, the range is
  simply not there;
* `$113`-`$119` — **partial**: `$114/$116/$117/$118/$119` have data,
  `$113`/`$115` do not.

So her sprite list is correct in structure — it emits sprites at sensible
positions — but points into VRAM that was never filled. One range is missing
wholesale and another is uploaded only in part, which is the shape of a transfer
that is too short or based wrong, not of a bad sprite list.

**Next:** find what uploads her projectile's effect tiles and compare the range
it covers against `$0CE-$0E6` and `$113-$119`. The DP-based DMA probe from the
patch-16 font hunt (`probe_fontdma2.lua`, read the parameters from direct page at
the `$420B` trigger — the DMA registers are write-only) is the tool that already
works for exactly this question.

### 214P projectile: SOLVED (2026-08-05) — the effects DMA is sized from the SHELL

**It is a per-shell truncation of her effect sheet.** The build stages her
0x1040-byte sheet over the shell's in `$7F:0000`, but the DMA that follows was
sized from the **shell character's own** effect sheet, and the shells differ.
Measured at the kick site (`probe_saturn_fxdma.lua`, dp+`$32`, D=`$0000`):

| shell | P1 effects DMA | vs her `$1040` sheet |
|---|---|---|
| 6 Uranus | `vram=$6A00 len=$11C0` | fits |
| **7 Neptune** | `vram=$6A00 len=$0E60` | **short by `$1E0` = 15 tiles** |
| 8 Pluto | `vram=$6A00 len=$10C0` | fits |

So on a **Neptune** shell the last 15 tiles (`$113-$121`) never reached VRAM and
kept whatever the previous match left there. Her 214P travel pose is 12 sprites
and **7 of them draw from exactly that range** — the five 16×16 tiles
(`$0CE/$0E0/$0E2/$0E4/$0E6`) survive, the seven 8×8 tiles (`$113-$119`) vanish.
That is the field report verbatim: *two disconnected blue pieces instead of one
shape*, on a Neptune shell, and intact on Uranus.

**Fix (v0.14.11):** the DMA stub's armed path now also forces the transfer
length — `lda #FX_SHEET_LEN / sta $004305` (long store: DB there is the
caller's). Proved safe in both directions from the full round-load DMA map
(same probe): P1 `$6A00`+`$1040` ends at word `$7220` and the next transfer
starts at `$7300` — Pluto's own already reaches `$7260`; P2 `$7300`+`$1040`
ends at `$7B20`, next starts at `$7C00`. Where a shell's sheet is *larger* this
also stops its leftover art trailing into tiles past hers.

**Verified:** her sheet is now byte-identical to `supers_lz`'s decoder output in
VRAM on shells 6/7/8 (130/130 tiles; before: Neptune 115/130), and the composed
projectile renders as one continuous flame. **The P2 side was measured, not
assumed** — Saturn as P2 on a Neptune shell was equally broken (114 non-blank
tiles at VRAM `$7300`) and now checksums identical to P1 (`$91C481B3`), which
also means P2 was affected on *every* shell, since P2's own transfer is `$0FC0`.
Gate `verify_saturn.sh` 46/46, regression 57/57.

**Every earlier attempt failed on instrumentation, not on reasoning:**

1. **The "root signature" table above is retracted a second time — but it named
   the right sprites.** It resolved a sprite's data as `tile * 32`, i.e. OBJ name
   base 0. The real base is `oamBaseAddress` = word `$6000` (byte `$C000`), with
   the second name table at word `$7000`, so every "blank VRAM" reading came from
   an unrelated part of VRAM. Correctly resolved, *all 12 sprites point at tiles
   that are present and correct* — on Uranus.
2. **The palette filter and the distance window both mis-identified the
   sprites.** Her sprite list is emitted on **alternate frames**, so a capture
   triggered "+20 frames after the slot populates" lands on an empty frame half
   the time — one such capture returned zero palette-7 entries and three
   unrelated sprites that looked like a projectile. Identification is now by
   **correlation over the whole flight** (`probe_saturn_projoam.lua`): the
   entries that appear when the slot populates, move with it, and vanish with it.
3. **The bug was never build-dependent — it is SHELL-dependent** (HANDOFF trap
   #1: test at least two shells). Every bisection compared builds on one shell
   and correctly reported "identical".
4. **Two probes reported nothing because they were broken.** `emu.getState()`
   throws inside a memory callback here and silently kills the hook — and the
   counter was incremented *after* that call, so a dead probe reported "0 DMA
   kicks" rather than an error. And the kick site must be hooked at **`$80:92A4`**,
   not `$C0:92A4`: this code runs from the FastROM mirror.

**The gate could not have caught this** — it passed on the broken build. It now
carries a check that fails on it: `probe_saturn_fxsheet.lua` asserts her effect
sheet is **identical across shells** (cross-shell invariance rather than a
hardcoded checksum, so it survives any change to her art). Sanity-checked
against v0.14.8: shells 6 and 7 disagree there, and agree on the fix.
