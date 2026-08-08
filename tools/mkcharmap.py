#!/usr/bin/env python3
"""Generate one per-character ROM map per fighter, measured from the clean ROM.

  python3 tools/mkcharmap.py            # write docs/game/characters/
  python3 tools/mkcharmap.py --check    # fail if what is on disk is out of date

WHY THIS IS GENERATED. The obvious way to answer "give me a ROM map per
character" is nine hand-written files — and nine files whose only per-character
content is a dozen addresses would be 95% identical prose, drifting apart the
first time anyone corrected one of them. Everything below is READ OUT OF THE ROM
at generation time instead, so the pages cannot disagree with the cartridge or
with each other, and `--check` makes that enforceable from a build script.

The engine-wide map those addresses hang off — the object struct, the box
format, the damage tables, the pipelines — is docs/game/sms_data_architecture.md
and the one-page card docs/game/sms_quickref.md; nothing here repeats them.

Two derivations are worth naming because they are not obvious:

* **Cel counts.** A character's cel records end where the NEXT character's
  pose->cel list begins — not where the next character's cel-record pointer is,
  which is a different (later) address. Chibi Moon, being last, has no next
  character, so her records are walked until a 5-byte entry stops looking like
  [src24][len16]; her record 0 is an all-zero sentinel and is skipped, which an
  earlier attempt tripped over (it stopped at once and reported zero cels).
  Both methods are cross-checked here against a hand census in ASSERT_CELS.

* **Act tables are NOT counted.** The per-character table at $C0:0000+id*2 holds
  u16 script pointers, but entries may point below the table (shared scripts), so
  "the table ends at the lowest pointer" gives 7 entries for Uranus, which is
  nonsense. The address is published; the count is not, because no static
  derivation for it survived scrutiny.
"""
import argparse
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom  # noqa: E402

OUT_DIR = REPO / "docs" / "game" / "characters"

NAMES = {1: "Moon", 2: "Mercury", 3: "Mars", 4: "Jupiter", 5: "Venus",
         6: "Uranus", 7: "Neptune", 8: "Pluto", 9: "Chibi Moon"}
SLUG = {1: "moon", 2: "mercury", 3: "mars", 4: "jupiter", 5: "venus",
        6: "uranus", 7: "neptune", 8: "pluto", 9: "chibimoon"}
JP = {1: "セーラームーン", 2: "セーラーマーキュリー", 3: "セーラーマーズ",
      4: "セーラージュピター", 5: "セーラーヴィーナス", 6: "セーラーウラヌス",
      7: "セーラーネプチューン", 8: "セーラープルート", 9: "ちびムーン"}

# The cancellable light-recovery act set per character (docs/game/sms_engine_internals.md
# §2) — this game's links live in these frames. Not derivable from the ROM statically.
CANCEL = {1: "42 48 54 58", 2: "41 46 53 57", 3: "42 49 55 59", 4: "42 47 53 57",
          5: "41 45 51 55", 6: "42 48 54 58", 7: "41 45 56 5A", 8: "41 49 55 59",
          9: "41 47 53 57"}

# Independent census from docs/game/sms_all_boxes.json (extract_sms_hitboxes.py),
# asserted against the derivation above — a silent off-by-one here would publish
# nine wrong pages.
ASSERT_BOXES = {
    1: {'hit': 17, 'hurt': 89, 'coll': 6},
    2: {'hit': 22, 'hurt': 87, 'coll': 6},
    3: {'hit': 33, 'hurt': 96, 'coll': 6},
    4: {'hit': 26, 'hurt': 104, 'coll': 6},
    5: {'hit': 18, 'hurt': 88, 'coll': 6},
    6: {'hit': 21, 'hurt': 81, 'coll': 6},
    7: {'hit': 25, 'hurt': 96, 'coll': 6},
    8: {'hit': 21, 'hurt': 77, 'coll': 6},
    9: {'hit': 16, 'hurt': 76, 'coll': 6},
}

# Independent hand census of cel counts, used as a tripwire on the derivation.
ASSERT_CELS = {1: 103, 2: 105, 3: 114, 4: 113, 5: 107, 6: 99, 7: 120, 8: 92, 9: 85}

ROM = open(clean_rom(), "rb").read()


def r8(o):  return ROM[o]
def r16(o): return ROM[o] | ROM[o + 1] << 8
def r24(o): return ROM[o] | ROM[o + 1] << 8 | ROM[o + 2] << 16
def f(snes): return snes & 0x3FFFFF


