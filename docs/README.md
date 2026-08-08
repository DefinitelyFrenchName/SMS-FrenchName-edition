# docs/

Split in two, because the two halves have different lifetimes and different
audiences:

| | |
|---|---|
| **[`game/`](game/)** | Analysis of the original **Sailor Moon S** ROM — memory maps, data formats, engine behaviour, the menu/font system. True of the retail cartridge whatever anyone patches, and **liftable by any other project on this game.** |
| **[`project/`](project/)** | The **FrenchName edition** itself — patches, builds, tests, decisions, the Saturn port. |

The rule of thumb when adding a file: *would this still be true, and still
useful, to someone who had never heard of this project?* If yes, it belongs in
`game/`.

Three documents stay at the repo root because they are the entry points:
`README.md` (what this is and how to apply it), `HANDOFF.md` (the operational
map) and `CLAUDE.md` (the working brief).
