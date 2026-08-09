# The game — analysis of *Bishoujo Senshi Sailor Moon S: Jougai Rantou!?* (SFC)

**Everything in this folder is about the ORIGINAL GAME, not about this project.**
It is knowledge of the retail ROM — memory layout, data formats, engine
behaviour — and it stays true whatever anyone patches. If you are working on this
game and have no interest in the FrenchName edition, this folder is the part you
want, and it is meant to be liftable on its own.

Ground truth for every file here: clean Japanese ROM, SHA-1
`bc0e29ee383574443226695215496eb0d09aaa1c`, HiROM + FastROM, headerless, and the
one rule the whole map hangs on — **file offset = SNES address & 0x3FFFFF**.

Two of these documents are also published as drawn pages:

* **[the data architecture](https://definitelyfrenchname.github.io/SMS-FrenchName-edition/)**
  — `sms_data_architecture.md` with the memory maps drawn rather than described.
* **[one frame, as the cartridge runs it](https://definitelyfrenchname.github.io/SMS-FrenchName-edition/frame.html)** — the in-match loop
  `$C0:E255` stage by stage, the NMI that releases it, where a hit is actually
  resolved, and the stage each patch hooks. The text version is
  `sms_data_architecture.md` §10B and `sms_engine_internals.md` §3.

## Where to start

| If you want to know… | Read |
|---|---|
| **where data lives and what shape it is** | [`sms_data_architecture.md`](sms_data_architecture.md) — the four memories, the object struct byte by byte, the record catalogue, the pipelines. Start here |
| how a subsystem *behaves* and why | [`sms_engine_internals.md`](sms_engine_internals.md) — the explanatory synthesis, by subsystem |
| the exact address of a thing | [`annotations.md`](annotations.md) — the flat address → label phone book |
| **a one-page card of the load-bearing addresses** | [`sms_quickref.md`](sms_quickref.md) — every entry points at a longer document |
| how damage is computed, end to end | [`sms_damage_system.md`](sms_damage_system.md) — and note its headline: **there is no RNG in damage** |
| the A.C.S. stat system + the damage matrix | [`sms_acs_system.md`](sms_acs_system.md) |
| every character's specials and desperations | [`sms_specials.md`](sms_specials.md) |
| how menus, fonts and text are drawn | [`menu_system.md`](menu_system.md) — the glyph format, both font sheets, the two screen engines, the runtime text writers, the VRAM rules |
| hitbox / hurtbox / push-box data | [`sms_all_boxes.json`](sms_all_boxes.json) — extracted, all nine characters |
| **the addresses for ONE character** | [`characters/`](characters/) — a generated page per fighter: manifest, palettes, box tables, animation layers, proc block, throws, voice ids |

`te_halfwidth.json` holds the half-width Latin font extracted from the Big Zam
**Tournament Edition** ROM, kept as reference.

## The house rules these were written under

They are worth knowing before trusting or extending anything here:

* **Measure, don't infer.** Every timing and behaviour claim was validated by
  frame-advance in an emulator, never derived from disassembly alone. Where a
  claim is disassembly-only, it says so.
* **Find the interpreter before trusting the data.** This engine is data-driven:
  generic code walks records. A run of zeros after a string looked like a
  terminator once and was centring padding — the build made on that reading hung
  the game.
* **A probe that reports nothing is usually broken, not evidence of nothing.**
  Several "the game never does this" findings here were a hook on the wrong bank
  mirror. Verify the instrument against a known-present signal first.
* **DMA is invisible to CPU write callbacks.** Any claim that a memory region is
  free needs snapshots as well as a write watch.
* **The holes are documented too** — `sms_data_architecture.md` §13 lists what is
  *not* decoded (codec 2, the variable-text engine, ~180 KB of unattributed
  graphics). A map that hides its gaps is worse than no map.

## What is NOT here

This project's own patches, builders, test suites and decisions live in
[`../project/`](../project/). If a file mentions a `mkpatchN.py` or a build hash,
it belongs there, not here.
