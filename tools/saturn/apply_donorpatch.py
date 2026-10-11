#!/usr/bin/env python3
"""apply_donorpatch.py — build Rev. SS from your own two cartridges: the command-line twin of release/Rev.SS-NN.html.

    python3 tools/saturn/apply_donorpatch.py release/Rev.SS-03.donor.bps <rom> <rom> <out.sfc>

The two <rom> are your clean dumps of Sailor Moon S and Sailor Moon SuperS, in
either order (they are told apart by SHA-1; a 512-byte copier header is
stripped). Every step is verified: both inputs, the rebuilt source and the
output, whose SHA-1 is the one printed in release/RELEASE_NOTES.md.

This is the TOOL OF RECORD for the format (tools/saturn/donorpatch.py); the
browser page must produce the same bytes (tools/saturn/test_donorpatch.sh).
Python 3 standard library only — no repo checkout beyond tools/saturn/ needed.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import donorpatch as DP


def main():
    args = sys.argv[1:]
    if len(args) != 4 or any(a.startswith("-") for a in args):
        raise SystemExit(__doc__)
    patch_p, rom_a, rom_b, out_p = map(Path, args)
    if out_p.resolve() in {rom_a.resolve(), rom_b.resolve(), patch_p.resolve()}:
        raise SystemExit("error: refusing to overwrite an input")
    patch = patch_p.read_bytes()
    try:
        meta = DP.read_meta(patch)
        sms, supers = DP.identify([(rom_a.name, rom_a.read_bytes()),
                                   (rom_b.name, rom_b.read_bytes())], meta)
        out = DP.apply(patch, sms, supers)
    except ValueError as e:
        raise SystemExit(f"error: {e}")
    out_p.write_bytes(out)
    print(f"wrote {out_p} — SHA-1 {meta['target_sha1']} (verified)")


if __name__ == "__main__":
    main()
