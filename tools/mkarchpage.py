#!/usr/bin/env python3
"""Render docs/game/sms_data_architecture.md's diagrams as a standalone HTML page.

The visual companion to `docs/game/sms_data_architecture.md`: the same material, with
the memory maps drawn rather than described. Writes an HTML file (default next
to this script; pass a path to place it elsewhere) which is published as an
Artifact — it is self-contained, so it also just opens in a browser.

Geometry is COMPUTED, never hand-typed: the 40-bank strip, the 128-byte struct
grid, the memory bands and the byte-layout ribbons are all regular grids, and
hand-authoring SVG coordinates is how off-by-one diagrams happen.

The page's palette is the game's own. The strip in the footer is Sailor Uranus's
character palette, read out of the clean ROM at $E0:06BE; the diagram categories
borrow from Neptune's, Pluto's and Moon's, adjusted where a theme needed the
contrast.

  python3 tools/mkarchpage.py [out.html]               # Artifact fragment
  python3 tools/mkarchpage.py --standalone [out.html]  # a file that opens in a browser
"""
import html, pathlib

import sys
OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else \
      pathlib.Path(__file__).with_name("sms_data_architecture.html")

# ---------------------------------------------------------------- palette ----
# Every colour here is read out of the game's own ROM ($E0:06BE etc.), not invented.
URANUS = ["#6a6a6a", "#202020", "#6a2000", "#e67b52", "#ff9c7b", "#ffc5c5",
          "#081083", "#0820ac", "#394abd", "#6a7bd5", "#9cace6", "#cddeff",
          "#ffb46a", "#ffd573", "#c55a31", "#ffffff"]

# role -> (light fill, dark fill) drawn from the roster's own costume ramps
ROLE = {
    "code":    ("#394abd", "#6a7bd5"),   # Uranus blue
    "data":    ("#c58a1f", "#ffd573"),   # her gold accent
    "gfx":     ("#007b7b", "#37b3b3"),   # Neptune teal
    "audio":   ("#2f7a2f", "#57b357"),   # Pluto green
    "menu":    ("#a03a63", "#ff8fb0"),   # Moon magenta
    "free":    ("#8c93a8", "#5a6480"),   # neutral
    "unknown": ("#b9bfd0", "#39415c"),
}

# --------------------------------------------------------------- ROM banks ---
# (snes bank, role, label, measured fill %)
BANKS = [
    (0xC0, "code", "engine core", 61.0), (0xC1, "code", "objects + proc blocks", 74.9),
    (0xC2, "code", "code/data", 75.5), (0xC3, "menu", "front end", 67.2),
    (0xC4, "menu", "menu payloads", 68.1), (0xC5, "gfx", "graphics", 82.4),
    (0xC6, "gfx", "graphics", 83.6), (0xC7, "menu", "kanji font", 74.7),
    (0xC8, "gfx", "graphics", 73.8), (0xC9, "gfx", "graphics", 76.3),
    (0xCA, "gfx", "graphics", 79.7), (0xCB, "data", "cel tables", 73.5),
    (0xCC, "gfx", "graphics", 67.2), (0xCD, "gfx", "graphics", 63.2),
    (0xCE, "gfx", "graphics", 67.1), (0xCF, "gfx", "graphics", 69.8),
    (0xD0, "gfx", "graphics", 70.4), (0xD1, "gfx", "graphics", 74.3),
    (0xD2, "gfx", "graphics", 70.9), (0xD3, "gfx", "graphics", 68.9),
    (0xD4, "gfx", "graphics", 67.0), (0xD5, "gfx", "graphics", 70.3),
    (0xD6, "gfx", "graphics", 65.2), (0xD7, "gfx", "graphics", 63.4),
    (0xD8, "gfx", "graphics", 59.3), (0xD9, "gfx", "graphics", 63.8),
    (0xDA, "gfx", "graphics", 60.3), (0xDB, "gfx", "graphics", 69.5),
    (0xDC, "gfx", "sparse", 25.4), (0xDD, "gfx", "sparse", 43.9),
    (0xDE, "gfx", "sparse", 53.4), (0xDF, "menu", "screen engine", 35.8),
    (0xE0, "data", "MANIFESTS + palettes", 85.8), (0xE1, "data", "data", 89.8),
    (0xE2, "gfx", "effect tiles", 51.5), (0xE3, "audio", "driver (sparse)", 12.4),
    (0xE4, "audio", "audio", 74.1), (0xE5, "audio", "voice banks", 94.5),
    (0xE6, "audio", "audio", 88.4), (0xE7, "audio", "audio", 74.0),
]

# ------------------------------------------------------------ object struct --
# offset -> (group, short label). Anything absent is "unknown".
STRUCT = {}
def put(start, end, group, label):
    for o in range(start, end + 1):
        STRUCT[o] = (group, label)
put(0x00, 0x00, "id", "charID / obj type")
put(0x01, 0x04, "state", "action")
put(0x05, 0x07, "anim", "pose / tick / frame")
put(0x08, 0x09, "draw", "pal+prio / facing")
put(0x0A, 0x15, "draw", "cel pointers + sizes")
put(0x16, 0x16, "state", "flags")
put(0x18, 0x18, "state", "action flags (bit0 = attack)")
put(0x20, 0x27, "pos", "X / Y position (32-bit subpixel)")
put(0x28, 0x28, "pos", "screen pos")
put(0x2A, 0x2A, "pos", "screen pos")
put(0x30, 0x36, "vel", "velocity / gravity")
put(0x38, 0x38, "vel", "integrator")
put(0x3A, 0x3A, "vel", "pushback")
put(0x40, 0x42, "box", "hit / hurt / coll index")
put(0x43, 0x45, "combat", "connected / attackID / damage")
put(0x46, 0x4A, "combat", "hurt state / d48 / HP")
put(0x4D, 0x4D, "combat", "hitstop")
put(0x50, 0x54, "input", "buttons / commands")
put(0x56, 0x56, "input", "throw mash count")
put(0x5B, 0x68, "input", "recognizer timer/state pairs")
put(0x70, 0x75, "acs", "A.C.S. stats")
put(0x76, 0x77, "acs", "update sel / strength")
put(0x78, 0x78, "audio", "sound id")

GROUP_COLOR = {
    "id":     ("#a03a63", "#ff8fb0"),
    "state":  ("#394abd", "#8b9ae8"),
    "anim":   ("#007b7b", "#37b3b3"),
    "draw":   ("#007b7b", "#37b3b3"),
    "pos":    ("#2f7a2f", "#57b357"),
    "vel":    ("#2f7a2f", "#57b357"),
    "box":    ("#c58a1f", "#ffd573"),
    "combat": ("#c55a31", "#ff9c7b"),
    "input":  ("#394abd", "#8b9ae8"),
    "acs":    ("#8c5bb8", "#b48bff"),
    "audio":  ("#2f7a2f", "#57b357"),
}

