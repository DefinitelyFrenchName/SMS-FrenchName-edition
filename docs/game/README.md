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
| **the sound system**, end to end | [`sms_sound_system.md`](sms_sound_system.md) — the APU upload, the SPC driver (which lives in ROM), sound ids, and why every fighter's voice carries its own transpose byte |
| how menus, fonts and text are drawn | [`menu_system.md`](menu_system.md) — the glyph format, both font sheets, the two screen engines, the runtime text writers, the VRAM rules |
| hitbox / hurtbox / push-box data | [`sms_all_boxes.json`](sms_all_boxes.json) — extracted, all nine characters |
| **the addresses for ONE character** | [`characters/`](characters/) — a generated page per fighter: manifest, palettes, box tables, animation layers, proc block, throws, voice ids |

`te_halfwidth.json` holds the half-width Latin font extracted from the Big Zam
**Tournament Edition** ROM, kept as reference.

## The house rules these were written under

They are worth knowing before trusting or extending anything here:

* **Measure, don't infer — and measure hardest when you are sure.** The full
  rule, which governs this whole corpus: *any data should come from measurements,
  NEVER guesses. When you don't know you measure, when you think you know you
  measure to check against the measurement, and when you're sure you don't have
  to measure is precisely when you absolutely must measure. We do not compromise:
  the source of truth is the original code.* Every timing and behaviour claim
  here was validated by frame-advance in an emulator, never derived from
  disassembly alone; where a claim is disassembly-only, it says so. Where a
  number appears, a run produced it — `tools/checkdocs.py` re-derives what it can
  from the cartridge on every `health.sh`, and each time that net has been widened
  it has caught documented facts that were plausible and wrong.
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

## Writing a new address into these pages

`tools/checkdocs.py` re-derives what it can from the cartridge, and how a claim
is *written* decides how much of it can be checked. None of this is style
policing — an unquoted address is a claim nobody can falsify.

* **Quote something.** An address alone can only be checked structurally ("there
  is an instruction there, and something calls it"), which catches a later edit
  but can never catch an address that is wrong the day it is written. An address
  written next to bytes or an instruction can, because you read the two
  independently. That redundancy is what caught `stz $47,X` documented at
  `$C1:0E51` when it is at `$C1:0E4F`.
* **The forms the extractors bind** (`tools/docaddrs.py`):

  | form | example |
  |---|---|
  | quoted instruction, attached | ``the box writer `$C0:9CCD` (`sta $41,X`)`` |
  | …or after it | ``` `stz $47,X` at `$C1:0E4F` ``` |
  | quoted byte run | ``` `$C1:0AF5` = `00 01 02 02` ``` |
  | file offset | `$C0:D56F (file 0x00D56F)` |
  | disassembly listing row | `C0/D055  rep #$30` |
  | table row: subject in cell 1, quote later | `\| $C3:BADE \| menu bound \| `sta $1F59` \|` |

* **Abridging a sequence is fine** — the parts need only appear in order, so
  ``jsr $B33F / ldx $8E / jmp ($B32B,X)`` checks out even though the ROM has a
  `sep #$30` in the middle.
* **Describing an absence is fine and stays unchecked.** "step-0 init MISSING the
  engine-standard `stz $46,X`" is deliberately not bound — asserting it would
  invert the claim.
* **In a table row, name the subject first.** If the row introduces another
  address before the quote, the quote is assumed to describe *that* one and
  nothing binds — which is usually what you meant.
* `python3 tools/checkdocs.py --uncovered` lists every documented ROM address no
  check re-derives, and says why each one could not be pinned.

## What is NOT here

This project's own patches, builders, test suites and decisions live in
[`../project/`](../project/). If a file mentions a `mkpatchN.py` or a build hash,
it belongs there, not here.
