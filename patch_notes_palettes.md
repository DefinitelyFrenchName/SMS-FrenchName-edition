# patch_notes_palettes.md — Extended palettes (Big Zam extraction) + "FrenchName" title

Target: Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (SFC, Japan),
clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`.

Deliverables (built by `tools/mkpatch3.py`):
- `build/sms_palettes.bps` — clean → palettes + "FrenchName" header (patch 3 alone, for QA)
- `build/sms_full.bps` — clean → **all three**: 1f-link + dash-fix + palettes + "FrenchName"
- Output ROMs are 3 MB, SHA-1 palettes `291f6474…`, full `eb7b86f8…`.

## What this patch does

1. **Extended character palettes** (up to 32 colors/character, 12 populated: 2 defaults
   + 10 extras), selectable on the character-select screen — the exact feature from
   the Big Zam edition. The 90 extra palettes (9 characters × 10) are **extracted from
   the Big Zam ROM** and re-inserted, so they render identically.
2. **"FrenchName" ROM-header title** (offset 0xFFC0) — shows in emulator title bars,
   ROM-info dialogs, and flashcart menus. SNES checksum recomputed.

## Provenance & mechanism

This reuses sprntgd's `sms_patcher.py` palette system (in `vendor/sms-training-mode/`),
which is also what built the Big Zam edition (confirmed: BZ's non-custom diffs match the
patcher's hook sites exactly). `tools/mkpatch3.py` imports the patcher's `apply_patch`,
`PATCH_PAL`, and `read_int` and applies them non-interactively, so the injected code and
pointers are the battle-tested originals — only the color *data* differs (Big Zam's,
not BMP files).

Hook sites (all bank $C0, verified disjoint from our bank-$C1 gameplay patches — the only
base-region bytes patch 3 changes are these):
- **0x884B–0x88AC** — 1P palette-load map hook (redirects to the per-slot palette block).
- **0x8998–0x89F9** — 2P palette-load map hook.
- **0xA630** — character-select confirm hook → `JSL $E8:000A` (palette select + default
  stage select).
- Appended: bank **$E8** (file 0x280000) — the selection/stage code at 0x28000A, then
  the palette data block from 0x281000. Per character: `0x1000` bytes = 32 slots × `0x80`;
  slot layout `[enable-flag word, pad, icon 4×BGR555 @+0x8, character 16 @+0x10,
  projectile 16 @+0x30]`. Defaults (slots 0–1) copied from each character's manifest
  ($E0:0238+id*2); extras (slots 2–11) lifted from the Big Zam block at file 0x2A0000.
- **0xFFC0** header title, **0xFFDC/DE** checksum.

## Selection (character-select screen)

Because the patch repurposes **Start / L / R as color-range modifiers**, you now confirm
a character with a **face button**, and the button (+modifier) chooses the color:

| Buttons | Color |
|---|---|
| A | 0 (default 1) |
| B | 1 (default 2) |
| Y | 2 |
| X | 3 |
| L + A/B/Y/X | 4–7 |
| R + A/B/Y/X | 8–15 |
| Start + A/B/Y/X | 16–31 |

Big Zam populates colors 0–11 (A/B/Y/X, L+A/B/Y/X, R+A, R+B). Higher slots are the two
defaults' fallback.

Bundled rider (part of the same indivisible patcher blob, kept as-is per request):
**random stage default** — stage select defaults to random; holding a direction while P2
confirms picks the home stage.

Roster note: the patcher (and thus Big Zam and this patch) covers **Moon…Chibimoon**
(9 characters). Saturn is not in Sailor Moon S (she is a Super S character), so she has
no extended palettes — correct and expected.

## Verification (Mesen2, deterministic RAM, CGRAM/screenshot)

1. **Selection works**: drove real character-select confirms (A/B/Y/X, L+A, R+A) for
   Uranus on the palettes ROM, reached a live match, dumped CGRAM. Uranus's character
   palette (CGRAM indices 128–142) + projectile (164–174) **differ per confirming
   button; all six tested selections are distinct**. Screenshots confirm visible recolor
   (e.g. A = default navy, R+A = silver).
2. **Faithful extraction**: `sms_palettes` and `sms_full` produce **byte-identical CGRAM**
   for every selection (the two builds share the palette block).
3. **Header**: applied ROM header reads `…S FrenchName`.
4. **No gameplay regression on the combined build** (`sms_full`, savestate-driven):
   - 1f-link: dash-out@100, only press-115 combos (114 whiffs) — unchanged.
   - Dash-fix: reversal-dash meaty connects (P1 → hitstun 0x16) — unchanged.
   - Base-region diff stacked→full = only the four bank-$C0 hook sites + header; our
     bank-$C1 patch bytes (0x1874D/E, 0x188ED/E, 0x1BE20–31) are intact.
5. **BPS round-trips**: `flips --apply` on a fresh clean ROM reproduces both builds
   byte-for-byte.

## Not included (scoped follow-up): on-screen title-screen text

Investigated fully. Big Zam's "BIG ZAM EDITION!!" subtitle and "©MOONLIGHT FIGHT SOCIETY"
credit are **custom letter-tile graphics injected by its 12 KB of custom code** (file
0x1E38–0x4CAC) — the title screen has **no reusable Latin font** (the credit lines are
baked single-purpose graphic tiles, and the subtitle graphic decompresses from an
identical blob then is overwritten by BZ's code). Adding on-screen "FrenchName" therefore
means authoring custom 4bpp letter tiles + an injection hook from scratch (a real
graphics-hacking task, ~a few hours, non-trivial risk), not a simple tilemap edit. The
**header-title identification is shipped** (the practical way a ROM is identified in
emulators/flashcarts); on-screen text is available as a follow-up if wanted.

## Applying

```
flips --apply build/sms_palettes.bps <clean ROM> <out>   # palettes + header only
flips --apply build/sms_full.bps     <clean ROM> <out>   # 1f-link + dashfix + palettes + header
```