def svg_struct():
    """8 rows x 16 columns of bytes = the 0x80-byte object struct."""
    cw, ch, pad, gut = 46, 34, 8, 54
    w = gut + 16 * cw + pad * 2
    h = 26 + 8 * ch + pad * 2
    p = [f'<svg viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" '
         f'aria-label="The 128-byte object struct, byte by byte">']
    for c in range(16):  # column headers
        x = gut + c * cw + cw / 2
        p.append(f'<text class="axis" x="{x:.0f}" y="18" text-anchor="middle">+{c:X}</text>')
    for r in range(8):
        y = 26 + r * ch
        p.append(f'<text class="axis" x="{gut-10}" y="{y+ch/2+4:.0f}" text-anchor="end">'
                 f'{r*16:02X}</text>')
        for c in range(16):
            o = r * 16 + c
            g = STRUCT.get(o)
            x = gut + c * cw
            cls = f"g-{g[0]}" if g else "g-unknown"
            title = f"+0x{o:02X} — {g[1]}" if g else f"+0x{o:02X} — unmapped"
            p.append(f'<g class="cell {cls}"><title>{html.escape(title)}</title>'
                     f'<rect x="{x}" y="{y}" width="{cw-2}" height="{ch-2}" rx="3"/>'
                     f'<text x="{x+(cw-2)/2:.0f}" y="{y+ch/2+4:.0f}" text-anchor="middle">'
                     f'{o:02X}</text></g>')
    p.append("</svg>")
    return "\n".join(p)

def svg_banks():
    """40 cartridge banks as a strip, height = measured fill."""
    cw, top, barh, pad = 30, 22, 92, 6
    w = pad * 2 + 40 * cw
    h = top + barh + 34
    p = [f'<svg viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" '
         f'aria-label="The 40 cartridge banks, coloured by what they hold">']
    for i, (bank, role, label, fill) in enumerate(BANKS):
        x = pad + i * cw
        bh = max(4, barh * fill / 100)
        y = top + barh - bh
        p.append(f'<g class="bank r-{role}"><title>${bank:02X} — {html.escape(label)} '
                 f'({fill:.0f}% packed)</title>'
                 f'<rect x="{x}" y="{top}" width="{cw-3}" height="{barh}" class="bankbg" rx="2"/>'
                 f'<rect x="{x}" y="{y:.1f}" width="{cw-3}" height="{bh:.1f}" rx="2"/></g>')
        if bank % 4 == 0:
            p.append(f'<text class="axis" x="{x+(cw-3)/2:.0f}" y="{top+barh+16}" '
                     f'text-anchor="middle">${bank:02X}</text>')
    # the free region marker
    xe = pad + 40 * cw
    p.append(f'<line class="freeline" x1="{xe}" y1="{top-6}" x2="{xe}" y2="{top+barh+6}"/>')
    p.append(f'<text class="axis free" x="{xe-4}" y="{top-10}" text-anchor="end">'
             f'vanilla ends — $E8+ is where patches live</text>')
    p.append("</svg>")
    return "\n".join(p)

# ------------------------------------------------------------- memory bands --
def band(regions, total, label, height=470):
    """A vertical address band. regions = [(start, end, role, name, note)]"""
    w, gut, pad = 640, 96, 10
    p = [f'<svg viewBox="0 0 {w} {height+pad*2}" width="{w}" height="{height+pad*2}" '
         f'role="img" aria-label="{html.escape(label)}">']
    for (s, e, role, name, note) in regions:
        y0 = pad + height * s / total
        y1 = pad + height * e / total
        hh = max(11, y1 - y0)
        p.append(f'<g class="reg r-{role}"><title>{html.escape(name)} — {html.escape(note)}</title>'
                 f'<rect x="{gut}" y="{y0:.1f}" width="{w-gut-pad}" height="{hh:.1f}" rx="3"/>'
                 f'<text class="addr" x="{gut-8}" y="{y0+11:.1f}" text-anchor="end">${s:04X}</text>'
                 f'<text class="rname" x="{gut+10}" y="{y0+min(hh-3,15):.1f}">{html.escape(name)}</text>')
        if hh > 30:
            p.append(f'<text class="rnote" x="{gut+10}" y="{y0+min(hh-6,31):.1f}">'
                     f'{html.escape(note)}</text>')
        p.append("</g>")
    p.append("</svg>")
    return "\n".join(p)

WRAM = [
    (0x0000, 0x0100, "code",  "direct page", "the engine's working registers; D=0"),
    (0x0100, 0x0200, "unknown", "stack", "by convention — never probed"),
    (0x0200, 0x0500, "gfx",   "OAM shadow", "DMA'd to the sprite table every frame"),
    (0x0500, 0x0700, "gfx",   "CGRAM shadow", "512 B, DMA'd WHOLE every frame"),
    (0x0700, 0x0800, "unknown", "unmapped", ""),
    (0x0800, 0x0816, "menu",  "HUD state", "displayed HP, timer, tile staging"),
    (0x0816, 0x0A00, "free",  "free in VS matches", "patch 10 lives here — NOT free in Practice"),
    (0x0A00, 0x1000, "data",  "camera + draw-order list", ""),
    (0x1000, 0x1200, "data",  "★ THE OBJECT POOL", "$1000 P1 · $1080 P2 · $1100/$1180 projectiles"),
    (0x1200, 0x1800, "unknown", "pool slots 4-15", "unmapped — nothing names a user"),
    (0x1800, 0x2000, "menu",  "menu + A.C.S. state", "cursors, stage id, asset job index, stats"),
]

VRAM_MATCH = [
    (0x0000, 0x0800, "gfx",  "BG1 tilemap", "the stage"),
    (0x0800, 0x1000, "gfx",  "BG2 tilemap", "the stage"),
    (0x1000, 0x2000, "menu", "BG3 tilemap — the HUD", "bars, nameplates, timer"),
    (0x2000, 0x5000, "gfx",  "BG1/BG2 CHR", "stage art, 4bpp"),
    (0x5000, 0x6000, "menu", "BG3 CHR (2bpp)", "timer digits, A-Z, and 0xC7-0xDF free"),
    (0x6000, 0x8000, "data", "OBJ — sprite cels + effects", "P1 $6000 · P2 $6500 · fx $6A00/$7300"),
]

VRAM_MENU = [
    (0x0000, 0x0400, "gfx",  "screen tilemaps", ""),
    (0x0400, 0x05B6, "menu", "the menu font sheet", "418 tiles, staged via $7E:C000"),
    (0x05B6, 0x0600, "free", "FREE — 64 tiles", "patch 16's half-width alphabet"),
    (0x0600, 0x0738, "gfx",  "screen art", ""),
    (0x0738, 0x07C0, "free", "FREE — 136 tiles", "unused"),
    (0x07C0, 0x0800, "gfx",  "screen art", ""),
]

