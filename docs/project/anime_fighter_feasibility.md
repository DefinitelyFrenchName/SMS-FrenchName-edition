# Anime-fighter feasibility — the measurement dossier

**Question (maintainer, 2026-08-20):** can SMS become an anime fighter — universal
ground+air front/back dashes, dashes cancellable into attacks, air specials for
all nine, air cancels/chains, juggle-capable air combos, and (added during
planning) an air block that would carry air guard-cancels? Balance out of scope.

**Verdict after Phases 0–7 (2026-08-20): YES — DEMONSTRATED.** Every requested
mechanism now runs live on `build/exp_anime_stack.sfc` (recipe
`tools/exp_anime_stack.sh`, regression 45/45): air dashes both ways,
dash-cancels into normals, air specials on characters who lacked them, on-hit
air chains, a tunable air-action budget, and real juggles — all of it landed
in one scripted no-pokes combo by `tools/demo_airrush.lua`
(launcher → air-dash chase → dash-cancel j.HP → juggle re-hit → gatling dash
→ landing reset). The only feature not yet prototyped is air block (two
bounded sites located, air GC rides along by construction). What remains is
roster ROLLOUT (per-character constants), the air-block prototype, and the
maintainer policy rulings below.

Everything here was measured 2026-08-20 on the clean ROM
(`bc0e29ee383574443226695215496eb0d09aaa1c`) unless marked otherwise; the
probes and censuses are in `tools/`, the traces in `traces/` (regenerate with
the command in each probe's header). The programme design and the phased
roadmap live in the session plan; the prior art is `tools/exp_airbackdash.py`
(Venus's working air back/front dash, commits a726fe1–b9ee584).

## The ten unknowns → measured answers

| # | unknown | answer | evidence |
|---|---|---|---|
| 1 | Can an airborne victim be re-hit? | **YES, once `+0x46` bit7 is clear.** The one gate is `lda $46,X / bmi` at **`$C0:C00A`** — a single instruction in hit resolution. With the victim held at jab range and `+0x46` poked to `0x20` or `0x00`, six consecutive jabs resolved on the airborne victim, each dealing damage and each re-dispatching the game's own AIR reaction row coherently (act `0x16` + fresh `0xA0` re-set per hit, no garbage act, no softlock). The clean run at identical spacing resolved **zero** — the negative control failed for the gate reason. | `probe_juggle.lua`; `traces/juggle_{clean,poke20,poke00}_d12.txt` |
| 2 | High-altitude air-hit reaction | **Partial.** Air contact sampled at y=164 (Venus 5HP's reach ceiling) → act `0x16`, `+0x46=0xA0`; grounded contact → act `0x11`/`0x13`, `+0x46=0x20`. Higher-altitude rows need a taller launcher (bounded coverage, not a conclusion). | `traces/juggle_clean_d{12,20,32}_free.txt` |
| 3 | On-hit record byte-3 "flags" | **A single bit, table-family-correlated**: `0x00` across the first five posture tables (except idx 12), `0x01` across the last five (except idx 13 in three). 160/160 records ∈ {0,1}. Consumer not yet traced; hypothesis: knockdown/launch-class marker. Anchored to the documented `$CDD5` rows, controls red at base±1. | `census_onhit_flags.py`; `traces/onhit_flags_census.txt` |
| 4 | `+0x32`/`+0x34` labeling conflict | **Player path settled: `+0x32` = Y velocity, `+0x34` = gravity.** Venus neutral jump: impulse −2048 into `+0x32`, sweep +96/frame; `+0x34` constant 96. Gravity is per-move (jump 96, Chibi jump-fwd 160, her dive-bounce 88, Uranus dash 64 per patch 6). The reaction-template sentence in `sms_engine_internals.md` ("launch velocities +0x32/+0x34") is wrong about `+0x34` and needs correcting. | `probe_airphys.lua`; `traces/airphys_jumps.txt` |
| 5 | Air-normal start routes | **NONE — 0 of 72.** Every air-normal handler of all nine characters offers no start route: vanilla air normals cancel into nothing. Air chains are therefore route-insertion work (the proven stub technique) on the air-normal handlers. Bonus census: all 18 jump stance tables decoded (backlog item closed); the jump acts' routes per character are in the trace, incl. a previously undocumented **air-throw route census** — exactly Moon/Mercury/Mars/Jupiter/Neptune offer `$055A` from jump acts, matching the documented air throws move for move. | `census_airroutes.py`; `traces/airroutes_census.txt` |
| 6 | Ground specials run airborne | **YES, both families — measured 2026-08-20 (Phase 2, `exp_airspecial.py`).** The whole edit is clearing flag bit0 on the entries (four bytes for Venus/Moon 236P + two for Venus 623P). Airborne: the act starts, X freezes (handler-set), the Y arc CONTINUES under gravity, the projectile spawns **body-relative** (ground beam y=124 = 192−68; air beam y=28 ≈ 96−68) and flies horizontally at air height, the act runs through landing (per the landing contract) and returns to neutral — no pinning, no wedge, projectile AND strike (623P) alike. Grounded sections frame-identical clean↔build; clean air input produces nothing. Re-fire is a non-issue exactly as predicted: the latch dies in 2 frames and special acts offer no routes. | `probe_exp_airspecial.lua`; `traces/exp_airspecial_{venus,moon}_{clean,build}*.txt`; regression 45/45 on the build |
| 7 | Jump-normal tables, 8 chars | **Decoded, all nine** (two tables each, 4 records each, printed in the census trace). All records are far==close with threshold 255 — jump normals have no proximity variants anywhere. | `traces/airroutes_census.txt` |
| 8 | Landing mechanics | Grounded bit (`+0x16` bit7) sets on the arrival frame (y=192 reached, velocities zeroed); act `0x09` staged the NEXT frame; landing is 5f. **Landing does not truncate a running act** — a whiffed Chibi j.2K dive reaches the ground and its own handler chains dive act `0x66` → grounded skid act `0x68` (~50f) → neutral; the engine only sets the bit. Landing behavior is a per-handler contract, like step-0 init. | `traces/airphys_jumps.txt`, `traces/airphys_airspec_d8_back.txt` |
| 9 | Saturn / Rev. SS | **Answered by scoping**: research runs on the Rev. S clean base only; every bank-`$C1` hook must also be applied to the SS line's bank copies ($EF/B_C1) at promotion time (trap 5 / [SSP-12]). |
| 10 | Air-action accounting | Not yet claimed (Phase 5). New fact that shapes it: the `+0x51` latch clears ~2 frames after a legitimate air-special start with NO step-0 re-fire — the exp's re-fire loop happens only when the STARTED act itself re-offers the same start route within the latch window. An authored air act that doesn't re-offer its own route needs no flag guard at all. | `traces/airphys_airspec_d8.txt` (t=89–91) |

## The air block / air guard-cancel question (maintainer addition)

Three measurements pin the architecture:

1. **Blocking is an input-state predicate, not an act predicate.** A grounded
   victim merely WALKING BACK blocks Venus's 5HP (act `0x02` → blockstun
   `0x0E`, zero damage); a victim POKED into guard pose `0x0C` with back held
   takes the full hit. (`traces/airguard_ground_{natural,act}.txt`)
2. **The victim-side posture gate is ONE branch**: `$C1:0E26`'s reaction
   dispatch selects the posture sub-table with `lda $16,X / and #$0080 / bne`
   at **`$C1:0E55`** — airborne victims route to the `$0EBB` (air /
   "guard-incapable") sub-table before any guard logic can run. Sub-tables:
   `$0E83` stand / `$0E9F` crouch / `$0EBB` air.
3. **The attacker-side guard predicate never consults an airborne victim**:
   the pending reaction code (`+0x47`) is `0x0C` for an airborne victim with
   back held AND without — identical — while a grounded blocker gets `0x04`
   (a block-level code). So resolution chooses hit-vs-block only for grounded
   victims. (`traces/airguard_air_{natural,noguard}.txt` vs
   `traces/airguard_ground_natural.txt`)

**Cost of air block: a bounded two-site redesign** — (a) the resolution-side
level chooser must be taught an airborne-guard case (the code that stages
`+0x47`, around the `$CD75/$CD95` dispatch pair at `$C0:C084`/`$C0:C157`;
exact predicate site is follow-up RE), and (b) the air path at `$C1:0E55`
needs block rows — an authored air-blockstun act behind a trampoline.
**Air guard-cancel then rides along by construction**: ground blockstun's only
start route is `jsr $0958` with the special-start table, so the authored
air-blockstun act carries the same route and the flag byte filters it to
air-legal moves (air dashes, air specials) for free.

## What this changes about the feature costs

| feature | cost after measurement |
|---|---|
| Air dashes, both ways, all nine | **Proven on BOTH structural classes** — Venus (reroute, `exp_airbackdash.py`) and now Uranus (route INSERTION, Phase 3 `exp_airdash2.py`, 2026-08-20): her jump handlers offer only the normals route, so the 35-byte stub at `$C1:BFA0` wraps `jsr $0459` instead — air back 0x2B (33f, vulnerable, dx=−119) and air front 0x2C (33f, dx=+131, her own Shadow Dash handler) both fire, ground 44/66 identical to clean, clean negatives silent, regression 45/45. Uranus needed NO table surgery at all (she owns the 66 → the stub reads nibble 04/05 directly). ⚠ NEW LAW: **`$C1:0459` does not preserve X** — a stub wrapping it must `ldx $88` before touching the object (measured: the stub was silently dead without it; `$0958` does preserve X, which is why the Venus stub never hit this). Replication to the remaining seven = per-char constants for the same two stub shapes. |
| Dash-cancels into attacks | Authorable: we write the air-dash handlers, so we choose their start routes (normals via the existing jump stance tables + specials). No engine obstacle found. |
| Air specials for the six | Table appends (air-only entries) + route insertion for the five whose jump handlers lack `$0958`. Open question is only handler physics airborne (Phase 2). |
| Air chains / cancels | Route insertion on air-normal handlers (72 handlers, none has routes today); hit-confirm cancels via the `$0952` entry work airborne (the `+0x43` latch is set by air hits — measured in the juggle runs). |
| Juggles | **Flag policy + reaction choice**, not surgery: keep `+0x46` bit7 clear (or clear it after k frames) in the AIR reaction rows and the engine already re-hits, re-reacts and re-launches coherently. The infinite-juggle bound needs the Phase 5 counter. |
| Air block + air GC | Moderate: two bounded sites (above) + guard-entry route in jump handlers. Feasible; most involved single feature. |
| Universal ground dashes | Motion budget confirmed: Moon and Uranus already own a 66; everyone else has ≥1 free motion slot (Moon/Jupiter 6/7, Mercury/Mars/Venus/Uranus 5/7, Neptune/Pluto/Chibi 4/7). Capacity-efficient design: ONE 66 motion + a flag-`0x00` (unrestricted) entry whose act handler branches on the grounded bit into ground-dash vs air-dash — no second motion needed. | 

(`census_motionbudget.py`; `traces/motionbudget_census.txt`)

## Roster-PoC findings (2026-08-20, all measured)

- **A stub returning into a handler continuation must restore X = object on
  EVERY exit path.** The `$0958` starter (and the continuation code generally)
  indexes the struct through X without reloading; the frontid lookup's `tax`
  left X = charID on the no-dash path and Chibi's air desperation read its
  pending nibble from `$005A` — zero damage, caught by the regression
  compendium, pinned by bisection (jump-hook-less variant passes). This is the
  Phase-3 `ldx $88` law's other half.
- **A motion appended AFTER a prefix-overlap motion never completes.** Jupiter's
  m5 desperation shares m4's script tail (`$14F8 = $14FA − 2`); a 66 at m6
  behind it resets on the exact input it wants, while the identical script at
  m6 works for Venus (measured with a skipped-slot list). Cause in the
  interpreter unidentified; the working rule is INSERT the new motion before
  the overlap motion (Jupiter's desperation now sits at ids 0x0E/0x0F and
  passes the compendium).
- **Nonzero step timeouts count DOWN** (a step's `[timeout]` loads the timer
  and decrements; timeout 0 counts UP to the `$0F` default window) — visible
  in the m5-vs-66 state traces.
- **Known PoC budget leak**: Venus/Jupiter/ChibiMoon's jump handlers natively
  offer the special table, so their front dash also starts through the vanilla
  starter (the air-only `[02→2C]` entries), uncounted when the +0x7F budget is
  exhausted. Leak-free wiring (per-entry gating or wrapper-edge counting) is
  rollout engineering.
- Space claims: relocated data spilled into the `$BE09` hole (patch 1/2's
  home) — the roster PoC is standalone-from-clean only; integration with the
  Rev. S patch line needs a space plan.

## Corrections owed to the docs (found on the way)

- `sms_engine_internals.md` reaction-template line ("X/Y launch velocities
  (+0x32/+0x34)"): `+0x34` is gravity on the player path; the reaction
  handlers' velocity fields should be re-derived before the sentence is fixed.
- `tools/exp_airbackdash.py` docstring lines ~111–128 and the `--front` help
  still say the front dash "does not fire" — superseded by commit 0f22977
  (stale text, the corrected account is lower in the same file).
- New engine facts worth promoting to `docs/game/` (with checkdocs treatment):
  the `$C0:C00A` untargetability gate, the `$C1:0E55` posture branch and
  sub-table addresses, jump physics constants, the landing contract, the
  air-throw route census, the 18 jump stance tables, prejump = 5f (confirmed),
  and the on-hit byte-3 bit census.

## Decision points for the maintainer (before prototypes)

1. Global edits: juggle enablement patches the AIR reaction rows, which are
   GLOBAL (every character's launches change) — acceptable as total-conversion
   policy? [SMS-4]
2. Juggle rule: remove untargetability outright, or a juggle-decay counter
   (shares Phase 5's accounting)?
3. Air-action budget N per jump?
4. Air specials: air-enable existing ground specials (if Phase 2 permits) vs
   authored air variants — per character?
5. Air block: in or out, given the two-site redesign cost above? (Air GC comes
   with it by construction.)
6. Promote to a numbered patch line / total-conversion branch, or keep as
   `exp_` research?

## Gate ledger

| gate | outcome |
|---|---|
| G1 (juggle kill-shot) | **BEST CASE** — flag policy; single-instruction gate at `$C0:C00A`; reaction path juggle-coherent |
| G3 (ground specials airborne) | **BEST CASE** — projectile and strike families both run coherently airborne from a flag-bit edit; body-relative projectile spawn gives true air fireballs; air specials scale to the roster as flag edits + route insertion |
| Phase-3 universality | route insertion proven (Uranus); mechanism declared universalizable, remaining seven characters are constants, not research |
| Phase 4 (cancels/chains) | dash→normal is a ONE-FRAME cancel (wrapper handler; routes-after-tail need a re-run of `$0204` to latch the anim); the on-hit gatling (j.HP → air dash on `+0x43`) fired and its whiff control stayed silent. ⚠ Two laws paid for: `$0459` clobbers X; Uranus's stance records are ordered by ASCENDING BUTTON BIT (her dir j.HP is act **0x50**, not 0x51 — engine-internals column labels need re-deriving) |
| Phase 5 (air budget) | counter = struct `+0x7F` (measured init-only; magic 0xA5 survives 1400 busy frames; boot watch owed); N=0 kills all air dashes, N=1 gives exactly one per airborne period, landing stub resets it. Harness law: the recognizer needs a registered NEUTRAL before tap 1 |
| Phase 6 (juggles) | **TWO BYTES** — the `+0x46` write census found exactly 18 immediate writers; flipping the act-0x1B launch and act-0x16 air-hitstun handlers' `#$A0`→`#$20` makes launched victims re-hittable with the game's own pipeline; knockdowns/flame/electric/throws keep protection; regression 45/45 (no vanilla invariant depended on launch untargetability). Launch handlers write Yvel→`+0x32`, gravity→`+0x34` — the reaction-path doc conflict resolved the same way as the player path |
| Phase 7 (integration) | `tools/exp_anime_stack.sh` chains all five exps (45/45 regression); **`tools/demo_airrush.lua` lands the whole thing in ONE no-pokes sequence**: anti-air launcher t=153 → air-dash chase (budget 1) → one-frame dash-cancel j.HP t=193 → JUGGLE re-hit on the floating victim t=198 → gatling second dash (budget 2) → landing reset. A plain jump provably cannot chase the launch drift (+2 px/f each) — the air dash's 11 px/f is what makes juggle routes real |
| **FULL-ROSTER PoC** | **`tools/exp_animeroster.py` (2026-08-20): every mechanism, ALL NINE characters, derived from the ROM at build time** — 27 jump-route hooks, 72 air-normal tail hooks (the gatling), 9 landing resets, appended/inserted 66 motions for seven characters (relocated motion lists + special tables with air-only `[02→2C]` entries in the measured-dead recognizer region + the `$C1` holes), 24 projectile-special air-enables, the 2 juggle bytes, the +0x7F budget — logic in an appended bank behind four `$C1` call gates and 5-7-byte shims. **Verified: per-character probe green 9/9** (ground 44 control, air 2B, dash-cancel into their own dir j.LP, air 2C incl. the appended-motion input), clean negatives silent, **regression 45/45**, `demo_airrush` and the Venus air-fireball probe green on the roster ROM. `build/exp_animeroster.bps` (2 KB). |
| G2 (landing) | acts keep running on landing → air-enabled ground specials need explicit landing handling (cost multiplier, not a kill) |
| G4 (air-normal routes) | none exist (0/72) → chains are route-insertion work, as planned |
| G5 (motion budget) | nobody blocked; flag-0x00 shared-entry design makes the 7-cap a non-issue |
| Air-block gate | guard predicate is grounded on BOTH sides (resolution + reaction); two bounded patch sites identified |
