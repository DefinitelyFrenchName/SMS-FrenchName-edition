#!/usr/bin/env python3
"""Render the in-match frame — the engine loop — as a standalone HTML page.

The companion to `mkarchpage.py`: that one draws where the DATA lives, this one
draws what the CPU does with it between two vblanks. It exists because the loop
is "standard practice" right up until you read it in assembly, and then every
question — where does a hit get applied, why a frame later, where does a patch
attach — is a question about call order that prose answers slowly and a ladder
answers at a glance.

EVERYTHING HERE WAS READ OUT OF THE CARTRIDGE (2026-08-09, `tools/Dispel`), not
inferred from how such engines usually work:

  * the NMI vector chain `$00:FFEA -> $C0:FFA6 -> $80:98DB`, its state dispatch
    `jmp ($98FD,X)`, and the in-match body at `$C0:D4C9`;
  * the six sibling phase loops in `$C0:E21A-E8F5`, each a straight-line call
    list ending in a `bra` back to its own head;
  * that hit resolution is NOT a stage of the loop — it is called from inside
    the characters' own procs, 192 times (`JSL $80:BFBB`), which is why an
    attack lands a frame before the reaction it causes;
  * the patch hook sites, parsed from the edit-region map that
    `tools/checkpatchmap.py` re-derives from the shipped `.bps` files.

`--check` re-reads every instruction this page draws and fails if one moved: the
call list is recorded as (address, opcode, operand) triples, so a stage that
shifts by a byte cannot quietly stay on the diagram. Three stages are drawn as
UNIDENTIFIED because that is what they are; a grey box is worth more than a
confident guess.

  python3 tools/mkenginepage.py [out.html]               # Artifact fragment
  python3 tools/mkenginepage.py --standalone [out.html]  # opens in a browser
  python3 tools/mkenginepage.py --check                  # verify against the ROM
"""
import html
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mkarchpage                                    # the shared page identity

REPO = pathlib.Path(__file__).resolve().parent.parent
OUT_DEFAULT = pathlib.Path(__file__).with_name("sms_engine_frame.html")

# ---------------------------------------------------------------------------
# THE FRAME, as measured. Each stage: (site, kind, target, bank, name, note,
# role) — `site` is where the call instruction sits, so --check can pin it.
# role: "combat" stages exist only in the round loop; "always" run in every
# phase loop; "unknown" means exactly that.
# ---------------------------------------------------------------------------
ROUND_LOOP = 0xE255
ROUND = [
    (0xE25C, "jsl", 0x8386, 0x80, "wait for vblank",
     "spins on DP $6C until the NMI sets it — the frame gate", "always"),
    (0xE260, "jsr", 0xE071, 0xC0, "pause / start",
     "reads $1E04, +0x76 and the fresh joy1 edges", "always"),
    (0xE263, "jsr", 0x9633, 0xC0, "input + camera snapshot",
     "copies $A3/$A5 aside, indexes on joy1 held ($5C)", "unknown"),
    (0xE266, "jsl", 0x0E26, 0xC1, "apply reactions",
     "the code left on +0x47 LAST frame becomes an act", "combat"),
    (0xE26A, "jsl", 0xA05C, 0x80, "animation scripts",
     "duration into +0x06, pose into +0x05", "always"),
    (0xE26E, "jsl", 0x9C96, 0x80, "poses to boxes",
     "class +0x18, box indices +0x40/41/42 ($C0:9CCD)", "always"),
    (0xE272, "jsl", 0x2584, 0xC1, "effect pool", "the $1200 object slots", "combat"),
    (0xE276, "jsl", 0x16EE, 0xC1, "projectile pool", "the $1100/$1180 slots", "combat"),
    (0xE27A, "jsl", 0x0000, 0xC1, "object update",
     "jsr ($00A6,X) by id — hits are detected in here", "always"),
    (0xE27E, "jsl", 0x9FB8, 0x80, "resolve cels",
     "the ROM address and size the DMA will stream", "always"),
    (0xE282, "jsr", 0x8BCB, 0xC0, "world to screen",
     "+0x21 - camera $0A00 + 0x2C -> +0x28", "always"),
    (0xE285, "jsr", 0x9CE2, 0xC0, "build draw order",
     "the live object slots, listed at $0B00", "always"),
    (0xE288, "jsl", 0x9A0E, 0x80, "emit sprites",
     "sprite records -> the OAM shadow $7E:0200", "always"),
    (0xE28C, "jsr", 0xD5E8, 0xC0, "HUD producer",
     "staging $0806-$0815 — never runs in Practice", "combat"),
    (0xE28F, "jsr", 0xDB35, 0xC0, "round state", "reads $1E3D, sets $71/$1E04", "unknown"),
    (0xE292, "jsr", 0xB321, 0xC0, "stage scroll",
     "`ldx $8E / jmp ($B32B,X)` — one scroll routine per stage", "always"),
    (0xE295, "jsr", 0x8CAF, 0xC0, "unidentified", "reads flag $B1 bit 1", "unknown"),
    (0xE298, "jsr", 0x8BF9, 0xC0, "advance the RNG",
     "stirs DP $90 — the byte the misfire roll reads", "always"),
]

# The entrance/intro loop: the same spine with the combat stages absent.
ENTRANCE_LOOP = 0xE21A
ENTRANCE = [0x8386, 0x877C, 0xA05C, 0x9C96, 0x0000, 0x9FB8, 0x8BCB, 0x9CE2,
            0x9A0E, 0xD99E, 0xB321, 0x8BF9]