ARAM = [
    (0x0000, 0x0800, "unknown", "IPL / boot", ""),
    (0x0800, 0x2800, "code",  "the sound driver", "its ROM home is file 0x23F804"),
    (0x2800, 0x3400, "data",  "sequence data", "swapped per scene"),
    (0x3400, 0x34C0, "data",  "BRR sample directory", "64 × [start, loop]"),
    (0x34C0, 0x3800, "data",  "★ per-character voice directory", "$34C0 + (charID-1)*32, resident from boot"),
    (0x3800, 0x8E00, "audio", "resident instrument samples", ""),
    (0x8E00, 0x9B92, "audio", "swappable sample slot", "per scene"),
    (0x9B92, 0xB700, "audio", "looks free — is NOT", "passed both freedom tests and was live"),
    (0xB700, 0xDB00, "menu",  "★ P1's voice bank", "directory entries 48-55"),
    (0xDB00, 0xFE8B, "menu",  "★ P2's voice bank", "directory entries 56-63"),
    (0xFE8B, 0x10000, "free", "the end", "largest zero run in all of ARAM: 64 bytes"),
]

def legend(items):
    out = ['<ul class="legend">']
    for role, text in items:
        out.append(f'<li><span class="sw r-{role}"></span>{html.escape(text)}</li>')
    out.append("</ul>")
    return "\n".join(out)



# --------------------------------------------------------- byte-layout strip --
def strip(fields, width=760, label=""):
    """fields = [(nbytes, role, name)] -> a proportional byte-layout ribbon."""
    total = sum(n for n, _, _ in fields)
    h, pad, top = 46, 8, 16
    p = [f'<svg viewBox="0 0 {width} {h+top+pad}" width="{width}" height="{h+top+pad}" '
         f'role="img" aria-label="{html.escape(label)}">']
    x = 0.0
    for n, role, name in fields:
        w = (width - 2) * n / total
        p.append(f'<g class="fld r-{role}"><title>{html.escape(name)} — {n} byte'
                 f'{"s" if n != 1 else ""}</title>'
                 f'<rect x="{x:.1f}" y="{top}" width="{max(2,w-2):.1f}" height="{h}" rx="3"/>'
                 f'<text class="fname" x="{x+w/2:.1f}" y="{top+h/2+4:.0f}" '
                 f'text-anchor="middle">{html.escape(name)}</text></g>')
        p.append(f'<text class="axis" x="{x+w/2:.1f}" y="11" text-anchor="middle">{n}</text>')
        x += w
    p.append("</svg>")
    return "\n".join(p)

BOX_ENTRY = [(1,"data","x_off R"),(1,"data","w R"),(1,"data","x_off L"),(1,"data","w L"),
             (1,"gfx","y_off"),(1,"gfx","h"),(1,"menu","flags"),(1,"unknown","--")]
ASSET_REC = [(2,"gfx","vram"),(2,"menu","len"),(3,"code","src24"),(3,"data","dest24")]
ONHIT_REC = [(1,"combatc","damage"),(1,"combatc","hitstun"),(1,"gfx","hit level"),(1,"menu","flags")]
STAGE_REC = [(6,"menu","header"),(48,"code","TOP row - 24 words, name centred by zero padding"),
             (48,"data","BOTTOM row - the same glyphs + $10")]

