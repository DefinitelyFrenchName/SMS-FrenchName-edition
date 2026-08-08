# The project — the FrenchName edition

**Everything in this folder is about THIS PROJECT**: what it patches, how it
builds, how it is tested, and what was decided along the way. Knowledge of the
original game lives in [`../game/`](../game/) and is deliberately kept separate,
so that half can be lifted by anyone working on this ROM.

## Where to start

| If you want to… | Read |
|---|---|
| **see every patch at a glance** | [`patch_index.md`](patch_index.md) — the one-page registry, with status and lifecycle |
| know what a patch changed, and why | [`patch_notes.md`](patch_notes.md) — mechanism, changed bytes, verification, per patch |
| pick up where the last session stopped | [`NEXT_SESSION.md`](NEXT_SESSION.md) |
| build, test, or avoid a known trap | [`../../HANDOFF.md`](../../HANDOFF.md) — the operational map (kept at the repo root) |
| set up the toolchain | [`toolchain.md`](toolchain.md) — what the repo does not ship and where to get it |
| use the training mode | [`training_install.md`](training_install.md), [`training_usage.md`](training_usage.md) (Lua), [`trainingplus.md`](trainingplus.md) (patch 11, in-ROM) |
| follow the Saturn port | [`saturn/`](saturn/) — its own PROJECT.md and BUILDS.md |

`patch_notes_dashfix.md`, `patch_notes_palettes.md` and `patch_notes_title.md`
are the long-form notes for patches 2, 3 and 4; `history/` holds the original
brief, superseded and kept as a record of how the ROM map was derived.
`halfwidth_caps.json` and `halfwidth_tiles.json` are patch 16's authored glyph
set and its glyph→VRAM tile map — generated, not hand-edited.

## Conventions worth knowing before contributing

* **Never patch a ROM in place**; builders take `(src, out)` and every stacked
  step needs `--stacked`.
* **Never chain standalone `.bps` files** — every bank-appending patch targets
  the same first free bank. Chain the *builders* instead, then diff once.
* **Byte-identity is the refactor gate.** A change that should not alter output
  must be proven not to, across every knob that alters emitted bytes.
* **Published artifacts are never redefined.** A superseded build gets a new
  name (REF v.1 → v.2, Rev. 01 → 02), never a redefinition.
* **Generated files are generated** — `tools/README.md`, the regression suite's
  signature block and the release notes all have `--check` modes, and the build
  scripts run them.

## Note on `saturn/`

The Saturn port sits here rather than in `../game/` because it exists to serve
this project. Some of it — `supers_map.md`, `supers_assets.md` — is genuinely
analysis of *Sailor Moon Super S*, a different game, and could be split out if
anyone ever wants that on its own; the set cross-references itself heavily, so
it was kept whole.
