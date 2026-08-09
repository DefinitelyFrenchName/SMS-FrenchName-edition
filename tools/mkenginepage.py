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
     "consumes the pending-hit code left on +0x47 LAST frame and turns it "
     "into an act, through the posture x level dispatch $C1:0E85", "combat"),
    (0xE26A, "jsl", 0xA05C, 0x80, "animation scripts",
     "walks each object's act script: duration into +0x06, pose into +0x05", "always"),
    (0xE26E, "jsl", 0x9C96, 0x80, "poses to boxes",
     "pose record -> class +0x18 and the hit/hurt/coll indices +0x40/41/42 "
     "(the `sta $41,X` at $C0:9CCD)", "always"),
    (0xE272, "jsl", 0x2584, 0xC1, "effect pool", "the $1200 object slots", "combat"),
    (0xE276, "jsl", 0x16EE, 0xC1, "projectile pool", "the $1100/$1180 slots", "combat"),
    (0xE27A, "jsl", 0x0000, 0xC1, "object update",
     "the dispatch — `jsr ($00A6,X)` by object id, into each character's own "
     "proc block. Hits are detected in here, not out here", "always"),
    (0xE27E, "jsl", 0x9FB8, 0x80, "resolve cels",
     "pose -> cel records -> the ROM address and size the DMA will stream", "always"),
    (0xE282, "jsr", 0x8BCB, 0xC0, "world to screen",
     "+0x21 - camera $0A00 + 0x2C -> +0x28, the on-screen position", "always"),
    (0xE285, "jsr", 0x9CE2, 0xC0, "build draw order",
     "walks the object slots and lists the live ones at $0B00", "always"),
    (0xE288, "jsl", 0x9A0E, 0x80, "emit sprites",
     "draw list -> per-pose sprite records -> the OAM shadow at $7E:0200", "always"),
    (0xE28C, "jsr", 0xD5E8, 0xC0, "HUD producer",
     "bars and timer into the staging block $0806-$0815. Never runs in "
     "Practice — hook it and your code is dead in the mode people train in", "combat"),
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
    (0xD4CF, 0x9EF5, "jsl", "OAM + CGRAM shadows -> the PPU"),
    (0xD4D3, 0x8C4D, "jsr", "unidentified"),
    (0xD4D6, 0xD56F, "jsr", "HUD uploader -> VRAM"),
    (0xD4D9, 0xB3D7, "jsr", "unidentified"),
    (0xD4DC, 0x8353, "jsr", "read the pads -> $5C-$5F held, $60/$62 edges"),
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
    "1": (0xE27A, "gates 2HP's dash cancel inside Uranus's proc"),
    "1b": (0xE27A, "the same gate, one frame tighter"),
    "2": (0xE27A, "clears the lingering untargetable flag in the dash's init"),
    "5": (0xE27A, "the dash's X-speed operand"),
    "6": (0xE26E, "overrides the hurtbox index AFTER the writer sets it"),
    "7": (0xE26E, "one box-height byte the writer indexes"),
    "8": (0xE27A, "one byte of the throw-hold script the proc walks"),
    "9": (0xE27A, "the fireball's box, read during collision"),
    "10": (0xE28C, "hooks the producer, and the uploader on the NMI side"),
    "10b": (0xE28C, "same pair, plus the label glyphs"),
    "11": (0xE25C, "rides the joy_read chain in the NMI"),
    "12": (0xE25C, "the next link in the same chain"),
    "13": (0xE27A, "the eight damage-apply sites, inside the procs"),
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
ROW_H, PAD_X = 46, 18


def esc(s):
    return html.escape(s, quote=False)