# ------------------------------------------------------------------- page ----
CSS = """
:root{
  --paper:#eceef4; --surface:#f8f9fc; --sunken:#e3e7f0;
  --ink:#11141c; --ink-2:#414a63; --ink-3:#6d7692;
  --rule:#ccd2e2; --accent:#2f3f9e; --accent-soft:#dfe3f7;
  --code:#394abd; --data:#a8761a; --gfx:#00706f; --audio:#2f7a2f;
  --menu:#a03a63; --free:#7f879c; --unknown:#c2c8d8;
  --shadow:0 1px 2px rgba(17,20,28,.06), 0 8px 24px -12px rgba(17,20,28,.18);
}
@media (prefers-color-scheme: dark){ :root:not([data-theme="light"]){
  --paper:#0a0d15; --surface:#121724; --sunken:#0e131f;
  --ink:#e8ebf4; --ink-2:#b3bbd0; --ink-3:#828cab;
  --rule:#242c42; --accent:#8b9ae8; --accent-soft:#1b2340;
  --code:#6a7bd5; --data:#ffd573; --gfx:#37b3b3; --audio:#57b357;
  --menu:#ff8fb0; --free:#5a6480; --unknown:#2b3350;
  --shadow:0 1px 2px rgba(0,0,0,.5), 0 10px 30px -14px rgba(0,0,0,.7);
}}
:root[data-theme="dark"]{
  --paper:#0a0d15; --surface:#121724; --sunken:#0e131f;
  --ink:#e8ebf4; --ink-2:#b3bbd0; --ink-3:#828cab;
  --rule:#242c42; --accent:#8b9ae8; --accent-soft:#1b2340;
  --code:#6a7bd5; --data:#ffd573; --gfx:#37b3b3; --audio:#57b357;
  --menu:#ff8fb0; --free:#5a6480; --unknown:#2b3350;
  --shadow:0 1px 2px rgba(0,0,0,.5), 0 10px 30px -14px rgba(0,0,0,.7);
}
*{box-sizing:border-box}
body{
  margin:0; background:var(--paper); color:var(--ink);
  font:16px/1.65 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;
  -webkit-font-smoothing:antialiased;
}
.wrap{max-width:78rem;margin:0 auto;padding:0 clamp(1rem,4vw,3rem) 6rem}
.col{max-width:44rem}
h1,h2,h3{font-family:"Iowan Old Style","Palatino Linotype",Palatino,Georgia,serif;
  font-weight:600;text-wrap:balance;letter-spacing:-.01em}
h1{font-size:clamp(2rem,4.6vw,3.1rem);line-height:1.08;margin:0 0 .6rem}
h2{font-size:clamp(1.35rem,2.4vw,1.8rem);margin:3.4rem 0 .3rem}
h3{font-size:1.08rem;margin:2rem 0 .3rem}
p,li{color:var(--ink-2)}
p{margin:.75rem 0}
strong{color:var(--ink);font-weight:600}
code,.mono{font-family:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
  font-variant-numeric:tabular-nums}
code{font-size:.88em;background:var(--sunken);padding:.1em .34em;border-radius:3px;
  color:var(--ink)}
a{color:var(--accent)}
.eyebrow{font:600 .72rem/1 ui-monospace,SFMono-Regular,Menlo,monospace;
  letter-spacing:.18em;text-transform:uppercase;color:var(--ink-3);margin:0 0 1.2rem}
header.hero{padding:clamp(3rem,7vw,5.5rem) 0 1rem}
.standfirst{font-size:1.12rem;color:var(--ink-2);max-width:40rem}
.rule{height:1px;background:var(--rule);border:0;margin:2.5rem 0 0}
nav.jump{position:sticky;top:0;z-index:10;background:color-mix(in srgb,var(--paper) 88%,transparent);
  backdrop-filter:blur(8px);border-bottom:1px solid var(--rule);margin-bottom:1rem}
nav.jump ol{display:flex;gap:.2rem;list-style:none;margin:0;padding:.5rem 0;overflow-x:auto;
  counter-reset:m}
nav.jump a{display:block;padding:.3rem .6rem;border-radius:5px;text-decoration:none;
  font:500 .8rem/1.4 ui-sans-serif,system-ui,sans-serif;color:var(--ink-2);white-space:nowrap}
nav.jump a:hover,nav.jump a:focus-visible{background:var(--accent-soft);color:var(--accent)}
figure{margin:1.6rem 0 2rem;background:var(--surface);border:1px solid var(--rule);
  border-radius:10px;box-shadow:var(--shadow);overflow:hidden}
.scroller{overflow-x:auto;padding:1.1rem 1.1rem .4rem}
figcaption{padding:.2rem 1.1rem 1rem;color:var(--ink-3);font-size:.86rem;border-top:0}
figcaption b{color:var(--ink-2);font-weight:600}
svg{display:block}
text{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-variant-numeric:tabular-nums}
.axis{font-size:11px;fill:var(--ink-3)}
.axis.free{font-size:11px;fill:var(--ink-3);font-style:italic}
.cell rect{fill:var(--unknown);stroke:var(--surface);stroke-width:1}
.cell text{font-size:11px;fill:var(--paper);opacity:.92}
.g-unknown rect{fill:var(--unknown)}
.g-unknown text{fill:var(--ink-3)}
.g-id rect{fill:var(--menu)} .g-state rect{fill:var(--code)}
.g-anim rect,.g-draw rect{fill:var(--gfx)}
.g-pos rect,.g-vel rect,.g-audio rect{fill:var(--audio)}
.g-box rect{fill:var(--data)} .g-combat rect{fill:#c55a31}
.g-input rect{fill:var(--code);opacity:.72}
.g-acs rect{fill:#8c5bb8}
.bankbg{fill:var(--sunken)}
.r-code rect:not(.bankbg){fill:var(--code)} .r-data rect:not(.bankbg){fill:var(--data)}
.r-gfx rect:not(.bankbg){fill:var(--gfx)} .r-audio rect:not(.bankbg){fill:var(--audio)}
.r-menu rect:not(.bankbg){fill:var(--menu)} .r-free rect:not(.bankbg){fill:var(--free)}
.r-unknown rect:not(.bankbg){fill:var(--unknown)}
.freeline{stroke:var(--ink-3);stroke-width:1;stroke-dasharray:3 3}
.reg rect{stroke:var(--surface);stroke-width:1.5}
.addr{font-size:11px;fill:var(--ink-3)}
.rname{font-size:12.5px;fill:var(--paper);font-weight:600}
.rnote{font-size:11px;fill:var(--paper);opacity:.82}
.r-free .rname,.r-unknown .rname{fill:var(--ink)}
.r-free .rnote,.r-unknown .rnote{fill:var(--ink-2)}
.r-data .rname,.r-data .rnote{fill:#1a1400}
.legend{display:flex;flex-wrap:wrap;gap:.25rem 1.1rem;list-style:none;margin:.2rem 0 0;
  padding:0 1.1rem 1rem;font-size:.82rem;color:var(--ink-3)}
.legend li{display:flex;align-items:center;gap:.4rem}
.sw{width:.8rem;height:.8rem;border-radius:3px;display:inline-block;background:var(--unknown)}
.sw.r-code{background:var(--code)} .sw.r-data{background:var(--data)}
.sw.r-gfx{background:var(--gfx)} .sw.r-audio{background:var(--audio)}
.sw.r-menu{background:var(--menu)} .sw.r-free{background:var(--free)}
.pair{display:grid;grid-template-columns:repeat(auto-fit,minmax(19rem,1fr));gap:1.2rem}
table{border-collapse:collapse;width:100%;font-size:.9rem;margin:1rem 0}
th,td{text-align:left;padding:.45rem .7rem;border-bottom:1px solid var(--rule);vertical-align:top}
th{font:600 .74rem/1.3 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.08em;
  text-transform:uppercase;color:var(--ink-3)}
td:first-child{white-space:nowrap}
.tablewrap{overflow-x:auto}
.callout{border-left:3px solid var(--accent);background:var(--surface);padding:.85rem 1.1rem;
  border-radius:0 8px 8px 0;margin:1.4rem 0}
.callout p{margin:.3rem 0}
.callout .tag{font:600 .7rem/1 ui-monospace,Menlo,monospace;letter-spacing:.14em;
  text-transform:uppercase;color:var(--accent)}
/* the nav is sticky, so an anchor jump would otherwise land its target underneath it */
section[id],[id^="fn"]{scroll-margin-top:4rem}
a.fnref{font-size:.7em;vertical-align:super;line-height:0;text-decoration:none;
  padding:0 .12em;font-weight:600}
a.fnref:hover{text-decoration:underline}
.footnotes{margin:2rem 0 0;padding:1.1rem 0 0;border-top:1px solid var(--rule);
  font-size:.88rem;color:var(--ink-3)}
.footnotes h3{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.72rem;
  letter-spacing:.16em;text-transform:uppercase;color:var(--ink-3);margin:0 0 .6rem;font-weight:600}
.footnotes p{margin:.55rem 0;color:var(--ink-3)}
.footnotes strong{color:var(--ink-2)}
.footnotes pre{background:var(--sunken);border-radius:6px;padding:.7rem .85rem;overflow-x:auto;
  font-size:.82rem;line-height:1.5;color:var(--ink-2);margin:.7rem 0}
.footnotes .back{text-decoration:none;font-weight:600}

.palette{display:flex;flex-wrap:wrap;gap:0;border-radius:8px;overflow:hidden;margin:1.1rem 0;
  border:1px solid var(--rule)}
.palette i{flex:1 1 3.4rem;height:3.2rem;position:relative}
.palette i span{position:absolute;inset:auto 0 .25rem 0;text-align:center;font:500 9px/1 ui-monospace,Menlo,monospace;
  color:#fff;mix-blend-mode:difference;letter-spacing:.02em}
footer{margin-top:4rem;padding-top:1.4rem;border-top:1px solid var(--rule);color:var(--ink-3);
  font-size:.85rem}
@media (prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}
/* PRINT / PDF EXPORT. Two things break when this page is printed rather than
   scrolled: wide diagrams live in overflow-x containers, so anything past the
   page width is simply GONE in a PDF; and the dark palette wastes ink. Both are
   fixed here rather than in a separate stylesheet, so one file exports well. */
@media print{
  :root,:root[data-theme="dark"],:root:not([data-theme="light"]){
    --paper:#fff; --surface:#fff; --sunken:#f0f2f7;
    --ink:#000; --ink-2:#23262e; --ink-3:#4a5060;
    --rule:#c3c9d6; --accent:#25348c; --accent-soft:#eef0fa;
    --code:#25348c; --data:#8a6210; --gfx:#00615f; --audio:#256b25;
    --menu:#8a2f52; --free:#6b7286; --unknown:#d3d8e4; --shadow:none;
  }
  body{background:#fff}
  nav.jump{display:none}
  .scroller{overflow:visible;padding-bottom:1rem}
  svg{max-width:100%;height:auto}            /* scale wide diagrams to the page */
  figure{break-inside:avoid;box-shadow:none;border-color:var(--rule)}
  section{break-before:auto}
  h2{break-after:avoid}
  table{break-inside:auto}
  tr{break-inside:avoid}
  .callout{break-inside:avoid}
  a{color:var(--ink);text-decoration:underline}
  .hoveronly{display:none}
  .cell text{fill:#fff}
  .g-unknown text{fill:var(--ink-3)}
}


.fld rect{stroke:var(--surface);stroke-width:1.5}
.fname{font-size:11.5px;fill:var(--paper);font-weight:600}
.r-unknown .fname,.r-free .fname{fill:var(--ink-2)}
.r-data .fname{fill:#1a1400}
.r-combatc rect{fill:#c55a31}
.flow{display:grid;gap:.55rem;margin:1.2rem 0}
.step{display:grid;grid-template-columns:auto 1fr;gap:.9rem;align-items:start;
  background:var(--surface);border:1px solid var(--rule);border-radius:8px;padding:.7rem .9rem}
.step .n{font:600 .7rem/1.5 ui-monospace,Menlo,monospace;color:var(--paper);
  background:var(--accent);border-radius:4px;padding:0 .42rem;height:1.5rem;display:grid;
  place-items:center;min-width:1.5rem}
.step p{margin:0;font-size:.92rem}
.step .where{font-family:ui-monospace,Menlo,monospace;font-size:.78rem;color:var(--ink-3);
  display:block;margin-top:.15rem}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:3px}
"""


