# How a patch is actually built

**What this is.** The mechanics of this project's patch pipeline, end to end:
what a `mkpatchN.py` does, what the assembler is for, what `flips` does and does
not do, and why the rules around all of it exist. Written because the pipeline is
mine and nobody else should have to reverse-engineer it from the builders.

**The short version, and one correction.** A builder does not emit a patch. It
reads the clean ROM, edits a `bytearray` in memory, and writes a **complete
patched `.sfc`**. Only afterwards does `flips` come in — and it does not *inject*
anything: it **diffs** clean against patched and writes that delta as a `.bps`.
The `.bps` is not "the stub bytes"; it is every byte the two images disagree on,
which for a code patch means the hook, the appended bank *and* the header
checksum.

```
    clean.sfc ──► mkpatchN.py ──► patched.sfc ──► flips --create --bps ──► patch.bps
                  (all the work)                  (a diff, nothing more)
                                                                              │
    a player, later:   clean.sfc + patch.bps ──► flips --apply ──► the same patched.sfc
```

That round trip is exactly what `tools/checkpatchmap.py` re-derives, and why a
recorded SHA-1 can be checked at all.

---

## 1. Two kinds of patch

**Data edits** — most of them. No assembler, no new code, often a single byte:

| Patch | The whole edit |
|---|---|
| 5 (dash distance) | two bytes: the operand of `LDA #$0B00` at `0x188E9` |
| 7 (Pluto 5HP) | one byte: a box height in bank `$8A` |
| 8 (Venus throw tech) | one byte: `byte5` of one throw-hold script step |
| 9 (Neptune fireball) | four bytes: `y_off` in four hit-box entries |

This is what "the engine is data-driven" buys you (`sms_data_architecture.md`
§0): most balance work is writing numbers into records the game already walks.

**Code hooks** — patches 4, 10, 10b, 11, 12, 13, 14. These need code that does not
exist, so they add a bank and redirect the game into it.

---

## 2. A code hook, line by line (patch 12)

`tools/mkpatch12.py`, with the measured result of each step:

```python
data = bytearray(open(src, "rb").read())      # 1. the ROM, in memory
data = trim_banks(data)                       # 2. drop trailing empty banks
if data[HOOK:HOOK+4] != HOOK_OLD:             # 3. REFUSE if the site is not what we think
    raise ValueError(...)
bankbase, bank = next_bank(data)              # 4. first free bank → 0x280000, SNES $E8
body, _ = A.assemble(_stub().splitlines(), off, bank)     # 5. assemble the stub
tail = HOOK_OLD + JML(HOOK_CONT)              # 6. the displaced bytes, replayed, then jump back
write_bank(data, bankbase, body + tail)       # 7. append it
data[HOOK:HOOK+4] = JML(bankbase)             # 8. rewrite the hook site
data = pad_to_size_multiple(data)             # 9. round the image up
fix_checksum(data)                            # 10. the header must agree with the bytes
open(out, "wb").write(data)
```

Measured, on the clean ROM:

```
hook  $80:8377   45 64 25 5c   →   5c 00 00 e8        JML $E8:0000
bank  $E8 at file 0x280000, 322 bytes:
        +0x000  314 bytes of assembled stub
        +0x13A  45 64 25 5c                            the displaced `eor $64 / and $5C`
        +0x13E  5c 7b 83 80                            JML $80:837B — back to the game
image 0x280000 → 0x300000        sha1 614f318e…
```

**The hook is the whole trick.** You cannot insert code into a ROM — every
address after the insertion point would move. So you *overwrite* an instruction
with a jump to somewhere empty, and the first thing your code does at the end is
perform the instruction you overwrote and jump back. The overwritten bytes are
"displaced", and replaying them is what makes the patch invisible to the rest of
the game.

Which is why the size of what you displace matters: a `jsr` is 3 bytes and a
`jsl`/`jml` is 4, so a hook that replaces a `jsr` has to displace a neighbouring
instruction too, and replay both. Patch 12 displaces exactly four bytes
(`eor $64 / and $5C`) because `JML` needs four.

---

## 3. What the assembler is, and is not

`tools/asm65816.py` is a **two-pass 65816 assembler of about 200 lines**, written
for this project. It is not a toolchain: it implements the addressing modes the
stubs actually use, and rejects anything else rather than guessing.