def fig_frame():
    """The spine: the loop's stages as a ladder, the NMI beside it, and the one
    handshake that ties them together."""
    n = len(ROUND)
    h = 96 + n * ROW_H + 40
    w = 980
    lane_x, lane_w = 36, 560
    nmi_x, nmi_w = 660, 284
    p = [f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="One in-match frame: '
         f'the main loop at $C0:E255 runs {n} stages, the NMI at $C0:D4C9 runs six, '
         'and the loop waits on DP $6C for it.">']
    p.append('<defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
             'markerHeight="7" orient="auto"><path d="M0 0L10 5L0 10z" fill="currentColor"/>'
             '</marker></defs>')
    p.append(f'<text class="lane" x="{lane_x}" y="26">MAIN LOOP · $C0:E255 · one pass = one frame</text>')
    p.append(f'<text class="lane" x="{nmi_x}" y="26">NMI · $C0:D4C9</text>')
    p.append(f'<rect class="lane-bg" x="{lane_x}" y="40" width="{lane_w}" height="{n * ROW_H + 20}" rx="10"/>')
    p.append(f'<rect class="lane-bg nmi" x="{nmi_x}" y="40" width="{nmi_w}" '
             f'height="{len(NMI_BODY) * 34 + 30}" rx="10"/>')

    for i, (site, kind, target, bank, name, note, role) in enumerate(ROUND):
        y = 58 + i * ROW_H
        p.append(f'<g class="stage r-{role}">')
        p.append(f'<rect x="{lane_x + 12}" y="{y}" width="{lane_w - 24}" height="{ROW_H - 10}" rx="6"/>')
        p.append(f'<text class="sname" x="{lane_x + 26}" y="{y + 17}">{esc(name)}</text>')
        p.append(f'<text class="snote" x="{lane_x + 26}" y="{y + 31}">{esc(note[:76])}</text>')
        p.append(f'<text class="saddr" x="{lane_x + lane_w - 36}" y="{y + 17}" text-anchor="end">'
                 f'{kind.upper()} ${bank:02X}:{target:04X}</text>')
        p.append(f'<text class="ssite" x="{lane_x + lane_w - 36}" y="{y + 31}" text-anchor="end">'
                 f'at ${site:04X}</text>')
        p.append('</g>')
        if i < n - 1:
            p.append(f'<line class="flow" x1="{lane_x + 22}" y1="{y + ROW_H - 10}" '
                     f'x2="{lane_x + 22}" y2="{y + ROW_H}" marker-end="url(#ar)"/>')

    back_y = 58 + n * ROW_H
    p.append(f'<path class="flow back" d="M{lane_x + 22} {back_y - 8} '
             f'L{lane_x - 8} {back_y - 8} L{lane_x - 8} 62 L{lane_x + 6} 62" marker-end="url(#ar)"/>')
    p.append(f'<text class="edge" x="{lane_x - 4}" y="{back_y + 8}">bra $E255 — next frame</text>')

    for i, (site, target, kind, label) in enumerate(NMI_BODY):
        y = 58 + i * 34
        p.append('<g class="stage r-nmi">')
        p.append(f'<rect x="{nmi_x + 12}" y="{y}" width="{nmi_w - 24}" height="26" rx="5"/>')
        p.append(f'<text class="sname" x="{nmi_x + 24}" y="{y + 17}">{esc(label)}</text>')
        p.append(f'<text class="saddr" x="{nmi_x + nmi_w - 24}" y="{y + 17}" text-anchor="end">'
                 f'${target:04X}</text>')
        p.append('</g>')

    hs_y = 58 + len(NMI_BODY) * 34 + 26
    p.append(f'<path class="flow hand" d="M{nmi_x + 60} {hs_y} L{nmi_x + 60} {hs_y + 26} '
             f'L{lane_x + lane_w + 40} {hs_y + 26} L{lane_x + lane_w + 40} 74 '
             f'L{lane_x + lane_w - 14} 74" marker-end="url(#ar)"/>')
    p.append(f'<text class="edge hand" x="{nmi_x + 66}" y="{hs_y + 20}">sets DP $6C — releases the wait</text>')
    p.append("</svg>")
    return ("".join(p),
            "<b>One frame.</b> The loop does not poll a timer: it spins in "
            "<code>$80:8386</code> until the NMI writes DP <code>$6C</code>, then runs "
            "its stages in this order and branches back. Every address is the "
            "instruction's own site, so a stage that moves fails <code>--check</code>.")


