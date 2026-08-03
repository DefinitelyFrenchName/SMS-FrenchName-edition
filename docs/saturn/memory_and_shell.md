# SMS memory, and why Saturn wears a shell

**Written 2026-08-03**, because the question keeps coming back in the form
"couldn't we just get more memory?" — by cutting story mode, or by repackaging
into a bigger cartridge. The short answer is that **memory has never been the
reason for the shell design**, and the resource those proposals would buy is the
one resource we already have spare. This document sets out what is actually
scarce in this game, what is not, and what a "true tenth character" would really
cost.

Every number here is measured from the ROM or from a live run, not recalled.

---

## 1. The four memories, with real budgets

A SNES cartridge game has four separate spaces, and they are not
interchangeable. Conflating them is what makes "add more ROM" sound like a
solution.

| Space | Size | Ours | Verdict |
|---|---|---|---|
| **ROM** (cartridge) | 4 MB HiROM ceiling | clean 2.50 MB / 40 banks; current build **3.62 MB / 58 banks**, 384 KB spare | **not scarce** |
| **WRAM** (work RAM) | 128 KB | mostly committed; safe bytes are hard to *prove* | scarce in a subtle way |
| **VRAM** (video) | 64 KB | committed per screen | scarce, but per-screen |
| **ARAM** (audio) | 64 KB | **full** | genuinely, hard-limited scarce |

### ROM — the one we keep being offered more of

The clean ROM is 2.50 MB, banks `$C0-$E7`. The current Saturn build is 3.62 MB,
banks `$C0-$F9` — we have **appended 18 banks, ten of them Saturn's**, without
ever hitting a wall, and 6 banks (384 KB) of HiROM headroom remain unused.

Her ten banks, for scale:

| bank | contents |
|---|---|
| +0 | animation scripts (full `$C0` script-region copy) |
| +1 | pose records |
| +2 | cel tables |
| +3..+5 | her cels (136.7 KB of graphics) |
| +6 | OAM blob, palettes, stubs, records |
| +7 | **a full copy of bank `$C1`** + her proc graft |
| +8 | **a full copy of bank `$8A`** + widened box tables |
| +9 | voice bank, IPL streams, load hooks |

Note banks +7 and +8: two entire 64 KB banks spent duplicating vanilla banks,
purely so a table inside them could be made wider. That is not a space problem —
it is a *layout* problem, and it is the heart of this document.

### ARAM — the only hard wall we have actually hit

64 KB, shared by the sample directory, the sequence data, every instrument, and
both fighters' voices. Measured layout:

```
$2800-$3338  sequence data (swapped per scene)
$3400        BRR sample directory (4 bytes per entry)
$34C0        + (charID-1)*32 : the nine-character voice directory, boot-resident
$3800-$8DFF  resident instrument samples
$8E00-$9B92  swappable sample slot
$9B92-$B6FF  ~7 KB uploaded from ROM bank $E4 — looked free, is not
$B700        P1's voice bank  }  9216 bytes each
$DB00        P2's voice bank  }  (the P2 bank is what caps P1's)
      -$FE8B  end of samples
```

The largest free run anywhere in ARAM is **64 bytes**, at `$FFC0`. This is the
space that forced a real compromise: her four in-match voices came to 9900 bytes
against a 9216-byte budget, and the overflow had to be trimmed by ear. It also
produced the project's sharpest lesson — the `$9B92-$B6FF` region passed both
"nothing points at it" and "it never changes" and was **still live**, proven only
by finding its bytes in ROM bank `$E4`.

**Neither a bigger cartridge nor deleting story mode adds a single byte of
ARAM.** It is 64 KB of hardware.

### WRAM — scarce in a way that is about *proof*, not bytes

128 KB, and the interesting part is not the total. The object pool is
`$7E:1000-$17FF` — sixteen 0x80-byte slots (the script interpreter's own loop
walks `$1000` to `$1800`), of which P1 and P2 are the first two.

The difficulty is finding bytes that are provably safe. Saturn's flags live at
`$7F:F100-F109` only after two failures: `$7E:1F60-63` turned out to be written
by bank `$C3`'s menu code, and then `$7F:F100-F102` was observed being sprayed
with junk during boot by a generic pointer-driven copy loop — which is why the
flags must equal a magic value (`$A5`) rather than merely be non-zero, so that
corruption can only ever *cancel* a selection, never invent one.

### VRAM — committed, but per screen

64 KB, re-laid-out per screen, so it is less of a global constraint than a
per-feature one: the movelist tilemaps sit at word `$1000` (P1) and `$1400`
(P2), effect tiles at `$6A00`/`$7300`, the report-card portrait window at
`$0000`. Her portrait needed its own sprite list because her art does not fit
the vanilla silhouette — a VRAM *layout* constraint, again not a size one.

---

## 2. What is actually scarce: nine-wide tables

The real constraint is not any of the four memories. It is that **this game is
built around exactly nine characters, and the per-character tables are sized to
nine and immediately followed by unrelated data.** Adding a tenth row is not a
question of finding space; it is a question of moving a table and repointing
every instruction that reads it.

Measured census of the tables Saturn has had to deal with:

| Table | Address | Shape | Room for a tenth? |
|---|---|---|---|
| Movelist pointers | `$E0:021A + id*3` | 9 x 3-byte | **No** — row 10 starts exactly at `$E0:0238`, the manifest pointer table |
| Manifest pointers | `$E0:0238 + id*2` | 9 x 2-byte | No |
| Audio banks (voice + select) | `$C0:ECE7 + id*6` | ids 22-30 select, 31-39 in-match | Row 40 is 6 zero bytes; rows 41+ are other data |
| BRR voice directory | `$E4:2CC4 + (id-1)*32` | 9 x 32-byte | A tenth slot exists but holds junk, **and is unreachable** — the driver's id map stops at 93 |
| Sound ids | `49 + (charID-1)*5` | 5 per character | No — ids past 93 are dead |
| Hitbox pointers | `$8A:C1F1` | 28 entries (9 chars + objects) | Not without moving it |
| Hurt/collision pointers | `$8A:C229` / `$8A:C23D` | 10 entries each | Index 0 unused; no free char row |
| Card portrait | `$9F:94C2` | 3-byte per character | No |

The one place we genuinely needed a tenth row was the **box tables** — and the
cost is the measured example of what the user's intuition was about. We could
not extend them in place, so the build **copies all of bank `$8A` into an
appended bank**, writes widened tables into the copy, and repoints **six**
`lda #$8A / pha / plb` sites plus three table reads. One row cost a 64 KB bank
and nine patch sites. Her proc block cost the same again for bank `$C1`.

Multiply that by the eight other tables and you have the "shifting a lot of code
around, with the risk of many pointers failing" that this design avoids.

---

## 3. What the shell actually is (and is not)

A common misreading: that Saturn is somehow a partial character riding on
Uranus. She is not. **Internally she is a complete, first-class character:**

- her own object id **`0x1C`** (the proc table `$C1:00A6` has 20 unused object
  ids, `0x1C-0x2F` — object-id space was never scarce);
- her own ~4.3 KB proc block, grafted into an appended bank;
- her own animation across all four layers — scripts, pose records, cel tables,
  cels — and her own OAM sprite layout;
- her own hit/hurt/collision boxes;
- her own projectiles, palettes, card portrait, and voice.

The "shell" is only about two things: **how she is selected**, and **which
per-character table rows she borrows**. Holding L+R while confirming any of the
nine sets a flag; at the round load she is substituted into that player's object
slot. The shell character supplies nothing but a table index.

### What it costs, feature by feature

Each per-character asset needs one hook to answer "is this player Saturn?", and
the recurring hazard is that the natural key is the *character*, not the player:

| Feature | Table row borrowed | The hook, and the trap it had to avoid |
|---|---|---|
| Card portrait | `$9F:94C2` | Keyed on the sprite-list pointer — worked for the Uranus shell only, dead for the other eight. Fixed by keying on the bank plus `$7E:1E14` (which player won) |
| In-match voice | char 1's ids + directory half | The halves are per player, so borrowing char 1's is collision-free; a non-Saturn load restores the row |
| Select voice | bank id `21 + charID` | `$1B1E` names the CHARACTER, so the player comes from its three per-player writers |
| Movelist | `$E0:021A + id*3` | Two 4-byte reads, one per player, each already fed by that player's own struct — the cleanest of the four |

The pattern is consistent: **a per-player hook costs a few bytes; a per-character
key is a bug waiting for a different shell.** Testing any such fix with at least
two shells is the standing rule for exactly this reason.

---

## 4. The two radical proposals, evaluated

### Remove story mode

Frees ROM. ROM is the resource we are not short of — we have 384 KB spare and
have never been blocked by it. It frees no ARAM (hardware), no WRAM in match (a
mode that is not running consumes nothing), and — decisively — it does not widen
a single per-character table. **Cost: high. Benefit: the thing we already
have.**

There is a narrow real case for it: if we ever needed contiguous space *inside* a
specific low bank, next to an existing table, deleting a neighbour could help.
That has not happened once so far, because appending a bank and repointing has
always been cheaper.

### Repackage into a larger cartridge (6 MB, ToP-style)

Going past 4 MB means **ExHiROM**, which breaks the single mapping assumption
this entire toolchain is written against:

> `file offset = SNES address & 0x3FFFFF`

That line is in `CLAUDE.md` as ground truth, and every builder, probe, extractor
and doc address in this repo depends on it. ExHiROM also reaches its extra space
through banks `$40-$7D`, which is fussier on real hardware and flash carts. In
exchange it buys ROM — again, the resource we have spare. **This is the most
expensive possible way to obtain the thing we need least.**

---

## 5. Conclusion, and when to revisit

The shell design was not a workaround for scarce memory. Given nine-wide tables
followed by live data, it is **the cheaper engineering path on its own merits**:
a handful of per-player hooks instead of relocating and repointing a dozen
tables, with each hook independently testable and independently revertible.

Revisit this decision if — and only if — one of these becomes true:

1. **We run out of ROM banks.** 384 KB left; her whole port cost ten banks, six
   of them graphics. Not close.
2. **A feature needs a tenth row in so many tables that the hooks cost more than
   relocating them.** Four features in, the hooks are winning comfortably.
3. **Something needs more ARAM.** Neither proposal helps; that would need a
   different fix entirely (smaller samples, or displacing an instrument).

None of those is close today. The one budget that genuinely constrains us is
ARAM, and it is a hardware limit no cartridge change can lift.
EOF
echo written; wc -l docs/saturn/memory_and_shell.md