def build(sections_html):
    swatches = "".join(
        f'<i style="background:{c}"><span>{c[1:]}</span></i>' for c in URANUS)
    return f"""<title>Sailor Moon S — the data architecture</title>
<style>{CSS}</style>
<nav class="jump"><div class="wrap"><ol>
<li><a href="#model">Address model</a></li>
<li><a href="#rom">The cartridge</a></li>
<li><a href="#wram">Work RAM</a></li>
<li><a href="#struct">The object struct</a></li>
<li><a href="#boxes">Box data</a></li>
<li><a href="#chars">Characters</a></li>
<li><a href="#vram">Video memory</a></li>
<li><a href="#aram">Audio memory</a></li>
<li><a href="#chain">One move</a></li>
<li><a href="#records">Records</a></li>
<li><a href="#flows">Pipelines</a></li>
<li><a href="#room">Where there's room</a></li>
</ol></div></nav>
<div class="wrap">
<header class="hero col">
  <p class="eyebrow">Bishoujo Senshi Sailor Moon S · SFC · 1994</p>
  <h1>The data architecture</h1>
  <p class="standfirst">Where this game keeps everything, and what shape it is in.
  Four memories, one struct that matters more than the rest, and a great many
  records walked by generic code.</p>
</header>
<hr class="rule">
{sections_html}
<footer class="col">
  <p>Every address here was measured against the clean Japanese ROM
  <code>bc0e29ee…</code>, HiROM+FastROM, headerless. Companion to
  <code>docs/game/sms_data_architecture.md</code> in the repo, which carries the same
  material as text.</p>
  <p>Its palette is the game's own. Below is <strong>Sailor Uranus's character
  palette</strong> — the sixteen colours the cartridge paints her with, read from
  <code>$E0:06BE</code>. The diagram categories borrow from Neptune's, Pluto's and
  Moon's palettes, adjusted where a theme needed the contrast.</p>
  <div class="palette">{swatches}</div>
</footer>
</div>"""