# The NMI side, measured the same way.
NMI = [
    (0xFFEA, "vector", "$00:FFEA", "the NMI vector", "-> $C0:FFA6"),
    (0xFFA6, "jmp", "$C0:FFA6", "trampoline", "jmp $80:98DB"),
    (0x98DB, "dispatch", "$80:98DB", "per-screen dispatch", "jmp ($98FD,X) — one handler per game state"),
    (0xD4C9, "body", "$C0:D4C9", "the in-match handler", "the five things below, then RTI"),
]
NMI_BODY = [
    (0xD4CC, 0x8448, "jsr", "queued transfers"),
    (0xD4CF, 0x9EF5, "jsl", "OAM + CGRAM -> the PPU"),
    (0xD4D3, 0x8C4D, "jsr", "unidentified"),
    (0xD4D6, 0xD56F, "jsr", "HUD uploader -> VRAM"),
    (0xD4D9, 0xB3D7, "jsr", "unidentified"),
    (0xD4DC, 0x8353, "jsr", "read the pads"),
]

# Call-site censuses: the numbers that say WHERE a thing is called from.
# All three are called through the $80 FastROM mirror, which is where this game
# executes from; $80:BFBB and $C0:BFBB are the same routine.
CENSUS = [(0x80, 0xBFBB, 192, "hit resolution", "called by the characters' procs"),
          (0x80, 0xC352, 22, "projectile collision", "same — from the procs"),
          (0x80, 0xC745, 1, "push / collision", "once, from the object update's head")]

# Which loop stage each patch attaches to. The OFFSETS are not typed here: they
# are parsed from the edit-region map in docs/project/patch_notes.md, which
# tools/checkpatchmap.py re-derives from the shipped .bps files. This table only
# says which stage a patch's hook belongs to, and why.
PATCH_STAGE = {
    "1": (0xE27A, "gates the 2HP dash cancel"),
    "1b": (0xE27A, "the same gate, one frame tighter"),
    "2": (0xE27A, "clears the stale invuln flag"),
    "5": (0xE27A, "the dash's X-speed operand"),
    "6": (0xE26E, "overrides the hurtbox index"),
    "7": (0xE26E, "one box-height byte"),
    "8": (0xE27A, "one byte of the hold script"),
    "9": (0xE27A, "the fireball's box"),
    "10": (0xE28C, "producer here, uploader in the NMI"),
    "10b": (0xE28C, "the same pair, plus glyphs"),
    "11": (0xE25C, "rides the joy_read chain"),
    "12": (0xE25C, "the next link in that chain"),
    "13": (0xE27A, "the eight damage-apply sites"),
    "14": (0xE27A, "the 7-byte tails of two of them"),
}


def read_rom():
    sys.path.insert(0, str(REPO / "tools"))
    from smspaths import clean_rom
    return open(clean_rom(), "rb").read()


def encode(kind, target, bank):
    if kind == "jsr":
        return bytes([0x20, target & 0xFF, target >> 8])
    return bytes([0x22, target & 0xFF, target >> 8, bank])


def check():
    """Re-read every instruction the page draws. A stage that moved is a page
    that lies, and the only way to notice is to pin the bytes."""
    rom, bad = read_rom(), []
    for site, kind, target, bank, name, _note, _role in ROUND:
        want = encode(kind, target, bank)
        if rom[site:site + len(want)] != want:
            bad.append(f"round loop: {name} — ${site:04X} holds "
                       f"{rom[site:site + len(want)].hex(' ')}, not {want.hex(' ')}")
    for site, target, kind, label in NMI_BODY:
        want = encode(kind, target, 0x80)
        if rom[site:site + len(want)] != want:
            bad.append(f"NMI: {label} — ${site:04X} moved")
    if (rom[0xFFEA] | rom[0xFFEB] << 8) != 0xFFA6:
        bad.append("the NMI vector no longer points at $C0:FFA6")
    if rom[0xFFA6:0xFFAA] != bytes([0x5C, 0xDB, 0x98, 0x80]):
        bad.append("$C0:FFA6 no longer jumps to $80:98DB")
    if rom[ROUND_LOOP:ROUND_LOOP + 2] != bytes([0xE2, 0x20]):
        bad.append("the round loop no longer starts with sep #$20 at $E255")
    if rom[0xE29B:0xE29D] != bytes([0x80, 0xB8]):
        bad.append("the back-edge (bra $E255) is not where it was")
    for bank, addr, n, name, _ in CENSUS:
        got = len(re.findall(re.escape(bytes([0x22, addr & 0xFF, addr >> 8, bank])), rom))
        if got != n:
            bad.append(f"{name}: {got} call sites, the page says {n}")
    return bad


def patch_regions():
    """{patch: [file offsets]} from the edit-region map — the same table
    checkpatchmap.py verifies against the .bps files."""
    text = (REPO / "docs" / "project" / "patch_notes.md").read_text(encoding="utf-8")
    out = {}
    for line in text.splitlines():
        m = re.match(r"^\|\s*\*\*([0-9]+b?)\*\*\s*\|\s*`[^`]+\.bps`\s*\|(.*?)\|", line)
        if m:
            out[m.group(1)] = [int(a, 16) for a, _ in
                               re.findall(r"`0x([0-9A-F]{5})(?:-([0-9A-F]{5}))?`", m.group(2))]
    return out


# ------------------------------------------------------------------ drawing --
# SVG text neither wraps nor shrinks: a label that is too long simply runs out of
# its box and over whatever is next to it. Both formatting bugs in the first cut
# of this page were that — an NMI label past the end of its pill, and patch pins
# stacked into the row below. So nothing here is eyeballed: every string is
# measured, boxes are sized or strings clipped to fit, row pitch is computed from
# the tallest row's contents, and `place()` ASSERTS containment at build time.
ROW_H = 46

# Per-character advance as a fraction of the font size. Monospace is exact
# (Menlo/SF Mono are 0.60em); the sans figures are a deliberate over-estimate, so
# the check errs toward clipping a label rather than letting one overflow.
NARROW = set("ijltfrI.,:;'|!()[]{} ")
WIDE = set("mwMW@")


