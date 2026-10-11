#!/usr/bin/env python3
"""mkdonorpatch.py — build Rev. SS's two-ROM patch: diffed against SMS + Super S, so no Super S bytes ship.

    python3 tools/saturn/mkdonorpatch.py build/SailorMoonS_Rev_SS-03.sfc release/Rev.SS-03.donor.bps

Format and rationale: tools/saturn/donorpatch.py. Steps:
  1. diff the target against SMS || Super S || EVERY decodable Super S LZ stream,
     and keep the streams the delta actually leans on (>= MIN_REF bytes copied);
  2. diff again against SMS || Super S || just those streams — the shipped patch;
  3. stamp the JSON metadata (format, both input SHA-1s, streams, target SHA-1);
  4. re-apply it with the applier's own code and require the target's SHA-1;
  5. audit the literal payload and REFUSE if any run >= 16 bytes is >= 90%
     identical to Super S content (raw or decompressed). Transformed donor data
     below that bar (a rebased pointer table, say) is printed, not refused.

Needs tools/Flips/flips (its suffix-array delta finds copies anywhere in the
source, which is the whole trick) and both clean ROMs (smspaths).
"""
import subprocess
import sys
import tempfile
from collections import Counter
from hashlib import sha1
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(REPO / "tools"))
sys.path.insert(0, str(HERE))
from cliguard import reject_unknown_flags
from smspaths import clean_rom, require_source, supers_bytes, SUPERS_SHA1, CLEAN_SHA1
import donorpatch as DP

FLIPS = REPO / "tools" / "Flips" / "flips"
MIN_REF = 256          # a stream earns its place in the source by >= this many copied bytes


def flips_delta(source, target, tmp):
    s, t, p = tmp / "source.bin", tmp / "target.sfc", tmp / "patch.bps"
    s.write_bytes(source)
    t.write_bytes(target)
    subprocess.run([str(FLIPS), "--create", "--bps-delta", str(s), str(t), str(p)],
                   check=True, stdout=subprocess.DEVNULL)
    return p.read_bytes()


def main():
    reject_unknown_flags(sys.argv, set(), "mkdonorpatch.py")
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    target_path, out_path = Path(sys.argv[1]), Path(sys.argv[2])
    if not FLIPS.exists():
        raise SystemExit("error: tools/Flips/flips missing — see HANDOFF.md §2")
    require_source(clean_rom())                # SHA-1 gate on the clean SMS ROM
    sms = Path(clean_rom()).read_bytes()
    supers = supers_bytes()                    # SHA-1 verified Super S
    target = target_path.read_bytes()

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        # 1. which streams does the delta want?
        offsets = []
        for idx in range(400):
            src = DP.LZ.job_entry(supers, idx)[0]
            if src in offsets or not (0 < src < len(supers) - 2):
                continue
            try:
                DP.LZ.lz_decompress(supers, src)
            except (ValueError, IndexError):
                continue
            offsets.append(src)
        spans, at = [], len(sms) + len(supers)
        for off in offsets:
            n = len(DP.LZ.lz_decompress(supers, off))
            spans.append((at, at + n, off))
            at += n
        wide = flips_delta(DP.build_source(sms, supers, offsets), target, tmp)
        used = Counter()
        for so, ln in DP.referenced_source(wide):
            for lo, hi, off in spans:
                if lo <= so < hi:
                    used[off] += ln
        streams = sorted(off for off, n in used.items() if n >= MIN_REF)

        # 2-3. the shipped patch
        patch = flips_delta(DP.build_source(sms, supers, streams), target, tmp)
        meta = {"format": DP.FORMAT,
                "sms_sha1": CLEAN_SHA1, "supers_sha1": SUPERS_SHA1,
                "streams": [f"0x{s:06X}" for s in streams],
                "target_sha1": sha1(target).hexdigest(),
                "target_name": target_path.name}
        patch = DP.with_meta(patch, meta)

    # 4. round trip through the applier's own code
    if DP.apply(patch, sms, supers) != target:
        raise SystemExit("error: the patch does not reproduce the target")

    # 5. what ships verbatim?
    a = DP.audit(patch, sms, supers)
    print(f"{out_path.name}: {len(patch)} bytes, {len(streams)} decompressed streams, "
          f"{a['literal_bytes']} literal bytes")
    print(f"  literal bytes matching Super S 8-grams absent from SMS: {a['donor_8grams']}")
    for op, ln, r, where in a["near_runs"]:
        print(f"  note: literal run at ${op:06X} ({ln} B) is {r:.0%} like {where} — transformed, kept")
    if a["verbatim_runs"]:
        for op, ln, r, where in a["verbatim_runs"]:
            print(f"  REFUSED: literal run at ${op:06X} ({ln} B) is {r:.0%} identical to {where}")
        raise SystemExit("error: Super S content would ship verbatim — not writing the patch")
    out_path.write_bytes(patch)
    print(f"  wrote {out_path} (target {meta['target_sha1'][:8]}…)")


if __name__ == "__main__":
    main()