SECTIONS = f"""
<section id="model" class="col">
<h2>The address model</h2>
<p>HiROM, FastROM, no copier header. The whole mapping reduces to one rule, and
every offset in this project is written with it in mind:</p>
<p><code>file offset = SNES address &amp; 0x3FFFFF</code></p>
<p>Banks <code>$C0-$FF</code> are the cartridge mapped straight through;
<code>$80-$BF</code> is a <strong>FastROM mirror of the same bytes</strong>, and the
game usually executes from it. That mirror is the single most expensive fact on
this page: a routine documented as <code>$C0:D055</code> runs as
<code>$80:D055</code>, so a watch on the wrong one sees nothing at all — which
reads exactly like "the game never does this".<a class="fnref" id="fnref1"
href="#fn1">[1]</a></p>
<div class="callout"><p class="tag">The cartridge, on paper</p>
<p>The header declares a <strong>4 MB</strong> ROM. The image is
<strong>2.5 MB</strong> — 40 banks, <code>$C0-$E7</code>. That gap is why every
patch in this project can append banks past the end and still boot, and why they
all target the first free bank, <code>$E8</code>.</p>
<p>Its title field is not ASCII: it is Shift-JIS half-width katakana,
<code>ｾｰﾗｰﾑｰﾝSｼｭﾔｸｿｳﾀﾞﾂｾﾝ</code>.</p></div>
</section>

<section id="rom">
<div class="col"><h2>Map 1 — the cartridge</h2>
<p>Code and tables at the bottom, a long run of character and stage graphics
through the middle, then the manifests and all of the audio at the top. Bar
height is measured packing — how much of each bank is neither <code>00</code> nor
<code>FF</code>.</p></div>
<figure><div class="scroller">{svg_banks()}</div>
{legend([("code","engine code"),("data","tables + manifests"),("gfx","graphics"),
         ("menu","front end / fonts"),("audio","sound driver + samples")])}
<figcaption><b>40 banks.</b> <span class="hoveronly">Hover any bank for what it holds. </span>Bank
<code>$8A</code> — a mirror of file bank <code>$0A</code> — is the one to know by
heart: it holds every collision box in the game.</figcaption></figure>
</section>

<section id="wram">
<div class="col"><h2>Map 2 — work RAM</h2>
<p>128 KB, about a third of it used. Low WRAM is mirrored into bank
<code>$00</code>, and direct page is <code>0</code> in essentially all game code —
so <code>$8D</code> and <code>$7E:008D</code> are the same byte written two
ways.</p></div>
<figure><div class="scroller">{band(WRAM, 0x2000, "Low work RAM", 500)}</div>
<figcaption><b>$7E:0000-$1FFF.</b> The two shadow buffers are DMA'd to the PPU
every frame — which is why a one-shot colour poke never survives, and why a
write-watch on VRAM catches nothing.</figcaption></figure>
</section>

<section id="struct">
<div class="col"><h2>The object struct — the centre of it all</h2>
<p>Everything that moves is one of these: both fighters, both projectiles, even
the portrait on the report card. Sixteen slots of <code>0x80</code> bytes from
<code>$1000</code>, and the same layout for all of them.</p></div>
<figure><div class="scroller">{svg_struct()}</div>
{legend([("menu","identity"),("code","state + input"),("gfx","animation + drawing"),
         ("audio","position + velocity"),("data","box indices"),("free","unmapped")])}
<figcaption><b>128 bytes, byte by byte.</b> <span class="hoveronly">Hover for each field. </span>The pale cells
are genuinely unmapped — about a third of the struct — and are shown as unknown
rather than guessed at.</figcaption></figure>
<div class="col">
<p>Four of these bytes carry most of the engine's meaning:</p>
<div class="tablewrap"><table>
<tr><th>Byte</th><th>Field</th><th>Why it matters</th></tr>
<tr><td><code>+0x00</code></td><td>charID / object type</td><td>1-9 are fighters,
<strong>10-27 are projectile types</strong> — and a projectile picks its box table
by its own id, never its owner's</td></tr>
<tr><td><code>+0x41</code></td><td>hurtbox index</td><td><strong>0 means
invulnerable.</strong> Invulnerability in this engine is the absence of a box, not
a flag — the backdash is invincible because its animation uses index 0 for all 14
frames</td></tr>
<tr><td><code>+0x48</code></td><td>first-hit defense</td><td>Worth one damage
column until the character is first hit that round. This is the entire source of
the "damage is random" folklore; <strong>there is no RNG in damage</strong></td></tr>
<tr><td><code>+0x18</code></td><td>action flags</td><td>bit 0 is the engine's own
"this act is an attack" answer — a better test than any action-ID range</td></tr>
</table></div>
</div>
</section>

<section id="boxes">
<div class="col"><h2>Box data — the table you will read most</h2>
<p>Three pointer tables sit next to each other in bank <code>$8A</code>, indexed
by <code>id * 2</code>: hit at <code>$8A:C1F1</code>, hurt at
<code>$8A:C229</code>, collision at <code>$8A:C23D</code>. They are
<code>0x14</code> bytes apart — the hurt table ends exactly where the collision
table begins.</p>
<p>That adjacency matters: <strong>only the hit table was widened</strong> to 28
entries for projectiles. Indexing hurt or collision by a projectile's object id
runs straight off the end into the neighbouring table. Gameplay never notices,
because nothing reads a projectile's hurtbox — but a tool that draws one renders
a flickering phantom out of unrelated bytes, and it took a while to work that
out.</p>
<p>Per character the three tables are contiguous, and the characters follow in
roster order — Moon's hit boxes at <code>$8A:C251</code>, then her hurt pairs,
then her six push boxes, then Mercury, and so on to Chibi Moon, with the nine
shared projectile tables last.</p>
<p>A box is eight bytes: two <code>(offset, width)</code> pairs — one per facing —
then a signed <code>y_off</code>, a height, and flags for guard height.
<strong>The origin is the character's feet and +y is down</strong>, so
<code>y_off</code> is normally negative. Height <code>0</code> means no box.</p>
</div>
</section>

<section id="chars">
<div class="col"><h2>A character is a manifest</h2>
<p>One pointer at <code>$E0:0238 + id*2</code> is where a fighter begins. The
record behind it is small: a defense byte, then pointers to palettes, a win icon,
an object palette, and the payload the loader expands into work RAM.</p>
<p>That very first byte is a real balance value hiding in plain sight — the
first-hit defense. Neptune ships with 2, Jupiter with 1, everyone else 0.</p>
<p>The palettes are where a character's identity actually lives. All nine are
structured identically — grey, outline, four skin tones, <strong>six costume
colours</strong>, two accents, a shared shade, white — and only those six costume
colours differ meaningfully between fighters. Re-hueing that ramp is how this
project authors new palette slots — and it is where this page's own palette comes
from.</p>
</div>
</section>

<section id="vram">
<div class="col"><h2>Map 3 — video memory</h2>
<p>VRAM is the one memory whose layout <strong>changes completely</strong> between
a match and a menu. Two different machines using the same 64 KB.</p></div>
<div class="pair">
<figure><div class="scroller">{band(VRAM_MATCH, 0x8000, "VRAM during a match", 430)}</div>
<figcaption><b>In a match.</b> The HUD is BG3, 2bpp, and its priority bit puts
those tiles <em>above</em> the sprites — which is how an in-match overlay is
possible without touching the sprite engine at all.</figcaption></figure>
<figure><div class="scroller">{band(VRAM_MENU, 0x0800, "VRAM on a menu screen", 430)}</div>
<figcaption><b>On a menu.</b> Addresses are tiles, not words. The 64 free tiles
above the font sheet are where patch 16's half-width alphabet lives — free on
every menu screen, overwritten the moment a match loads.</figcaption></figure>
</div>
<div class="col">
<div class="callout"><p class="tag">Two traps worth the ink</p>
<p><strong>A screen transition clears all 64 KB</strong> — one fixed-source DMA
with a length of zero, meaning 65536 — and the next screen reloads only its own
asset list. "It was in VRAM a moment ago" proves nothing.</p>
<p><strong>DMA never surfaces as a CPU write callback.</strong> A write-watch on
the free window saw zero writes across a whole match while snapshots caught 1416
bytes arriving. Any claim that a region is free needs both instruments, and they
have to disagree before you believe either.</p></div>
</div>
</section>

<section id="aram">
<div class="col"><h2>Map 4 — audio memory</h2>
<p>The APU has its own 64 KB and it is <strong>full</strong>: the largest run of
zeros in the whole of it is 64 bytes. ROM is not this project's constraint;
this is.</p></div>
<figure><div class="scroller">{band(ARAM, 0x10000, "ARAM", 480)}</div>
<figcaption><b>The APU's 64 KB.</b> A fighter's voice is uploaded
<em>per player</em>, not per character — two fixed banks near the top, filled with
whoever is on screen — while a nine-character directory sits resident from boot.
</figcaption></figure>
<div class="col"><p>Pitch is per-sound note data rather than a per-sample rate:
each sound's sequence header carries a transpose byte worth one semitone per
unit. That is the whole of patch 101 — and the reason it cannot correct two
characters at once, since the transpose lives in a sequence they share.</p></div>
</section>
<section id="chain">
<div class="col"><h2>One move, end to end</h2>
<p>The clearest way to see what "data-driven" means here: Uranus's crouching
light punch, followed from her character id to the pixels of her hitbox. Four
table reads, and not one line of code specific to her.</p>
<div class="flow">
<div class="step"><span class="n">1</span><p>Her id picks an <strong>action
table</strong>.<span class="where">$C0:0000 + 6&times;2 &rarr; $C0:0FF1</span></p></div>
<div class="step"><span class="n">2</span><p>The act picks a <strong>script</strong>
&mdash; <code>02 35 | 03 36 | 80</code>: three frames of pose <code>$35</code>,
four of pose <code>$36</code>, then hold.<span class="where">$C0:0FF1 +
0x53&times;2 &rarr; $C0:122C</span></p></div>
<div class="step"><span class="n">3</span><p>The pose is a <strong>4-byte
record</strong> &mdash; <code>09 0A 2C 02</code>: class 9, hit box
<code>$0A</code>, hurt pair <code>$2C</code>, push box <code>$02</code>.
<span class="where">$84:809C + 6&times;2 &rarr; $84:8A44, + 0x36&times;4</span></p></div>
<div class="step"><span class="n">4</span><p>The index reads a <strong>box</strong>
&mdash; <code>FC 37 CD 37 CC 14 03 00</code>: 55 px wide starting 4 px behind her
origin, 20 px tall at head height, hitting high and low.<span class="where">$8A:C1F1
+ 6&times;2 &rarr; $8A:E3E1, + 0x0A&times;8</span></p></div>
</div>
<p>The startup pose <code>$35</code> carries hit index <strong>00</strong> &mdash;
that is how a startup frame is expressed in this engine: a pose with no attack
box. Change the <code>02</code> in step 2 and you have changed her startup. That
is the whole mechanism behind this project's frame-data patches, and the reason
they need no hooks at all.</p>
</div>
</section>

<section id="records">
<div class="col"><h2>The record catalogue</h2>
<p>This is what "data-driven" means in practice. Each of these is walked by
generic engine code, and each was confirmed against a real example decoded out of
the cartridge &mdash; a layout without a worked example is a hypothesis.</p>
<h3>A collision box &mdash; 8 bytes</h3></div>
<figure><div class="scroller">{strip(BOX_ENTRY, label="Box entry byte layout")}</div>
<figcaption>Two <b>(offset, width)</b> pairs &mdash; one per facing &mdash; then a
signed vertical offset, a height, and guard-height flags. The origin is the
character's feet and <b>+y is down</b>, so <code>y_off</code> is normally
negative; height zero means no box at all. A hurt entry is two of these: body,
then head.</figcaption></figure>

<div class="col"><h3>An on-hit record &mdash; 4 bytes</h3></div>
<figure><div class="scroller">{strip(ONHIT_REC, label="On-hit record byte layout")}</div>
<figcaption>Indexed by <code>(attackID &gt;&gt; 1) &times; 4</code> into
<code>$C0:CDD5</code> and its eight sibling tables, selected by attack and
defender posture. <b>These tables are global &mdash; indexed by strength class,
not by character</b>, which is why this project has never edited hitstun here: it
would change every character's move of that class.</figcaption></figure>

<div class="col"><h3>An asset job &mdash; 10 bytes</h3></div>
<figure><div class="scroller">{strip(ASSET_REC, label="Compressed-asset job record")}</div>
<figcaption>The record that drives every menu upload. <b>The length sits two
bytes before the source pointer</b> &mdash; read the other way round, you pair
record N's length with record N+1's source, which is exactly why three separate
attempts to grow one transfer "changed nothing": they were quietly lengthening an
unrelated upload. The menu font's record reads <code>vram $4000 &middot; len
$3480 &middot; src $C4:2590 &middot; dest $7E:C000</code>, and patch 16 changes
precisely one field of it.</figcaption></figure>

<div class="col"><h3>A stage name &mdash; 102 bytes</h3></div>
<figure><div class="scroller">{strip(STAGE_REC, label="Stage-name record")}</div>
<figcaption><b>There is no terminator.</b> The name is <em>centred</em> in a
fixed 24-word field by leading and trailing zero words, and the bottom row is the
top row plus <code>$10</code>. Read as "start at the first glyph, stop at zero",
this record looks terminated &mdash; and the build made on that reading wrote a
longer name straight through the bottom row into the next stage's header,
corrupting the screen and hanging the game a second after stage select. Two
records side by side would have shown the padding immediately.</figcaption></figure>

<div class="col">
<div class="callout"><p class="tag">Three structures, one throw</p>
<p>A throw is decided by three separate records, which is how a character can
have all three wrong independently: a <strong>4 &times; 8-byte table indexed by
attack button</strong> picks which throw comes out (its last byte is the act), a
<strong>5-byte toss record</strong> holds the forward velocity (negated when the
thrower faces left), and the <strong>hold script</strong> decides escapability
&mdash; any step whose byte 5 is non-zero samples the victim's mashing.</p>
<p>Saturn shipped with the first two wrong, inherited from the game she was
ported out of. The engine was faithfully executing correct code on incorrect data
for thirty years.</p></div>
</div>
</section>

<section id="flows">
<div class="col"><h2>What happens in one frame</h2>
<div class="flow">
<div class="step"><span class="n">1</span><p>The pad is read once per frame and
press edges are derived from it.<span class="where">$80:8353 &mdash; the
canonical per-frame anchor for tooling</span></p></div>
<div class="step"><span class="n">2</span><p>Every object runs its state
processor, which walks the current action script: it sets the pose, the step
duration, and <strong>the three box indices</strong>.<span class="where">JSL
$C1:0000 &rarr; $C0:9CCD writes +0x40/41/42</span></p></div>
<div class="step"><span class="n">3</span><p>Boxes are tested against each other,
read <strong>live out of ROM bank $8A</strong> &mdash; never staged
anywhere.<span class="where">$C0:BFC0</span></p></div>
<div class="step"><span class="n">4</span><p>On a hit: the on-hit record supplies
damage and hitstun, eleven handlers compose a column shift from counter-hit,
first-hit defense and A.C.S. stats, the matrix turns it into a number, and one of
eight apply sites subtracts it.<span class="where">$C0:CDD5 &rarr;
0xCAED-0xCD6D &rarr; $80:D055</span></p></div>
<div class="step"><span class="n">5</span><p>The reaction is dispatched by
posture &times; hit level, setting pushback or launch velocity and the victim's
reaction act.<span class="where">$C1:0E85</span></p></div>
<div class="step"><span class="n">6</span><p>The HUD is <em>computed</em> into
WRAM staging, then <em>uploaded</em> in the next vblank &mdash; a split that lets
a patch compute in one place and draw in the other.<span class="where">$C0:D5E8
producer, $C0:D56F uploader</span></p></div>
</div>
<p>Two things to know before hooking any of this: <strong>the HUD producer never
runs in Practice mode</strong>, so code hooked there is dead in the mode people
actually train in &mdash; and <strong>attacks are not processed on an action's
step 0</strong>, which puts the engine's effective timing one frame later than
the action's start.</p>
</div>
</section>

<section id="room">
<div class="col"><h2>Where there is room</h2>
<p>Every change bigger than a few bytes has to go somewhere. The inventory, all
measured:</p>
<div class="tablewrap"><table>
<tr><th>Space</th><th>Size</th><th>Notes</th></tr>
<tr><td>Appended banks <code>$E8+</code></td><td>effectively unlimited</td>
<td>The image ends at <code>$E7</code> and the header declares 4 MB &mdash; so
this is free, legal, and where every non-trivial patch puts its code</td></tr>
<tr><td>ROM hole <code>$C1:BE09</code></td><td>63 bytes</td>
<td>The classic free code hole; patches 1 and 2 live in it</td></tr>
<tr><td>ROM hole <code>$C1:BE85</code></td><td>69 bytes</td><td>Patch 6</td></tr>
<tr><td>WRAM <code>$0816-$09FF</code></td><td>490 bytes</td>
<td><b>VS matches only</b> &mdash; native Practice uses the whole range</td></tr>
<tr><td>WRAM <code>$7F:6000+</code></td><td>~31 KB</td>
<td>Untouched in steady-state play; four patches keep their state here</td></tr>
<tr><td>VRAM BG3 CHR <code>0xC7-0xDF</code></td><td>25 tiles</td>
<td>Free in every matchup &mdash; the in-match font window</td></tr>
<tr><td>VRAM menu <code>$5C0-$5FF</code></td><td>64 tiles</td>
<td>Free on every menu screen, gone at match load</td></tr>
<tr><td>CGRAM OBJ row 7</td><td>16 colours</td><td>Never loaded, never drawn</td></tr>
<tr><td><b>ARAM</b></td><td><b>~0</b></td>
<td>The largest zero run in the APU's 64 KB is 64 bytes. Audio is the one hard
wall &mdash; adding a voice means displacing one</td></tr>
</table></div>
<div class="callout"><p class="tag">Two rules about "free"</p>
<p><strong>Unreferenced and unchanging is not free.</strong> A 7 KB region of
audio RAM passed both tests and was still live &mdash; proven only by finding its
bytes back in a ROM bank. On this console everything was uploaded from somewhere;
ask where it came from.</p>
<p><strong>A write-watch cannot prove a region is free</strong>, because DMA is
not a CPU write. Snapshot as well, and make the two instruments disagree before
you believe either.</p></div>
</div>
</section>

<section id="notes" class="col">
<div class="footnotes">
<h3>Footnote</h3>
<p id="fn1"><strong>[1] Why one routine has three addresses, and why it matters.</strong>
There are two different spaces in play, and the rule above converts between
them. The cartridge is a <em>file</em> — 2.5 MB of bytes numbered
<code>0</code> to <code>0x27FFFF</code>. The CPU never sees a file; it sees an
address space of 256 banks of 64 KB, which also holds RAM and hardware
registers. The mapping is simply: which byte of the file appears at which CPU
address? The cartridge's wiring decides that, and there were two common
conventions — LoROM and HiROM. This game is HiROM, so a full 64 KB slab of the
file appears in each bank.</p>
<p><code>&amp; 0x3FFFFF</code> means "throw away everything above the low 22
bits, and what is left is the position in the file". Twenty-two bits, because a
HiROM cartridge tops out at 4 MB and that is all it takes to name any byte of
one. Worked out on the routine named above:</p>
<pre>$C0:D055  →  0xC0D055 &amp; 0x3FFFFF  =  0x00D055  →  c2 30 85 02 a5 00
$80:D055  →  0x80D055 &amp; 0x3FFFFF  =  0x00D055  →  c2 30 85 02 a5 00
$40:D055  →  0x40D055 &amp; 0x3FFFFF  =  0x00D055  →  c2 30 85 02 a5 00</pre>
<p><strong>Those are not three copies. They are one set of bytes, visible at
three addresses.</strong> The high bits choose which window you look through,
not which byte you get — being wired into the address space several times over
was normal on this console.</p>
<p>The game prefers the <code>$80</code> window for speed: the SNES reads the
cartridge at 2.68 MHz through most windows and at 3.58 MHz through banks
<code>$80-$FF</code> when the cartridge asks for it, which this one does (its
map-mode byte is <code>$31</code> — HiROM <em>and</em> FastROM). About a third
faster, for free.</p>
<p>And that is where the cost lands: <strong>breakpoints and watches are keyed to
an address, not to a byte.</strong> Break on <code>$C0:D055</code> and the CPU
will execute those exact bytes through <code>$80:D055</code> all day without
tripping it. Your probe prints nothing — and nothing looks identical to "the game
never calls this". Low work RAM has the same sibling trap, visible as both
<code>$7E:1000</code> and <code>$00:1000</code>.</p>
<p>One last thing the rule assumes: <strong>no copier header</strong>. Some dumps
carry an extra 512 bytes at the front, added by the hardware that made them; with
one of those, every offset on this page is wrong by 512. The SHA-1 in the footer
is what pins that down. <a class="back" href="#fnref1">↩ back</a></p>
</div>
</section>
"""

# The Artifact host wraps the page in its own <!doctype>/<head>/<body>, so the
# default output is a FRAGMENT. Exporting one file that opens in a browser needs
# a real document — above all a charset, since this page carries Japanese
# katakana, box-drawing rules and em dashes that mojibake without it.
STANDALONE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Where Bishoujo Senshi Sailor Moon S (SFC, 1994) keeps its data and what shape it is in: four memory maps, the object struct byte by byte, and the record formats the engine walks.">
<meta name="color-scheme" content="light dark">
{head}
</head>
<body>
{body}
</body>
</html>
"""


def standalone(page):
    """Split the fragment at </style> into head-ish and body-ish halves."""
    cut = page.index("</style>") + len("</style>")
    return STANDALONE.format(head=page[:cut].strip(), body=page[cut:].strip())


if __name__ == "__main__":
    page = build(SECTIONS)
    if "--standalone" in sys.argv:
        sys.argv.remove("--standalone")
        OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else OUT
        page = standalone(page)
    OUT.write_text(page, encoding="utf-8")
    print("wrote", OUT, OUT.stat().st_size, "bytes")
