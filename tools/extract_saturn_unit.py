#!/usr/bin/env python3
"""Extract Sailor Saturn's complete data unit from Super S — the Route A port bundle.

Pulls every DATA component the SMS port needs (docs/saturn/supers_map.md has the
decoded systems; docs/saturn/saturn_notes.md the dossier) into build/saturn_unit/
as raw .bin blobs + manifest.json (addresses, sizes, sha1s, rebase rules, TODOs).
ROM-derived output stays in build/ (gitignored) — never commit the bundle.

Components (all verified 2026-07-30 unless flagged TODO in the manifest):
  anim_scripts    $C0:2105..$C0:252B  act-ptr table + [dur,pose] step scripts
  pose_records    $84:9209..$84:9401  126 x [class,hit,hurt,coll] (+guard-fix info)
  pose_to_cels    $CB:4892..$CB:499A  132 x (celA,celB)
  cel_records     $CB:1346 + 115*5    [addr24,size16] per cel
  cels_dd/de/df   $DD:0D40-FEE0 / $DE:0000-FC60 / $DF:0000-34E0 (136.7 KB)
  boxes hit/hurt/coll  $AF:EC3A/ED2A/F2FA (30x8 / 93x16 / 6x8)
  recognizers     $C1:1452..$C1:161A  ptr list + 5 motion specs (format partial)
  button_map      $C1:174E            7-byte button->request-nibble record
  special_actlists $C1:0940..$C1:0968 normal/special act lists (indexing TODO)
  manifest_record $E0:AC6A            16-byte char manifest (d48=1 + pal ptrs)
  palettes        pal1/pal2/icon/obj  0x20 each (size ASSUMED — see TODO)

Rebase rules (manifest carries them machine-readable):
  * anim_scripts: internal act pointers are bank-$C0-absolute; add (new_base - 0x2105).
  * cel_records: addr24 = bank-delta rebase ONLY — cels must keep their in-bank
    offsets (DMA A-bus wraps at bank boundaries), i.e. land in 3 fresh SMS banks
    at the same in-bank ranges.
  * pose_records/pose_to_cels/boxes/button_map: verbatim.
  * guard fix (ships-fixed policy): pose_records offsets 0x74/0x80 byte0 00->09.

Usage: python3 tools/extract_saturn_unit.py [--out DIR] [--check]
Reads smspaths.supers_rom(), SHA-verified unconditionally. --check re-parses the
extracted blobs and cross-validates against the ROM (also run by default).
"""
import sys, json, hashlib, argparse
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import supers_rom, SUPERS_SHA1  # noqa: E402

CID = 10  # Saturn

# ---- verified source addresses (file offset = SNES & 0x3FFFFF) ----
SCRIPTS_LO, SCRIPTS_HI = 0x002105, 0x00252B      # $C0:2105..252B (char slice)
POSES_LO, POSES_HI = 0x049209, 0x049401          # $84:9209..9401 (126 x 4B)
P2C_LO, P2C_HI = 0x0B4892, 0x0B499A              # $CB:4892..499A (132 x 2B)
CELREC_LO = 0x0B1346                             # $CB:1346, 5B each
NCELS = 115                                      # max cel index 0x72 + 1
CEL_SPANS = {                                    # per-bank in-bank ranges
    "dd": (0xDD, 0x0D40, 0xFEE0),
    "de": (0xDE, 0x0000, 0xFC60),
    "df": (0xDF, 0x0000, 0x34E0),
}
BOXES = {"hit": (0x2FEC3A, 30 * 8), "hurt": (0x2FED2A, 93 * 16), "coll": (0x2FF2FA, 6 * 8)}
RECOG_LO, RECOG_HI = 0x011452, 0x01161A          # $C1:1452..161A
BTNMAP_LO, BTNMAP_N = 0x01174E, 7                # $C1:174E
ACTLIST_LO, ACTLIST_HI = 0x010940, 0x010968      # $C1:0940..0968
OAM_LO, OAM_HI = 0x078000, 0x07BE5E              # $87:8000 OAM sprite-layout blob
MANIFEST_LO, MANIFEST_N = 0x20AC6A, 16           # $E0:AC6A
PALETTES = {"pal1": 0x20B0C8, "pal2": 0x20B0A8, "icon": 0x20B270, "obj": 0x20B208}
PAL_N = 0x20                                     # ASSUMED (16 colors x 2B)

GUARDFIX = [  # (blob offset in pose_records, pose, vanilla, fixed)
    (0x1D * 4, 0x1D, 0x00, 0x09),  # far 5LK + close 5HK startup
    (0x20 * 4, 0x20, 0x00, 0x09),  # far 5HK startup
]
CLASS_VOCAB = {0, 2, 4, 6, 8, 9, 11, 13}


def sha1(b):
    return hashlib.sha1(b).hexdigest()