def text_w(s, size, mono=False):
    if mono:
        return len(s) * size * 0.60
    w = 0.0
    for ch in s:
        if ch in NARROW:
            w += 0.34
        elif ch in WIDE:
            w += 0.92
        elif ch.isupper() or ch.isdigit() or ch == "$":
            w += 0.66
        else:
            w += 0.55
    return w * size


CLIPPED = []


def clip(s, room, size, mono=False):
    """Trim to what actually fits — and REPORT it.

    An ellipsis in a diagram is not a design decision, it is the safety net
    firing: it means a label was written longer than the space it was given, and
    the reader loses the end of a sentence with no way to know what was there.
    The trim still happens (an overflowing label is worse), but every one is
    recorded and the build refuses to finish while any remain, so the fix lands
    on the STRING or the BOX rather than on the reader.
    """
    if text_w(s, size, mono) <= room:
        return s
    full = s
    while s and text_w(s + "…", size, mono) > room:
        s = s[:-1]
    out = (s.rstrip(" ,;-") + "…") if s else "…"
    CLIPPED.append((full, room))
    return out


class Fig:
    """Collects the SVG and refuses to hand back a drawing whose text escapes a
    box. `place` takes the room available; if a caller passes room the parent
    rect does not have, that is the caller's bug and it fails loudly here."""

    def __init__(self, w, h, label):
        self.w, self.h, self.label, self.bad = w, h, label, []
        self.p = [f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="{esc(label)}">']

    def add(self, markup):
        self.p.append(markup)

    def place(self, s, x, y, cls, size, room, mono=False, anchor="start"):
        s = clip(s, room, size, mono)
        w = text_w(s, size, mono)
        left = x if anchor == "start" else x - w
        if left < -1 or left + w > self.w + 1:
            self.bad.append(f"{self.label[:28]}: {s!r} runs outside the viewBox")
        a = ' text-anchor="end"' if anchor == "end" else ""
        self.p.append(f'<text class="{cls}" x="{x}" y="{y}"{a}>{esc(s)}</text>')
        return w

    def done(self):
        if self.bad:
            raise SystemExit("layout: " + "; ".join(self.bad))
        return "".join(self.p) + "</svg>"


def esc(s):
    return html.escape(s, quote=False)


def fig_frame():
    """The spine: the loop's stages as a ladder, the NMI beside it, and the one
    handshake that ties them together. Column widths are derived from the widest
    string that has to sit in them."""
    n = len(ROUND)
    lane_x = 36
    addr_w = max(text_w(f"{k.upper()} ${b:02X}:{t:04X}", 11, True) for _s, k, t, b, *_ in ROUND)
    name_w = max(text_w(nm, 12.5) for *_x, nm, _nt, _r in ROUND)
    lane_w = int(26 + max(name_w, 330) + 24 + addr_w + 26) + 2
    nmi_label_w = max(text_w(lb, 11.5) for _s, _t, _k, lb in NMI_BODY)
    nmi_w = int(24 + nmi_label_w + 18 + text_w("$D56F", 11, True) + 24) + 4
    nmi_x = lane_x + lane_w + 64
    w = nmi_x + nmi_w + 36
    h = 96 + n * ROW_H + 46
    f = Fig(w, h, f"One in-match frame: the main loop at $C0:E255 runs {n} stages, "
            "the NMI at $C0:D4C9 runs six, and the loop waits on DP $6C for it.")
    f.add('<defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
          'markerHeight="7" orient="auto"><path d="M0 0L10 5L0 10z" fill="currentColor"/>'
          '</marker></defs>')
    f.place("MAIN LOOP · $C0:E255 · one pass = one frame", lane_x, 26, "lane", 10.5, lane_w)
    f.place("NMI · $C0:D4C9", nmi_x, 26, "lane", 10.5, nmi_w)
    f.add(f'<rect class="lane-bg" x="{lane_x}" y="40" width="{lane_w}" height="{n * ROW_H + 20}" rx="10"/>')
    f.add(f'<rect class="lane-bg nmi" x="{nmi_x}" y="40" width="{nmi_w}" '
          f'height="{len(NMI_BODY) * 34 + 30}" rx="10"/>')

    box_x, box_w = lane_x + 12, lane_w - 24
    txt_room = box_w - 28 - addr_w - 24            # what is left beside the addresses
    for i, (site, kind, target, bank, name, note, role) in enumerate(ROUND):
        y = 58 + i * ROW_H
        f.add(f'<g class="stage s-{role}">')
        f.add(f'<rect x="{box_x}" y="{y}" width="{box_w}" height="{ROW_H - 10}" rx="6"/>')
        f.place(name, box_x + 14, y + 17, "sname", 12.5, txt_room)
        f.place(note, box_x + 14, y + 31, "snote", 11, txt_room)
        f.place(f"{kind.upper()} ${bank:02X}:{target:04X}", box_x + box_w - 14, y + 17,
                "saddr", 11, addr_w + 8, mono=True, anchor="end")
        f.place(f"at ${site:04X}", box_x + box_w - 14, y + 31,
                "ssite", 10.5, addr_w + 8, mono=True, anchor="end")
        f.add("</g>")
        if i < n - 1:
            f.add(f'<line class="flow" x1="{lane_x + 22}" y1="{y + ROW_H - 10}" '
                  f'x2="{lane_x + 22}" y2="{y + ROW_H}" marker-end="url(#ar)"/>')

    back_y = 58 + n * ROW_H
    f.add(f'<path class="flow back" d="M{lane_x + 22} {back_y - 8} L{lane_x - 8} {back_y - 8} '
          f'L{lane_x - 8} 62 L{lane_x + 6} 62" marker-end="url(#ar)"/>')
    f.place("bra $E255 — the next frame", lane_x + 30, back_y + 12, "edge", 11, lane_w - 40, mono=True)

    nb_x, nb_w = nmi_x + 12, nmi_w - 24
    nmi_addr_w = text_w("$D56F", 11, True) + 6
    for i, (site, target, kind, label) in enumerate(NMI_BODY):
        y = 58 + i * 34
        f.add('<g class="stage s-nmi">')
        f.add(f'<rect x="{nb_x}" y="{y}" width="{nb_w}" height="26" rx="5"/>')
        f.place(label, nb_x + 12, y + 17, "sname", 11.5, nb_w - 24 - nmi_addr_w - 12)
        f.place(f"${target:04X}", nb_x + nb_w - 12, y + 17, "saddr", 11,
                nmi_addr_w, mono=True, anchor="end")
        f.add("</g>")

    hs_y = 58 + len(NMI_BODY) * 34 + 22
    f.add(f'<path class="flow hand" d="M{nb_x + 40} {hs_y} L{nb_x + 40} {hs_y + 24} '
          f'L{lane_x + lane_w + 30} {hs_y + 24} L{lane_x + lane_w + 30} 74 '
          f'L{lane_x + lane_w - 14} 74" marker-end="url(#ar)"/>')
    f.place("sets DP $6C", nb_x + 48, hs_y + 18, "edge hand", 11, nmi_w - 60, mono=True)
    return (f.done(),
            "<b>One frame.</b> The loop does not poll a timer: it spins in "
            "<code>$80:8386</code> until the NMI writes DP <code>$6C</code>, then runs its "
            "stages in this order and branches back. The pad read at the bottom of the NMI "
            "leaves the held state in <code>$5C-$5F</code> and the press edges in "
            "<code>$60</code>/<code>$62</code>. Every address is the instruction's own site, "
            "so a stage that moves fails <code>--check</code>.")


def fig_phases():
    """Two loops, same spine — the round loop is the entrance loop plus combat."""
    rows = [(s[2], s[4], s[6]) for s in ROUND]
    name_w = max(text_w(nm, 12.5) for _t, nm, _r in rows)
    name_x, addr_x = 24, int(24 + name_w + 28)
    col_w, gap = 150, 80
    col1 = addr_x + 60
    col2 = col1 + col_w + gap
    delta_x = col2 + col_w + 22
    w = int(delta_x + text_w("added by the round", 11, True) + 24)
    h = 52 + len(rows) * 30
    f = Fig(w, h, "The entrance loop and the round loop run the same stage list; "
            "the round loop adds the combat stages.")
    f.place("ENTRANCE $C0:E21A", col1, 26, "lane", 10.5, col_w)
    f.place("ROUND $C0:E255", col2, 26, "lane", 10.5, col_w)
    for i, (target, name, role) in enumerate(rows):
        y = 44 + i * 30
        in_entrance = target in ENTRANCE
        f.place(name, name_x, y + 14, "prow", 12.5, name_w + 4)
        f.place(f"${target:04X}", addr_x, y + 14, "paddr", 11, 60, mono=True)
        for cx, present in ((col1, in_entrance), (col2, True)):
            cls = "on" if present else "off"
            f.add(f'<rect class="pcell {cls} s-{role}" x="{cx}" y="{y}" '
                  f'width="{col_w}" height="20" rx="4"/>')
        if not in_entrance:
            f.place("added by the round", delta_x, y + 14, "pdelta", 11, w - delta_x - 12, mono=True)
    return (f.done(),
            "<b>Six phase loops, one stage list.</b> The engine has a loop per match phase "
            "(<code>$C0:E21A</code>, <code>E255</code>, <code>E2E2</code>, <code>E30F</code>, "
            "<code>E41E</code>, <code>E8D3</code>). They call the same routines in the same "
            "order; what a phase does <em>not</em> do is what it leaves out. The entrance "
            "animates and draws — it just never fights. (It also runs two stages of its own, "
            "<code>$C0:877C</code> and <code>$C0:D99E</code>, which the round loop has no use for.)")


def fig_hits():
    """Where a hit actually happens — the answer to 'why a frame later'."""
    bw, colgap = 250, 70
    cols = [30, 30 + bw + colgap, 30 + 2 * (bw + colgap)]
    w, h = cols[2] + bw + 150, 330
    f = Fig(w, h, "Hit resolution is called from inside each character proc, 192 times; "
            "the reaction it causes is applied at the top of the next frame.")
    f.add('<defs><marker id="ar2" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
          'markerHeight="7" orient="auto"><path d="M0 0L10 5L0 10z" fill="currentColor"/>'
          '</marker></defs>')
    nodes = [(cols[0], 60, "object update", "$C1:0000", "stage 9 of the frame", "obj"),
             (cols[0], 140, "proc dispatch", "$C1:0080", "jsr ($00A6,X) by object id", "obj"),
             (cols[0], 220, "the character's proc", "$C1:79F2", "Uranus, 5040 bytes", "obj"),
             (cols[1], 220, "hit resolution", "$80:BFBB", "192 call sites, all bank $C1", "hit"),
             (cols[2], 220, "pending code", "+0x47", "written on the VICTIM", "hit"),
             (cols[2], 60, "apply reactions", "$C1:0E26", "stage 4 — NEXT frame", "obj")]
    for x, y, name, addr, note, cls in nodes:
        aw = text_w(addr, 11, True) + 8
        f.add(f'<g class="node {cls}"><rect x="{x}" y="{y}" width="{bw}" height="58" rx="7"/>')
        f.place(name, x + 16, y + 23, "sname", 12.5, bw - 32 - aw)
        f.place(note, x + 16, y + 41, "snote", 11, bw - 32)
        f.place(addr, x + bw - 16, y + 23, "saddr", 11, aw, mono=True, anchor="end")
        f.add("</g>")
    mid = cols[0] + bw // 2
    for x1, y1, x2, y2 in ((mid, 118, mid, 140), (mid, 198, mid, 220),
                           (cols[0] + bw, 249, cols[1], 249),
                           (cols[1] + bw, 249, cols[2], 249)):
        f.add(f'<line class="flow" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" marker-end="url(#ar2)"/>')
    f.place("JSL", cols[0] + bw + 12, 242, "edge", 11, colgap - 16, mono=True)
    f.place("writes", cols[1] + bw + 8, 242, "edge", 11, colgap - 10, mono=True)
    back = cols[2] + bw - 30
    f.add(f'<path class="flow next" d="M{back} 220 L{back} 118" marker-end="url(#ar2)"/>')
    f.place("one frame later", back + 10, 170, "edge next", 11, w - back - 18, mono=True)
    return (f.done(),
            "<b>Nothing in the frame list checks a hitbox.</b> Detection lives in the "
            "attacker's own proc — <code>JSL $80:BFBB</code>, 192 sites, every one of them in "
            "bank <code>$C1</code> — and it leaves a code on the victim's <code>+0x47</code>. "
            "The loop's fourth stage turns that into an act on the FOLLOWING pass, which is "
            "the whole reason this engine's timing reads one frame late and why a move "
            "announced only on its first active frame loses the guard race.")


def fig_patches():
    """The same ladder, with every shipped patch pinned to the stage it changes.
    Row height is computed from the busiest stage — patch 13 and friends all hang
    off the object update, and a fixed pitch is what stacked them into each other."""
    regions = patch_regions()
    by_stage = {}
    for patch, (stage, why) in PATCH_STAGE.items():
        by_stage.setdefault(stage, []).append((patch, why, regions.get(patch, [])))
    rows = [s for s in ROUND if s[0] in by_stage]
    stage_w, pin_w, pin_h, pin_gap = 300, 330, 22, 5
    pin_x = 24 + stage_w + 30
    w = pin_x + 2 * pin_w + 20 + 30
    pitch = []
    for site, *_ in rows:
        lines = -(-len(by_stage[site]) // 2)                # ceil
        pitch.append(max(60, lines * (pin_h + pin_gap) + 16))
    h = 28 + sum(pitch) + 12
    f = Fig(w, h, "Each shipped patch pinned to the loop stage it changes.")
    y = 22
    for row, (site, _k, target, bank, name, _n, role) in zip(pitch, rows):
        f.add(f'<g class="stage s-{role}"><rect x="24" y="{y}" width="{stage_w}" '
              f'height="{row - 12}" rx="6"/>')
        aw = text_w(f"${bank:02X}:{target:04X}", 11, True) + 8
        f.place(name, 40, y + 22, "sname", 12.5, stage_w - 32 - aw)
        f.place(f"${bank:02X}:{target:04X}", 24 + stage_w - 16, y + 22, "saddr", 11,
                aw, mono=True, anchor="end")
        f.place(f"stage {ROUND.index(next(r for r in ROUND if r[0] == site)) + 1}",
                40, y + 40, "snote", 11, stage_w - 60)
        f.add("</g>")
        pins = sorted(by_stage[site], key=lambda t: (len(t[0]), t[0]))
        for j, (patch, why, offs) in enumerate(pins):
            px = pin_x + (j % 2) * (pin_w + 20)
            py = y + (j // 2) * (pin_h + pin_gap)
            f.add(f'<g class="pin"><rect x="{px}" y="{py}" width="{pin_w}" '
                  f'height="{pin_h}" rx="11"/>')
            lab = f"patch {patch}"
            lw = f.place(lab, px + 14, py + 15, "pnum", 11, 76, mono=True)
            f.place(why, px + 14 + max(lw, 62) + 10, py + 15, "pwhy", 11,
                    pin_w - 28 - max(lw, 62) - 10)
            f.add("</g>")
        y += row
    return (f.done(),
            "<b>Every hook, on the stage it changes.</b> Patches 11 and 12 ride the pad read "
            "the NMI performs before the loop wakes; 10 and 10b bracket the HUD, producer on "
            "this side and uploader on the NMI's; 6 and 7 change what the pose writer puts in "
            "<code>+0x40/41</code>; everything else lives inside the object update, because "
            "that is where a character's own code runs. The offsets come from the edit-region "
            "map, which <code>checkpatchmap.py</code> re-derives from the shipped patches.")


CSS_EXTRA = """
.lane{font:600 .72rem/1 ui-monospace,Menlo,monospace;letter-spacing:.12em;
  text-transform:uppercase;fill:var(--ink-3)}
.lane-bg{fill:var(--sunken);stroke:var(--rule)}
.lane-bg.nmi{fill:var(--gfx);fill-opacity:.07;stroke:var(--gfx);stroke-opacity:.45}
.stage rect{fill:var(--surface);stroke:var(--rule)}
.stage .sname{font:600 12.5px/1 ui-sans-serif,system-ui,sans-serif;fill:var(--ink)}
.stage .snote{font:11px/1 ui-sans-serif,system-ui,sans-serif;fill:var(--ink-3)}
.stage .saddr{font:600 11px/1 ui-monospace,Menlo,monospace;fill:var(--code)}
.stage .ssite{font:10.5px/1 ui-monospace,Menlo,monospace;fill:var(--ink-3)}
.s-combat rect{stroke:var(--code)}
.s-unknown rect{fill:var(--sunken);stroke-dasharray:4 3}
.s-unknown .sname{fill:var(--ink-3);font-style:italic}
.s-nmi rect{stroke:var(--gfx)}
.s-nmi .saddr{fill:var(--gfx)}
.flow{stroke:var(--ink-3);stroke-width:1.4;fill:none;color:var(--ink-3)}
.flow.back{stroke-dasharray:5 4}
.flow.hand{stroke:var(--gfx);color:var(--gfx)}
.flow.next{stroke:var(--data);color:var(--data);stroke-dasharray:5 4}
.edge{font:11px/1 ui-monospace,Menlo,monospace;fill:var(--ink-3)}
.edge.hand{fill:var(--gfx)}
.edge.next{fill:var(--data)}
.prow{font:12.5px/1 ui-sans-serif,system-ui,sans-serif;fill:var(--ink)}
.paddr{font:11px/1 ui-monospace,Menlo,monospace;fill:var(--ink-3)}
.pdelta{font:11px/1 ui-monospace,Menlo,monospace;fill:var(--code)}
.pcell{fill:var(--sunken);stroke:var(--rule)}
.pcell.on{fill:var(--code);fill-opacity:.28;stroke:var(--code)}
.pcell.on.s-unknown{fill:var(--ink-3);fill-opacity:.18;stroke:var(--rule)}
.node rect{fill:var(--surface);stroke:var(--rule)}
.node.hit rect{stroke:var(--data);fill:var(--data);fill-opacity:.12}
.node .saddr{font:600 11px/1 ui-monospace,Menlo,monospace;fill:var(--code)}
.node.hit .saddr{fill:var(--data)}
.pin rect{fill:var(--data);fill-opacity:.14;stroke:var(--data)}
.pin .pnum{font:600 11px/1 ui-monospace,Menlo,monospace;fill:var(--data)}
.pin .pwhy{font:11px/1 ui-sans-serif,system-ui,sans-serif;fill:var(--ink-2)}
.asm{background:var(--sunken);border:1px solid var(--rule);border-radius:10px;
  padding:1rem 1.2rem;margin:1.4rem 0;overflow-x:auto}
.asm table{width:100%;border-collapse:collapse;font:12.5px/1.7 ui-monospace,Menlo,monospace}
.asm td{padding:.1rem .8rem .1rem 0;vertical-align:top;white-space:nowrap}
.asm td.why{white-space:normal;font-family:ui-sans-serif,system-ui,sans-serif;
  color:var(--ink-2);font-size:.86rem}
.asm td.op{color:var(--code)}
.gloss-h{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.72rem;
  letter-spacing:.16em;text-transform:uppercase;color:var(--ink-3);font-weight:600;
  margin:1.6rem 0 .4rem}
.gloss{display:grid;grid-template-columns:minmax(9rem,13rem) 1fr;gap:.1rem 1.4rem;
  margin:0;padding:.2rem 0}
.gloss dt{font:600 .86rem/1.6 ui-monospace,SFMono-Regular,Menlo,monospace;
  color:var(--ink);padding:.35rem 0;border-top:1px solid var(--rule)}
.gloss dd{margin:0;padding:.35rem 0;color:var(--ink-2);font-size:.92rem;
  border-top:1px solid var(--rule)}
.gloss dt:first-of-type,.gloss dt:first-of-type + dd{border-top:0}
@media (max-width:44rem){
  .gloss{grid-template-columns:1fr;gap:0}
  .gloss dd{padding:0 0 .6rem;border-top:0}
}
"""

ASM_ROWS = [
    ("$C0:E255", "sep #$30", "the loop head — where the back-edge lands"),
    ("$C0:E257", "lda $1E05 / bmi $E29D",
     "the exit test: a negative $1E05 means the round is over"),
    ("$C0:E25C", "jsl $80:8386", "wait for vblank — everything below is one frame's work"),
    ("...", "...", ""),
    ("$C0:E27A", "jsl $C1:0000",
     "the object update. JSL because it crosses banks; the callee ends in RTL"),
    ("...", "...", ""),
    ("$C0:E29B", "bra $E255", "two bytes, and the frame starts again"),
]


# Sizes and families have to be repeated here because the audit reads the emitted
# markup, not the code that produced it — the point is to catch a figure whose
# geometry drifted from its CSS, which is exactly what "the label is wider than
# its pill" was.
# A page that sits between two audiences needs both their vocabularies: the
# console terms a fighting-game player has no reason to know, and the engine
# terms an assembly reader has no reason to know. Definitions are specific to
# THIS cartridge wherever they can be — a generic dictionary entry would be
# padding, and the address in it is what makes the term findable.
GLOSSARY = [
    ("The console", [
        ("NMI", "the interrupt the PPU raises once per frame, at the start of vblank. "
                "Here it is the whole reason the loop advances: it writes DP $6C and the "
                "loop is spinning on that byte"),
        ("vblank", "the gap between drawing the last scanline and the first of the next "
                   "frame — the only safe window to write video memory"),
        ("DMA", "the chip that copies a block without the CPU. Sprites, palettes and the "
                "HUD all reach the PPU this way, which is why they are written to shadow "
                "copies in RAM first"),
        ("OAM", "the 544 bytes the PPU reads to know where every sprite is. This game "
                "keeps a shadow at $7E:0200 and sends the whole thing every frame"),
        ("CGRAM / VRAM / WRAM", "the palette memory, the video memory and the console's "
                                "128 KB of work RAM"),
        ("DP (direct page)", "a movable 256-byte window the CPU can address in one byte "
                             "instead of two — this engine parks its per-frame flags there "
                             "($6C, $88, $90)"),
        ("bank", "a 64 KB slice of the 24-bit address space. `$C1:0000` means offset "
                 "$0000 in bank $C1"),
        ("FastROM mirror", "the same cartridge visible again at banks $80-$BF, where the "
                           "console reads it a third faster. `$80:A05C` and `$C0:A05C` are "
                           "one routine, which is why a breakpoint on the wrong one never "
                           "fires"),
        ("jsr / JSL / RTL", "call within a bank, call across banks, and the return that "
                            "matches the long one. A `jsr` operand is two bytes and a "
                            "`JSL` three — which decides how much room a hook has"),
        ("jsr ($00A6,X)", "an indirect call: the address is looked up in a table at "
                          "$00A6. One instruction, twenty-eight different characters"),
        ("hook / stub", "how every patch here works — overwrite a call with one to your "
                        "own code (the stub), do the extra work, then do what the "
                        "original instruction did and return"),
    ]),
    ("The engine", [
        ("object", "anything the update loop drives: the two fighters, projectiles, "
                   "effects. All of them are 128-byte structs with the same layout"),
        ("act", "the object's current state number, at +0x01 — walking, 2LP's startup, "
                "hitstun. Everything else follows from it"),
        ("pose", "one drawn frame, at +0x05. The act's script picks poses; a pose record "
                 "picks the boxes and the sprite list"),
        ("hitbox / hurtbox", "the rectangle that hits and the rectangle that can be hit, "
                             "chosen per pose by the indices at +0x40/41. **Invulnerable "
                             "means hurtbox index 0** — an empty box, not a flag"),
        ("hitstun / blockstun", "the frames a defender cannot act after being hit, or "
                                "after blocking. The difference between them is most of "
                                "what makes a combo a combo"),
        ("guard cancel (GC)", "cancelling blockstun directly into a special. This game's "
                              "defining mechanic, and why the reaction stage runs where it "
                              "does"),
        ("meaty", "an attack timed so it becomes active exactly as the defender leaves "
                  "stun. At one frame of margin it cannot be blocked on reaction — the "
                  "Uranus infinite is built on this"),
        ("proc block", "one character's own code, ~4-5 KB of it, reached through the "
                       "dispatch table. Uranus's is $C1:79F2"),
    ]),
]


AUDIT_SIZE = {"sname": 12.5, "snote": 11, "saddr": 11, "ssite": 10.5, "lane": 10.5,
              "edge": 11, "prow": 12.5, "paddr": 11, "pdelta": 11, "pnum": 11, "pwhy": 11}
AUDIT_MONO = {"saddr", "ssite", "lane", "edge", "paddr", "pdelta", "pnum"}


def audit(page):
    """Read back the drawing and refuse to ship one that overlaps or overflows.

    SVG will happily render a label straight through the box next to it, and no
    amount of care while writing coordinates catches that reliably — the first
    cut of this page shipped both faults. So the emitted markup is parsed and
    three things are asserted: no two boxes overlap, every string fits inside the
    box it sits in, and nothing runs past the viewBox.
    """
    def attr(tag, name):
        m = re.search(rf'\b{name}="([-\d.]+)"', tag)
        return float(m.group(1)) if m else None

    bad = []
    for fig, m in enumerate(re.finditer(r'<svg viewBox="0 0 (\d+) (\d+)"(.*?)</svg>',
                                        page, re.S), 1):
        W, H, body = int(m.group(1)), int(m.group(2)), m.group(3)
        rects = []
        for tag in re.findall(r"<rect [^>]*>", body):
            x, y, w, h = (attr(tag, k) for k in ("x", "y", "width", "height"))
            cls = (re.search(r'class="([^"]*)"', tag) or [None, ""])[1]
            if None in (x, y, w, h):
                continue
            if x + w > W + 0.5 or y + h > H + 0.5:
                bad.append(f"figure {fig}: a box runs past the viewBox at ({x:.0f},{y:.0f})")
            if "lane-bg" not in (cls or ""):
                rects.append((x, y, w, h))
        for i, (x1, y1, w1, h1) in enumerate(rects):
            for x2, y2, w2, h2 in rects[i + 1:]:
                if x1 < x2 + w2 - .5 and x2 < x1 + w1 - .5 \
                        and y1 < y2 + h2 - .5 and y2 < y1 + h1 - .5:
                    bad.append(f"figure {fig}: boxes overlap at ({x1:.0f},{y1:.0f}) "
                               f"and ({x2:.0f},{y2:.0f})")
        for t in re.finditer(r'<text class="([^"]*)" x="([-\d.]+)" y="([-\d.]+)"'
                             r'( text-anchor="end")?>([^<]*)</text>', body):
            cls, x, y, end, txt = (t.group(1), float(t.group(2)), float(t.group(3)),
                                   bool(t.group(4)), t.group(5))
            key = cls.split()[0]
            wid = text_w(txt, AUDIT_SIZE.get(key, 11), key in AUDIT_MONO)
            left = x - wid if end else x
            host = [r for r in rects if r[0] <= x <= r[0] + r[2] and r[1] <= y <= r[1] + r[3] + 4]
            if not host:
                continue
            rx, _ry, rw, _rh = host[0]
            if left < rx - 1 or left + wid > rx + rw + 1:
                bad.append(f"figure {fig}: {txt[:34]!r} is wider than the box it sits in")
    return bad


def audit_selftest():
    """The audit is a parser, and a parser that has stopped matching passes
    everything. `place()` clips, so a real figure can no longer produce an
    overlong label — which means the only way to know the audit still has teeth
    is to hand it markup that is deliberately broken."""
    box = '<rect x="10" y="10" width="80" height="20" rx="4"/>'
    over = '<rect x="40" y="14" width="80" height="20" rx="4"/>'
    long_text = '<text class="sname" x="18" y="24">a label far too long for that box</text>'
    fits = '<text class="sname" x="18" y="24">short</text>'
    bad = []
    if not audit(f'<svg viewBox="0 0 200 60">{box}{long_text}</svg>'):
        bad.append("the audit no longer notices a label wider than its box")
    if not audit(f'<svg viewBox="0 0 200 60">{box}{over}</svg>'):
        bad.append("the audit no longer notices two boxes overlapping")
    if not audit('<svg viewBox="0 0 100 40"><rect x="10" y="10" width="200" height="20"/></svg>'):
        bad.append("the audit no longer notices a box past the viewBox")
    if audit(f'<svg viewBox="0 0 200 60">{box}{fits}</svg>'):
        bad.append("the audit flags a figure that is fine")
    return bad


STANDALONE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="One in-match frame of Bishoujo Senshi Sailor Moon S (SFC, 1994), disassembled: the loop at $C0:E255, the NMI that releases it, where a hit is actually resolved, and the stage every patch attaches to.">
<meta name="color-scheme" content="light dark">
<title>SMS — one frame, as the cartridge runs it</title>
{head}
</head>
<body>
{body}
</body>
</html>
"""


def build():
    figs = [fig_frame(), fig_phases(), fig_hits(), fig_patches()]
    out = [f"<style>{mkarchpage.CSS}{CSS_EXTRA}</style>"]
    out.append('<article>')
    out.append('<p class="eyebrow">Sailor Moon S · Jougai Rantou!? · SFC</p>')
    out.append("<h1>One frame, as the cartridge runs it</h1>")
    out.append('<p class="standfirst">The in-match loop lives at <code>$C0:E255</code>. '
               'It waits for the NMI, runs nineteen calls, and branches back — and every '
               'question this project keeps asking (why a hit lands a frame late, where a '
               'patch attaches, what runs in Practice) is a question about that list. '
               'Everything below was disassembled out of the clean ROM, not assumed from '
               'how such engines usually work.</p>')

    out.append("<h2>The frame</h2>")
    svg, cap = figs[0]
    out.append(f'<figure><div class="scroller">{svg}</div><figcaption>{cap}</figcaption></figure>')

    out.append("<h2>Reading it as assembly</h2>")
    out.append("<p>Three idioms account for most of the surprise. <strong>JSL</strong> is a "
               "long call and <strong>jsr</strong> a same-bank one, which is why a hook that "
               "replaces a <code>jsr</code> has three bytes to work with and one replacing a "
               "<code>jsl</code> has four. <strong>The <code>$80</code> and <code>$C0</code> "
               "banks are the same ROM</strong> — <code>$80:A05C</code> and <code>$C0:A05C</code> "
               "are one routine, and the game executes from the fast mirror. And "
               "<strong>dispatch is a table</strong>: <code>jsr ($00A6,X)</code> is how one "
               "line of code becomes twenty-eight different characters.</p>")
    out.append('<div class="asm"><table>')
    for addr, op, why in ASM_ROWS:
        out.append(f'<tr><td>{esc(addr)}</td><td class="op">{esc(op)}</td>'
                   f'<td class="why">{esc(why)}</td></tr>')
    out.append("</table></div>")

    out.append("<h2>Phases share the list</h2>")
    svg, cap = figs[1]
    out.append(f'<figure><div class="scroller">{svg}</div><figcaption>{cap}</figcaption></figure>')

    out.append("<h2>Where a hit happens</h2>")
    svg, cap = figs[2]
    out.append(f'<figure><div class="scroller">{svg}</div><figcaption>{cap}</figcaption></figure>')

    out.append("<h2>Where the patches attach</h2>")
    svg, cap = figs[3]
    out.append(f'<figure><div class="scroller">{svg}</div><figcaption>{cap}</figcaption></figure>')

    out.append('<div class="callout"><span class="tag">HONEST GAPS</span>'
               '<p>Three stages are drawn in grey because they are not identified: '
               '<code>$C0:9633</code> (copies <code>$A3</code>/<code>$A5</code> aside and '
               'indexes on the held pad), <code>$C0:DB35</code> (reads <code>$1E3D</code>, '
               'writes <code>$71</code>/<code>$1E04</code>) and <code>$C0:8CAF</code> '
               '(reads flag <code>$B1</code>). Naming them would make a nicer diagram and a '
               'worse document.</p></div>')

    out.append("<h2>Glossary</h2>")
    out.append('<p>Two vocabularies meet on this page, and nobody arrives with both.</p>')
    for group, terms in GLOSSARY:
        out.append(f'<h3 class="gloss-h">{esc(group)}</h3><dl class="gloss">')
        for term, meaning in terms:
            meaning = re.sub(r"`([^`]+)`", r"<code>\1</code>", esc(meaning))
            meaning = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", meaning)
            out.append(f"<dt>{esc(term)}</dt><dd>{meaning}</dd>")
        out.append("</dl>")
    out.append('<p class="foot">Generated by <code>tools/mkenginepage.py</code> from the clean '
               'ROM <code>bc0e29ee…</code>. <code>--check</code> re-reads every instruction '
               'drawn here and fails if one moved. Companion page: the data architecture.</p>')
    out.append("</article>")
    return "\n".join(out)


if __name__ == "__main__":
    if "--check" in sys.argv:
        problems = check()
        problems += audit(build()) + [f"SELF-TEST: {b}" for b in audit_selftest()]
        problems += [f"clipped: {t!r} (had {room:.0f}px)" for t, room in CLIPPED]
        for line in problems:
            print("  FAIL ", line)
        if problems:
            sys.exit(1)
        print(f"engine page in sync with the ROM ({len(ROUND)} loop stages, "
              f"{len(NMI_BODY)} NMI stages, {len(CENSUS)} call-site censuses); "
              "layout audit clean")
        sys.exit(0)
    page = build()
    problems = audit(page) + [f"clipped: {t!r} (had {room:.0f}px)" for t, room in CLIPPED]
    if problems:
        for line in problems:
            print("  LAYOUT ", line)
        sys.exit(1)
    out = OUT_DEFAULT
    if "--standalone" in sys.argv:
        sys.argv.remove("--standalone")
        if len(sys.argv) > 1:
            out = pathlib.Path(sys.argv[1])
        page = STANDALONE.format(head=page[:page.index("</style>") + 8].strip(),
                                 body=page[page.index("</style>") + 8:].strip())
    elif len(sys.argv) > 1:
        out = pathlib.Path(sys.argv[1])
    out.write_text(page, encoding="utf-8")
    print("wrote", out, out.stat().st_size, "bytes")