def fig_phases():
    """Two loops, same spine — the round loop is the entrance loop plus combat."""
    rows = [(s[2], s[4], s[6]) for s in ROUND]
    w, h = 900, 90 + len(rows) * 30
    p = [f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="The entrance loop and the '
         'round loop run the same stage list; the round loop adds the combat stages.">']
    p.append('<text class="lane" x="392" y="26">ENTRANCE $C0:E21A</text>')
    p.append('<text class="lane" x="622" y="26">ROUND $C0:E255</text>')
    for i, (target, name, role) in enumerate(rows):
        y = 48 + i * 30
        in_entrance = target in ENTRANCE
        p.append(f'<text class="prow" x="24" y="{y + 14}">{esc(name)}</text>')
        p.append(f'<text class="paddr" x="300" y="{y + 14}" text-anchor="end">${target:04X}</text>')
        for cx, present in ((392, in_entrance), (622, True)):
            cls = "on" if present else "off"
            p.append(f'<rect class="cell {cls} r-{role}" x="{cx}" y="{y}" width="150" height="20" rx="4"/>')
        if not in_entrance:
            p.append(f'<text class="pdelta" x="790" y="{y + 14}">added by the round</text>')
    p.append("</svg>")
    return ("".join(p),
            "<b>Six phase loops, one stage list.</b> The engine has a loop per match phase "
            "(<code>$C0:E21A</code>, <code>E255</code>, <code>E2E2</code>, <code>E30F</code>, "
            "<code>E41E</code>, <code>E8D3</code>). They call the same routines in the same "
            "order; what a phase does <em>not</em> do is what it leaves out. The entrance "
            "animates and draws — it just never fights. (It also runs two stages of its own, "
            "<code>$C0:877C</code> and <code>$C0:D99E</code>, which the round loop has no use for.)")


def fig_hits():
    """Where a hit actually happens — the answer to 'why a frame later'."""
    w, h = 940, 330
    p = [f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="Hit resolution is called from '
         'inside each character proc, 192 times; the reaction it causes is applied at the '
         'top of the next frame.">']
    p.append('<defs><marker id="ar2" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
             'markerHeight="7" orient="auto"><path d="M0 0L10 5L0 10z" fill="currentColor"/>'
             '</marker></defs>')
    box = [(30, 60, 250, "object update", "$C1:0000", "stage 9 of the frame"),
           (30, 140, 250, "proc dispatch", "$C1:0080", "jsr ($00A6,X) by object id"),
           (30, 220, 250, "the character's proc", "$C1:79F2", "Uranus, 5040 bytes of it"),
           (350, 220, 250, "hit resolution", "$80:BFBB", "192 call sites, all in bank $C1"),
           (660, 220, 250, "pending code", "+0x47", "written on the VICTIM"),
           (660, 60, 250, "apply reactions", "$C1:0E26", "stage 4 — NEXT frame")]
    for x, y, bw, name, addr, note in box:
        cls = "hit" if addr in ("$80:BFBB", "+0x47") else "obj"
        p.append(f'<g class="node {cls}"><rect x="{x}" y="{y}" width="{bw}" height="58" rx="7"/>'
                 f'<text class="sname" x="{x + 16}" y="{y + 23}">{esc(name)}</text>'
                 f'<text class="snote" x="{x + 16}" y="{y + 41}">{esc(note)}</text>'
                 f'<text class="saddr" x="{x + bw - 16}" y="{y + 23}" text-anchor="end">{esc(addr)}</text></g>')
    for x1, y1, x2, y2, label, lx, ly in (
            (155, 118, 155, 140, "", 0, 0),
            (155, 198, 155, 220, "", 0, 0),
            (280, 249, 350, 249, "JSL", 300, 242),
            (600, 249, 660, 249, "writes", 604, 242)):
        p.append(f'<line class="flow" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" marker-end="url(#ar2)"/>')
        if label:
            p.append(f'<text class="edge" x="{lx}" y="{ly}">{label}</text>')
    p.append('<path class="flow next" d="M785 220 L785 118" marker-end="url(#ar2)"/>')
    p.append('<text class="edge next" x="795" y="175">one frame later</text>')
    p.append('<text class="edge next" x="795" y="192">the reaction becomes an act</text>')
    p.append("</svg>")
    return ("".join(p),
            "<b>Nothing in the frame list checks a hitbox.</b> Detection lives in the "
            "attacker's own proc — <code>JSL $80:BFBB</code>, 192 sites, every one of them "
            "in bank <code>$C1</code> — and it leaves a code on the victim's <code>+0x47</code>. "
            "The loop's fourth stage turns that into an act on the FOLLOWING pass, which is "
            "the whole reason this engine's timing reads one frame late and why a move "
            "announced only on its first active frame loses the guard race.")


