# PROJECT: "SMS + Saturn" — Sailor Moon S with Sailor Saturn

> **This is the project brief for a multi-session effort** (started 2026-07-30), the
> same role CLAUDE.md played for the original infinite patch. Companion docs in this
> directory: `feasibility.md` (route decision, evidence), `supers_map.md` (the Super S
> ROM/RAM map — verified facts only), `saturn_notes.md` (Saturn's kit, act IDs, frame
> data, balance hooks). Session state: repo `HANDOFF.md` / `docs/NEXT_SESSION.md`.

## Objective

A game that **plays like Sailor Moon S** — the SMS engine's rules, timings and
idiosyncrasies, carrying the **REF v.1 patch set** (1b+2+3+4+5+7+8+9+12+13+14) —
extended with:

1. **Sailor Saturn as a 10th playable character** (MUST-HAVE). Source material: the
   sequel *Bishoujo Senshi Sailor Moon Super S — Zenin Sanka!! Shuyaku Soudatsusen*
   (SNES, 1996), the only game where she exists.
2. **Extra stages / music / assets from Super S** (NICE-TO-HAVE).

Regardless of implementation route, **Saturn must be documented the way Uranus was**
(act IDs, hitboxes, frame data, damage, the specific broken tools) so she can be
balance-adjusted — in Super S she is the S-tier problem child the way vanilla Uranus
was in SMS.

## The route decision

- **Route A (preferred a priori): port Saturn INTO the SMS ROM.** Keeps every verified
  SMS behavior bit-exact; costs the character-port work (see feasibility.md).
- **Route B: port SMS's values/patches INTO the Super S ROM.** Saturn pre-exists;
  costs re-deriving every patch hook for Super S **plus reverting the sequel's own
  gameplay changes** (it nerfed projectiles/desperations across the shared cast and
  introduced at least one input regression — see feasibility.md §Super S deltas).
- The decision lives in `feasibility.md` with the evidence and the conditions that
  would flip it.

## Ground truth (validated 2026-07-30 — do not re-derive)

- **Super S ROM**: `SailorMoonSuperS Vol2`, HiROM+FastROM (map byte 0x31), 0x300000
  (3 MB), header game code `$FFB3 = 0x4A` (SMS = 0x51), SHA-1
  `1ada34177e7384612ae83464288f3860e4c4426e`, CRC32 `25440331`. Resolved by
  `tools/smspaths.py: supers_rom()` (same `$SMS_ROM_DIR → roms/ → ../roms/` chain).
- **The vendor Lua is dual-game** (`vendor/sms-training-mode/SailorMoonS.lua` — the
  Rosetta Stone): Super S boxes live in bank `$AF` (ptr tables hit `$AF:B000`, hurt
  `$AF:B046`, coll `$AF:B05C`), palette manifests `$E0:ABC4`, input-read hook
  `$80:8347`, object update `$C1:0000` (same as SMS). Table extents = SMS + exactly
  one roster slot. **Saturn box ptrs: hit `$AF:B014`, hurt `$AF:B05A`, coll
  `$AF:B070`.** WRAM player structs presented as identical across games
  ($7E:1000/1080, all offsets incl. ACS +0x70-75). Verified subset: `supers_map.md`.
- **SMS has NO dormant Saturn slot** (full dossier in `feasibility.md` §Route A):
  every roster table is exactly null+9 and packed; six tables need relocation for a
  10th character; on-hit classes 0x1C-0x1F look unclaimed; ~1 MB headroom under the
  4 MB HiROM ceiling.
- **Saturn's kit is structurally different**: her cancellable-recovery act set has
  8 entries (`{0x41,0x43,0x49,0x4B,0x59,0x5B,0x61,0x63}`) vs 4 for every SMS
  character.
- **Why she's broken in Super S** (Super Fighting Wiki): far 5LK and far 5HK are
  UNBLOCKABLE (guard-proximity data never triggers the guard animation), close 5HK
  nearly so (guardable only at ranges 25-37 standing / 25-32 crouching), plus "weird
  throws". S-tier above Uranus. This reads as a data bug in how she was integrated —
  i.e., fixable by data, which is exactly the balance surface we want documented.
- **Prior art**: "Sailor Moon Fighter S" (romhacking.net/hacks/4498) is a large
  Super S hack (rebalance incl. Saturn changes, new characters, translation) —
  proof of Super S hackability and a reference for what others changed.

## Constraints & conventions (inherited from the SMS project)

- All timing/behavior claims validated by frame-advance in Mesen (tools/run.sh
  harness), never inferred. Ground-truth docs updated per finding.
- Never patch ROMs in place; builders + BPS via flips; `--stacked` on chained steps;
  byte-identity audits after refactors; suites green before shipping.
- ROMs never tracked; resolution via `tools/smspaths.py`.
- The repo-wide "no Saturn references in code" rule (HANDOFF §5) has a **scoped
  exception**: `docs/saturn/**` and Super-S-targeted tools (`tools/*supers*`,
  probes named `probe_supers_*`). SMS-targeted code keeps the rule.
- The maintainer's dedup rule: common tooling centralized, game-/patch-specific
  logic standalone.
- **Doc separation (maintainer, 2026-07-30):** Saturn-the-character material →
  `saturn_notes.md`; Super S EXTRA assets (stages/music/etc.) → `supers_assets.md`;
  shared engine/ROM facts → `supers_map.md`. Keep them apart.
- **ROM space:** ~1 MB free today. Removing STORY MODE entirely (tournament-edition
  style) is on the table if space runs out, but **requires explicit maintainer
  approval before execution** — never assume it.

## Definition of done (whole project)

1. A shippable BPS (against whichever base the route decision picks) whose ROM:
   plays like SMS (SMS engine invariants green in the regression suite), carries the
   REF v.1 behavior set, and offers Saturn on the character select with working
   normals/specials/throws/desperation, palettes, portraits, theme.
2. `saturn_notes.md` grown into a full Uranus-grade dossier: act table, box tables,
   frame data (oracle-validated), damage values, and the documented broken tools
   with tuning knobs (her guard-proximity data first).
3. Balance pass: her unblockable normals made blockable (data fix), then tuning to
   the maintainer's "minimal playbook-preserving nerfs" philosophy.
4. Test estate: Saturn cases in the regression suite (fixtures, frame-data locks,
   desperation compendium entry), builders with SIG fingerprints, recipes committed.
5. Nice-to-have (separate milestone): Super S stages/music selectable.