def parse_script(rom, p, limit=0x300):
    """Parse one act script at bank-$C0 offset p -> (steps, end_off). Steps are
    (kind, a, b): kind in {step, cmd, loop, hold}."""
    steps, i = [], 0
    while i < limit:
        d, arg = rom[p + i], rom[p + i + 1]
        c = d & 0xC0
        if c == 0x40:
            steps.append(("loop", d & 0x3F, None)); return steps, p + i + 1
        if c == 0x80:
            steps.append(("hold", d, None)); return steps, p + i + 1
        if c == 0xC0:
            steps.append(("cmd", d, arg)); i += 2; continue
        steps.append(("step", d + 1, arg)); i += 2
    raise SystemExit(f"error: unterminated script at $C0:{p:04X}")


def extract(rom, outdir):
    comps, notes = {}, []

    def put(name, blob, snes, **meta):
        (outdir / f"{name}.bin").write_bytes(blob)
        comps[name] = {"file": f"{name}.bin", "snes": snes, "size": len(blob),
                       "sha1": sha1(blob), **meta}

    # 1) anim scripts — char slice; the act-ptr table ends where the lowest
    # in-slice pointer begins (iterative bound, same trick as the SMS extractors)
    blob = rom[SCRIPTS_LO:SCRIPTS_HI]
    min_ptr, act, entries = 0x252B, 0, []
    while 0x2105 + 2 * act < min_ptr:
        w = rom[SCRIPTS_LO + 2 * act] | rom[SCRIPTS_LO + 2 * act + 1] << 8
        if w:
            if not (0x2105 < w < 0x252B):
                raise SystemExit(f"error: act {act:02X} ptr $C0:{w:04X} outside slice")
            min_ptr = min(min_ptr, w)
        entries.append((act, w))
        act += 1
    nacts = act
    acts = {}
    for a, w in entries:
        if not w:
            continue
        steps, end = parse_script(rom, w)   # end = one past the terminator byte
        if end > 0x252B:
            raise SystemExit(f"error: act {a:02X} script overruns slice")
        acts[f"{a:02X}"] = {"ptr": f"{w:04X}", "steps": len(steps),
                            "cmds": sum(1 for s in steps if s[0] == "cmd")}
    put("anim_scripts", blob, "$C0:2105", base=0x2105, acts_in_table=nacts,
        act_scripts=len(acts),
        rebase="internal act ptrs are bank-absolute: add (new_base - 0x2105)",
        acts=acts)
    ncmd = sum(a["cmds"] for a in acts.values())
    notes.append(f"scripts: {nacts} act slots, {len(acts)} scripted, {ncmd} CMD steps "
                 "(SMS interpreter $80:A05C has NO CMD case — strip or back-port)")

    # 2) pose records — validate vocab + box-index bounds
    blob = rom[POSES_LO:POSES_HI]
    for i in range(0, len(blob), 4):
        cls, hit, hurt, coll = blob[i:i + 4]
        if cls not in CLASS_VOCAB:
            raise SystemExit(f"error: pose {i//4:02X} class {cls:02X} outside vocab")
        if hit >= 30 or hurt >= 93 or coll >= 6:
            raise SystemExit(f"error: pose {i//4:02X} box index out of range "
                             f"({hit:02X}/{hurt:02X}/{coll:02X})")
    put("pose_records", blob, "$84:9209", poses=len(blob) // 4,
        guardfix=[{"offset": o, "pose": f"{p:02X}", "vanilla": v, "fixed": f}
                  for o, p, v, f in GUARDFIX],
        rebase="verbatim; apply guardfix bytes at build time (ships-fixed policy)")

    # 3) pose->cels + cel records; cross-check spans
    p2c = rom[P2C_LO:P2C_HI]
    put("pose_to_cels", p2c, "$CB:4892", entries=len(p2c) // 2, rebase="verbatim")
    crec = rom[CELREC_LO:CELREC_LO + NCELS * 5]
    used = sorted({c for c in p2c})
    if max(used) >= NCELS:
        raise SystemExit(f"error: pose->cels references cel {max(used):02X} >= {NCELS}")
    total = 0
    for c in used:
        a = crec[5 * c] | crec[5 * c + 1] << 8 | crec[5 * c + 2] << 16
        sz = crec[5 * c + 3] | crec[5 * c + 4] << 8
        total += sz
        if sz == 0:
            continue
        bank, off = a >> 16, a & 0xFFFF
        span = next((s for s in CEL_SPANS.values() if s[0] == bank), None)
        if span is None or not (span[1] <= off and off + sz <= span[2]):
            raise SystemExit(f"error: cel {c:02X} ${a:06X}+{sz:#x} outside known spans")
    put("cel_records", crec, "$CB:1346", cels=NCELS, cels_referenced=len(used),
        streamed_bytes=total,
        rebase="addr24 bank-delta ONLY: cels must keep in-bank offsets "
               "(DMA A-bus wraps at bank boundary) -> 3 fresh SMS banks, same ranges")

    # 4) cel blobs, one per bank
    for tag, (bank, lo, hi) in CEL_SPANS.items():
        b = rom[(bank & 0x3F) << 16 | lo:(bank & 0x3F) << 16 | hi]
        put(f"cels_{tag}", b, f"${bank:02X}:{lo:04X}", in_bank_lo=lo, in_bank_hi=hi)

    # 5) boxes
    for tag, (lo, n) in BOXES.items():
        put(f"boxes_{tag}", rom[lo:lo + n], f"$AF:{lo & 0xFFFF:04X}", rebase="verbatim")

    # 6) bank $C1 records
    put("recognizers", rom[RECOG_LO:RECOG_HI], "$C1:1452",
        todo="motion-spec format only partially decoded (2B entries, FF-terminated "
             "streams, list at +0: 145E 15F1 15FA 1603 160C FFFF)")
    put("button_map", rom[BTNMAP_LO:BTNMAP_LO + BTNMAP_N], "$C1:174E", rebase="verbatim")
    put("special_actlists", rom[ACTLIST_LO:ACTLIST_HI], "$C1:0940",
        todo="per-char indexing of these lists + the gating-flag record base "
             "not yet located (consumer $C1:096B gets Y from caller)")

    # 6b) OAM sprite-layout (4th animation layer; found during the smoke test)
    oam = rom[OAM_LO:OAM_HI]
    p2c_words = [oam[2 * i] | oam[2 * i + 1] << 8 for i in range(132)]
    nvalid = sum(1 for w in p2c_words if 0x8000 <= w < OAM_HI - 0x070000)
    put("oam_layout", oam, "$87:8000", pose_words_valid=nvalid,
        rebase="pose->list words are in-bank absolute: keep in-bank offset 0x8000 in "
               "the destination bank. Char-table entry bank byte MUST be a $80-$BF "
               "WRAM-mirror bank (emitters write the OAM shadow via DB-absolute).")

    # 7) manifest + palettes
    put("manifest_record", rom[MANIFEST_LO:MANIFEST_LO + MANIFEST_N], "$E0:AC6A",
        note="d48=1 (first_hit_defense) + 4 palette ptrs + vestigial anim field")
    for tag, lo in PALETTES.items():
        put(f"palette_{tag}", rom[lo:lo + PAL_N], f"$E0:{lo & 0xFFFF:04X}",
            todo="size 0x20 ASSUMED — confirm against SMS palette port (mkpatch3)")

    notes.append("NOT in this bundle (code, ported separately): her per-char proc "
                 "block $C1:C6F7+ (~4.3 KB, main-dispatch table $C1:00A6-twin entry "
                 "10) + projectile procs, and the 0xC0 CMD handler $80:FBB4")

    # ---- ground-truth tripwires (measured 2026-07-30, saturn_notes.md) ----
    pr = rom[POSES_LO:POSES_HI]
    assert pr[0x6B * 4:0x6B * 4 + 4] == bytes.fromhex("091b5002"), "pose 6B drifted"
    assert pr[0x20 * 4:0x20 * 4 + 4] == bytes.fromhex("00001700"), "pose 20 drifted"
    assert pr[0x1D * 4:0x1D * 4 + 4] == bytes.fromhex("00001400"), "pose 1D drifted"
    s4c, _ = parse_script(rom, rom[SCRIPTS_LO + 0x98] | rom[SCRIPTS_LO + 0x99] << 8)
    assert s4c[1:] == [("step", 7, 0x20), ("step", 10, 0x21), ("hold", 0x80, None)], \
        "act 4C script drifted"
    hb = rom[BOXES["hit"][0]:BOXES["hit"][0] + 240]
    assert hb[0x1B * 8 + 1] == 0 and hb[0x1B * 8 + 5] == 0, "marker box 1B not zero-size"
    return comps, notes


def main():
    ap = argparse.ArgumentParser(description="Extract Saturn's Route A data bundle")
    ap.add_argument("--out", default=str(REPO / "build" / "saturn_unit"))
    ap.add_argument("--check", action="store_true", help="validate only, write nothing")
    args = ap.parse_args()

    path = supers_rom()
    rom = open(path, "rb").read()
    if len(rom) % 0x8000 == 0x200:
        rom = rom[0x200:]
    h = sha1(rom)
    if h != SUPERS_SHA1:
        raise SystemExit(f"error: Super S ROM sha1 {h} != expected {SUPERS_SHA1}")

    outdir = _P(args.out)
    if args.check:
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            comps, notes = extract(rom, _P(td))
        print("CHECK OK —", len(comps), "components validate")
        return

    outdir.mkdir(parents=True, exist_ok=True)
    comps, notes = extract(rom, outdir)
    total = sum(c["size"] for c in comps.values())
    manifest = {
        "what": "Sailor Saturn data unit extracted from Super S (Route A port bundle)",
        "source_rom_sha1": SUPERS_SHA1, "char_id": CID,
        "extracted_by": "tools/extract_saturn_unit.py",
        "docs": ["docs/saturn/supers_map.md", "docs/saturn/saturn_notes.md"],
        "components": comps, "notes": notes, "total_bytes": total,
    }
    (outdir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {len(comps)} components + manifest.json -> {outdir}")
    print(f"total {total} bytes ({total/1024:.1f} KB)")
    for n in notes:
        print("note:", n)


if __name__ == "__main__":
    main()