def fig_patches():
    """The same ladder, with every shipped patch pinned to the stage it changes."""
    regions = patch_regions()
    by_stage = {}
    for patch, (stage, why) in PATCH_STAGE.items():
        by_stage.setdefault(stage, []).append((patch, why, regions.get(patch, [])))
    rows = [s for s in ROUND if s[0] in by_stage]
    w, h = 940, 40 + len(rows) * 74
    p = [f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="Each shipped patch pinned to the '
         'loop stage it changes, with the file offsets it edits.">']
    for i, (site, _k, target, bank, name, _n, role) in enumerate(rows):
        y = 20 + i * 74
        p.append(f'<g class="stage r-{role}"><rect x="24" y="{y}" width="300" height="{56}" rx="6"/>'
                 f'<text class="sname" x="40" y="{y + 22}">{esc(name)}</text>'
                 f'<text class="saddr" x="308" y="{y + 22}" text-anchor="end">${bank:02X}:{target:04X}</text>'
                 f'<text class="snote" x="40" y="{y + 40}">stage {ROUND.index(next(s for s in ROUND if s[0] == site)) + 1}</text></g>')
        for j, (patch, why, offs) in enumerate(sorted(by_stage[site], key=lambda t: (len(t[0]), t[0]))):
            px, py = 360 + (j % 2) * 290, y + (j // 2) * 26
            p.append(f'<g class="pin"><rect x="{px}" y="{py}" width="272" height="22" rx="11"/>'
                     f'<text class="pnum" x="{px + 14}" y="{py + 15}">patch {esc(patch)}</text>'
                     f'<text class="pwhy" x="{px + 78}" y="{py + 15}">{esc(why[:44])}</text></g>')
    p.append("</svg>")
    return ("".join(p),
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
.r-combat rect{stroke:var(--code)}
.r-unknown rect{fill:var(--sunken);stroke-dasharray:4 3}
.r-unknown .sname{fill:var(--ink-3);font-style:italic}
.r-nmi rect{stroke:var(--gfx)}
.r-nmi .saddr{fill:var(--gfx)}
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
.cell{fill:var(--sunken);stroke:var(--rule)}
.cell.on{fill:var(--code);fill-opacity:.28;stroke:var(--code)}
.cell.on.r-unknown{fill:var(--ink-3);fill-opacity:.18;stroke:var(--rule)}
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
    out.append(f'<figure><div class="scroll">{svg}</div><figcaption>{cap}</figcaption></figure>')

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
    out.append(f'<figure><div class="scroll">{svg}</div><figcaption>{cap}</figcaption></figure>')

    out.append("<h2>Where a hit happens</h2>")
    svg, cap = figs[2]
    out.append(f'<figure><div class="scroll">{svg}</div><figcaption>{cap}</figcaption></figure>')

    out.append("<h2>Where the patches attach</h2>")
    svg, cap = figs[3]
    out.append(f'<figure><div class="scroll">{svg}</div><figcaption>{cap}</figcaption></figure>')

    out.append('<div class="callout"><span class="tag">HONEST GAPS</span>'
               '<p>Three stages are drawn in grey because they are not identified: '
               '<code>$C0:9633</code> (copies <code>$A3</code>/<code>$A5</code> aside and '
               'indexes on the held pad), <code>$C0:DB35</code> (reads <code>$1E3D</code>, '
               'writes <code>$71</code>/<code>$1E04</code>) and <code>$C0:8CAF</code> '
               '(reads flag <code>$B1</code>). Naming them would make a nicer diagram and a '
               'worse document.</p></div>')

    out.append('<p class="foot">Generated by <code>tools/mkenginepage.py</code> from the clean '
               'ROM <code>bc0e29ee…</code>. <code>--check</code> re-reads every instruction '
               'drawn here and fails if one moved. Companion page: the data architecture.</p>')
    out.append("</article>")
    return "\n".join(out)


if __name__ == "__main__":
    if "--check" in sys.argv:
        problems = check()
        for line in problems:
            print("  FAIL ", line)
        if problems:
            sys.exit(1)
        print(f"engine page in sync with the ROM ({len(ROUND)} loop stages, "
              f"{len(NMI_BODY)} NMI stages, {len(CENSUS)} call-site censuses)")
        sys.exit(0)
    page = build()
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