def bgr555(word):
    r = (word & 31) * 255 // 31
    g = ((word >> 5) & 31) * 255 // 31
    b = ((word >> 10) & 31) * 255 // 31
    return f"#{r:02x}{g:02x}{b:02x}"


def palette(snes):
    base = f(snes)
    return [bgr555(r16(base + i * 2)) for i in range(16)]


def boxes(cid):
    """(base, count) for hit / hurt / coll, from the bank-$8A pointer tables.

    Per character the three tables are CONTIGUOUS and in that order, so each
    one's length is bounded by the next table's base — hit by hurt, hurt by coll,
    coll by the NEXT character's hit (and, for Chibi Moon, by the first
    projectile table at $8A:FBD9). Counting a table against the next entry of its
    OWN pointer table instead gives ~200 boxes per character, which is how this
    was caught.
    """
    hit = r16(f(0x8AC1F1) + cid * 2)
    hurt = r16(f(0x8AC229) + cid * 2)
    coll = r16(f(0x8AC23D) + cid * 2)
    nxt_hit = r16(f(0x8AC1F1) + (cid + 1) * 2) if cid < 9 else 0xFBD9
    out = {"hit": (hit, (hurt - hit) // 8),
           "hurt": (hurt, (coll - hurt) // 16),
           "coll": (coll, (nxt_hit - coll) // 8)}
    for kind, (base, n) in out.items():
        assert n == ASSERT_BOXES[cid][kind], \
            f"{NAMES[cid]} {kind}: derived {n}, census says {ASSERT_BOXES[cid][kind]}"
    return out


def cel_end(cid):
    if cid < 9:
        return r16(f(0xCB0000) + (cid + 1) * 4)          # next char's pose->cel list
    rec, k = r16(f(0xCB0000) + cid * 4 + 2), 1           # last char: walk past the zero record
    while True:
        src, ln = r24(f(0xCB0000) + rec + k * 5), r16(f(0xCB0000) + rec + k * 5 + 3)
        if not (0xCB0000 <= src <= 0xDD0000 and 0 < ln <= 0x4000):
            return rec + k * 5
        k += 1


def gather(cid):
    man = f(0xE00000) + r16(f(0xE00238) + cid * 2)
    proc = r16(f(0xC100A6) + cid * 2)
    proc_next = r16(f(0xC100A6) + (cid + 1) * 2) if cid < 9 else 0xBE00
    pose = r16(f(0x84809C) + cid * 2)
    pose_next = r16(f(0x84809C) + (cid + 1) * 2)
    p2c, celrec = r16(f(0xCB0000) + cid * 4), r16(f(0xCB0000) + cid * 4 + 2)
    ncels = (cel_end(cid) - celrec) // 5
    assert ncels == ASSERT_CELS[cid], f"{NAMES[cid]}: cel count {ncels} != census {ASSERT_CELS[cid]}"
    return dict(
        cid=cid, manifest=0xE00000 + (man - f(0xE00000)), d48=r8(man),
        pal0=r24(man + 1), pal1=r24(man + 4), icon_pal=r24(man + 7),
        obj_pal=r24(man + 10), payload=r24(man + 13),
        proc=proc, proc_size=proc_next - proc,
        acts=r16(cid * 2), pose=pose, nposes=(pose_next - pose) // 4,
        p2c=p2c, celrec=celrec, ncels=ncels,
        oam=r24(f(0x848000) + cid * 3),
        boxes=boxes(cid),
        movelist=r24(f(0xE0021A) + cid * 3),
        throws=throw_tables(cid, proc, proc_next),
        holds=hold_scripts(cid, proc, proc_next),
    )


def _scan(pattern, lo, hi):
    """Every 'ldy #imm16 / jsr <pattern>' inside [lo,hi) of bank $C1."""
    out, base = [], f(0xC10000)
    for off in range(lo, hi - 5):
        if ROM[base + off] == 0xA0 and ROM[base + off + 3:base + off + 6] == pattern:
            out.append(r16(base + off + 1))
    return sorted(set(out))


def throw_tables(cid, lo, hi): return _scan(b"\x20\x5a\x05", lo, hi)   # jsr $055A
def hold_scripts(cid, lo, hi): return _scan(b"\x20\xe5\x06", lo, hi)   # jsr $06E5


def page(d):
    cid = d["cid"]
    n, slug = NAMES[cid], SLUG[cid]
    p0, p1 = palette(d["pal0"]), palette(d["pal1"])
    sound0 = 49 + (cid - 1) * 5
    hit, hurt, coll = d["boxes"]["hit"], d["boxes"]["hurt"], d["boxes"]["coll"]
    swatch = lambda pal: " ".join(f"`{c}`" for c in pal)
    L = []
    A = L.append
    A(f"# {n} — per-character ROM map")
    A("")
    A(f"**charID {cid}** · {JP[cid]} · clean ROM `bc0e29ee…` · file offset = SNES & `0x3FFFFF`")
    A("")
    A("> **Generated** by `tools/mkcharmap.py` — every address on this page is read out")
    A("> of the cartridge, not transcribed. Do not hand-edit. The engine-wide map these")
    A("> addresses hang off (the object struct, the box format, the damage pipeline) is")
    A("> [`../sms_data_architecture.md`](../sms_data_architecture.md).")
    A("")
    A("## Where she begins — the manifest")
    A("")
    A("| | SNES | file |")
    A("|---|---|---|")
    A(f"| manifest record | `${d['manifest']:06X}` | `0x{f(d['manifest']):06X}` |")
    A(f"| palette 0 | `${d['pal0']:06X}` | `0x{f(d['pal0']):06X}` |")
    A(f"| palette 1 | `${d['pal1']:06X}` | `0x{f(d['pal1']):06X}` |")
    A(f"| win-icon palette | `${d['icon_pal']:06X}` | `0x{f(d['icon_pal']):06X}` |")
    A(f"| object palette | `${d['obj_pal']:06X}` | `0x{f(d['obj_pal']):06X}` |")
    A(f"| sprite-CHR payload | `${d['payload']:06X}` | `0x{f(d['payload']):06X}` |")
    A("")
    A(f"**First-hit defense: `{d['d48']}`** — the manifest's first byte, loaded into struct")
    A("`+0x48`. It is worth one damage-matrix column until she is first hit each round,")
    A("and it is the whole of what used to be read as damage randomness.")
    A("")
    A("### Her palettes")
    A("")
    A(f"Palette 0 — {swatch(p0)}")
    A("")
    A(f"Palette 1 — {swatch(p1)}")
    A("")
    A("Indices 0-5 (grey, outline, four skin tones) and 15 (white) are shared across the")
    A("roster; **6-11 are the costume ramp**, and they are what makes this character look")
    A("like herself.")
    A("")
    A("## Collision boxes — bank `$8A`")
    A("")
    A("| Table | SNES | file | entries |")
    A("|---|---|---|---|")
    A(f"| attack (hit) | `$8A:{hit[0]:04X}` | `0x{0xA0000 + hit[0]:06X}` | {hit[1]} × 8 B |")
    A(f"| hurt (body+head pairs) | `$8A:{hurt[0]:04X}` | `0x{0xA0000 + hurt[0]:06X}` | {hurt[1]} × 16 B |")
    A(f"| collision (push) | `$8A:{coll[0]:04X}` | `0x{0xA0000 + coll[0]:06X}` | {coll[1]} × 8 B |")
    A("")
    A("Indexed live every frame by struct `+0x40` / `+0x41` / `+0x42`. Extracted and")
    A("decoded for all nine in [`../sms_all_boxes.json`](../sms_all_boxes.json).")
    A("")
    A("## Animation — her four id-indexed layers")
    A("")
    A("| Layer | Table entry | Her data |")
    A("|---|---|---|")
    A(f"| action scripts | `$C0:0000 + {cid}*2` | act table at `$C0:{d['acts']:04X}` |")
    A(f"| pose records | `$84:809C + {cid}*2` | `$84:{d['pose']:04X}`, **{d['nposes']} poses** × 4 B |")
    A(f"| cel tables | `$CB:0000 + {cid}*4` | pose→cel `$CB:{d['p2c']:04X}`, records `$CB:{d['celrec']:04X}`, **{d['ncels']} cels** × 5 B |")
    A(f"| OAM sprite layout | `$84:8000 + {cid}*3` | `${d['oam']:06X}` |")
    A("")
    A("A pose record is `[class][hit idx][hurt idx][coll idx]`, so **the pose is what puts")
    A("her hitboxes on screen**; a cel record is `[src24][len16]`, a raw CHR block DMA'd")
    A("straight to VRAM.")
    A("")
    A("*(The act table's entry count is deliberately not published: entries may point")
    A("below the table, so no static derivation for it survived checking.)*")
    A("")
    A("## Her code — the proc block")
    A("")
    A(f"`$C1:{d['proc']:04X}`, **{d['proc_size']} bytes**, reached through the object dispatch")
    A(f"`jsr ($00A6,X)` with `X = {cid}*2`.")
    A("")
    if d["throws"]:
        A("**Close-throw tables** (4 × 8 B, indexed by attack button; the record's last byte")
        A("is the thrower's act): " + ", ".join(f"`$C1:{t:04X}`" for t in d["throws"]) + ".")
        A("")
    if d["holds"]:
        A("**Throw-hold scripts** (8 B per step; a step whose byte 5 is non-zero samples the")
        A("victim's mashing): " + ", ".join(f"`$C1:{t:04X}`" for t in d["holds"]) + ".")
        A("")
    A(f"**Cancellable light-recovery acts:** `{CANCEL[cid]}` — the frames this game's links")
    A("live in.")
    A("")
    A("## Sound and menus")
    A("")
    A("| | |")
    A("|---|---|")
    A(f"| in-match voice sound ids | `{sound0}`-`{sound0 + 3}` (id = 49 + (charID−1)×5) |")
    A(f"| BRR directory (ARAM) | `$34C0 + {cid - 1}*32` = `${0x34C0 + (cid - 1) * 32:04X}` |")
    A(f"| BRR directory (ROM) | `$E4:{0x2CC4 + (cid - 1) * 32:04X}` |")
    A(f"| character-select voice | bank id `{21 + cid}` |")
    A(f"| movelist tilemap | `${d['movelist']:06X}` (compressed, codec 1 → BG3 map) |")
    A("")
    A("## Further reading")
    A("")
    A(f"* Her moves, damages and desperation: [`../sms_specials.md`](../sms_specials.md)")
    A("* How any of these systems works: [`../sms_data_architecture.md`](../sms_data_architecture.md)")
    A("* The flat address reference: [`../annotations.md`](../annotations.md)")
    A("")
    return "\n".join(L) + "\n"


def index_page(all_d):
    L = ["# Per-character ROM maps", "",
         "One page per fighter, **generated** by `tools/mkcharmap.py` — every address is",
         "read out of the clean ROM at generation time, so these cannot drift from the",
         "cartridge or from each other. Run `mkcharmap.py --check` to prove it.", "",
         "The engine-wide map is [`../sms_data_architecture.md`](../sms_data_architecture.md);",
         "these pages hold only what differs per character.", "",
         "| charID | Character | proc block | hit / hurt / coll | poses | cels | d48 |",
         "|---|---|---|---|---|---|---|"]
    for d in all_d:
        cid = d["cid"]
        h, u, c = d["boxes"]["hit"], d["boxes"]["hurt"], d["boxes"]["coll"]
        L.append(f"| {cid} | [{NAMES[cid]}]({SLUG[cid]}.md) | `$C1:{d['proc']:04X}` ({d['proc_size']} B) | "
                 f"`{h[1]}` / `{u[1]}` / `{c[1]}` | {d['nposes']} | {d['ncels']} | "
                 f"{'**' + str(d['d48']) + '**' if d['d48'] else '0'} |")
    L += ["",
          "Two things that table says at a glance: **every character has exactly 6 push",
          "boxes**, and **first-hit defense is non-zero for only two of the nine** —",
          "Jupiter 1 and Neptune 2, which is the entire source of the \"damage varies\"",
          "folklore.", ""]
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if the files on disk differ from what would be generated")
    args = ap.parse_args()

    all_d = [gather(cid) for cid in sorted(NAMES)]
    want = {OUT_DIR / f"{SLUG[d['cid']]}.md": page(d) for d in all_d}
    want[OUT_DIR / "README.md"] = index_page(all_d)

    if args.check:
        stale = [p for p, text in want.items()
                 if not p.exists() or p.read_text(encoding="utf-8") != text]
        if stale:
            print("mkcharmap: out of date — run: python3 tools/mkcharmap.py", file=sys.stderr)
            for p in stale:
                print(f"  {p.relative_to(REPO)}", file=sys.stderr)
            sys.exit(1)
        print(f"character maps in sync ({len(NAMES)} characters)")
        return

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for p, text in want.items():
        p.write_text(text, encoding="utf-8")
    print(f"wrote {len(want)} files to {OUT_DIR.relative_to(REPO)}/")


if __name__ == "__main__":
    main()