Two things about it are worth knowing before writing a stub:

* **Immediate width follows the M/X flags**, tracked through `rep`/`sep` — not
  the number of hex digits you typed. `lda #$00` assembles to two bytes in 8-bit
  A and three in 16-bit, which is correct and is also the classic way to corrupt
  a stub if you forget which mode you are in.
* **Addressing modes are spelled in the mnemonic**, because there is no operand
  parser: `lda_dp`, `sta_y`, `lda_idpy`, `sta_sr`. Ugly, deliberate, and the
  reason a typo is a `ValueError` at build time instead of a wrong opcode.

The stub itself is a Python f-string (see `_player()` in patch 12, which unrolls a
per-character compare chain). Generating assembly from Python is what makes a
nine-way table cheap, and it is the only "code generation" in the pipeline.

---

## 4. The guard rails, and the bug each one remembers

Every one of these exists because something went wrong once:

| Guard | What it stops |
|---|---|
| `require_source` — SHA gate | patching the wrong file. The source is hashed unconditionally; only `--stacked` allows a non-clean input, and even then the file must *look* like an SNES image (#12, #66) |
| `check_not_inplace` | `src == out`, which silently destroys the input (#56) |
| the hook-bytes assertion | patching an offset that no longer holds what you think — every builder checks the bytes it is about to displace |
| `write_bank` virgin check | writing over an existing appended bank, i.e. someone chained standalone BPS files (#27) |
| `next_bank` | hardcoding `$E8`; the bank is *found*, so builders chain |
| `trim_banks` + `pad_to_size_multiple` | image growth compounding down a chain |
| `fix_checksum` | a header that disagrees with the bytes — hangs at power-of-two sizes (#9) |

---

## 5. Bundles: chain the builders, never the patches

Every standalone `.bps` is a diff against the **clean** ROM, and every
bank-appending patch claims **the first free bank, which is always `$E8`**. Apply
two of them in sequence and the second silently overwrites the first one's code
while the first one's hook still jumps there.

So a bundle is built by chaining the **builders**, each finding the next free
bank for itself:

```bash
python3 tools/mkpatch.py   0x05 "$T/r1.sfc"
python3 tools/mkpatch2.py  --stacked "$T/r1.sfc" "$T/r2.sfc"
…
./tools/Flips/flips --create --bps "$CLEAN" "$OUT" build/sms_reference_v2.bps
```

`--stacked` is required on every step after the first: it is what tells the SHA
gate the input is deliberately not the clean ROM. The committed recipes
(`tools/build_ref_v1.sh`, `build_ref_v2.sh`, `build_v022.sh`, `build_rev.sh`) are
the authority on what each bundle contains.

`tools/checkpatchmap.py` proves both halves of this: the in-place regions of all
19 standalone patches are pairwise disjoint, and every bank-appending one starts
at `0x280000` — the collision, measured rather than remembered.

---

## 6. How a patch proves it works

1. **The builder's own asserts** — hook bytes, bank guards, knob ranges.
2. **A fingerprint.** Each builder exports `SIG = [(offset, byte), …]` of bytes
   that survive stub-layout and bank changes; `tools/mksigs.py --write` renders
   those into the regression suite's detection table, so the suite knows which
   patches are in a ROM it is handed. Never hand-edit that table — a hand-pinned
   byte silently skipped eleven tests for a week.
3. **The regression suite** (`tools/test_regression.lua`, in Mesen): engine
   invariants plus per-patch behavioural tests, dual-mode where a patch changes
   an expectation.
4. **Byte identity.** Any refactor that should not change output must reproduce
   the recorded SHA-1s — including through every env knob that alters emitted
   bytes, not just the default path.

---

## 7. If you are writing patch 19

Start from the smallest builder that resembles your case — `mkpatch5.py` for a
data edit, `mkpatch12.py` for a hook — and keep its shape. Then:

* find the site and **assert its vanilla bytes** in the builder;
* if you need code, write the stub as a string, assemble it, append a bank;
* export a `SIG` and run `mksigs.py --write`;
* add the row to `docs/project/patch_notes.md`'s edit-region map — measured, not
  intended: `checkpatchmap.py` will diff your `.bps` against it;
* build the bundles that include it and check their hashes moved only where you
  expected.

The rule underneath all of it: **never patch in place, never chain standalone
BPS, and never record a number you did not measure.**
