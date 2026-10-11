#!/usr/bin/env python3
"""mkapplier.py — generate release/Rev.SS-NN.html, the one-file browser builder for the two-ROM Rev. SS patch.

    python3 tools/saturn/mkapplier.py            # write release/Rev.SS-<REV_SS>.html
    python3 tools/saturn/mkapplier.py --check    # exit 1 if the committed page is stale or unsafe

Inlines tools/saturn/applier/donor_applier.js and release/Rev.SS-NN.donor.bps into
tools/saturn/applier/page_shell.html. Reads no ROM, so --check runs anywhere (health,
CI). Two safety checks on the generated page, the second independent of the first:
  1. the Content-Security-Policy must be present and unweakened — it is what makes
     "your ROMs never leave this page" a property of the browser, not a claim;
  2. a static scan refuses known network primitives anywhere in the page.
"""
import base64
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(REPO / "tools"))
sys.path.insert(0, str(HERE))
from cliguard import reject_unknown_flags
import smspaths
import donorpatch as DP

CSP = ("default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'none'; "
       "connect-src 'none'; form-action 'none'; base-uri 'none'; frame-src 'none'; "
       "object-src 'none'; worker-src 'none'")
NETWORK = re.compile(r"\bfetch\s*\(|XMLHttpRequest|WebSocket|EventSource|sendBeacon|RTCPeerConnection"
                     r"|\bimport\s*\(|<link\b|<iframe\b|<img\b|src\s*=\s*[\"']?https?:")


def render(rev):
    patch = (REPO / "release" / f"Rev.SS-{rev}.donor.bps").read_bytes()
    meta = DP.read_meta(patch)
    js = (HERE / "applier" / "donor_applier.js").read_text()
    page = (HERE / "applier" / "page_shell.html").read_text()
    for key, val in (("REV", rev), ("SMS_SHA1", meta["sms_sha1"]), ("SUPERS_SHA1", meta["supers_sha1"]),
                     ("TARGET_NAME", meta["target_name"]), ("TARGET_SHA1", meta["target_sha1"]),
                     ("APPLIER_JS", js), ("PATCH_B64", base64.b64encode(patch).decode())):
        page = page.replace(f"@@{key}@@", val)
    left = re.findall(r"@@[A-Z0-9_]+@@", page)
    if left:
        raise SystemExit(f"error: unfilled placeholders {sorted(set(left))}")
    return page


def safety(page):
    problems = []
    if f'content="{CSP}"' not in page:
        problems.append("Content-Security-Policy missing or changed")
    for m in NETWORK.finditer(page):
        problems.append(f"network primitive {m.group(0)!r}")
    return problems


def main():
    reject_unknown_flags(sys.argv, {"--check"}, "mkapplier.py")
    rev = smspaths.REV_SS
    out = REPO / "release" / f"Rev.SS-{rev}.html"
    page = render(rev)
    problems = safety(page)
    if problems:
        raise SystemExit("error: unsafe page — " + "; ".join(problems))
    if "--check" in sys.argv:
        if not out.exists() or out.read_text() != page:
            raise SystemExit(f"{out.relative_to(REPO)} is stale — run tools/saturn/mkapplier.py")
        print(f"{out.relative_to(REPO)} in sync, CSP intact, no network primitive")
        return
    out.write_text(page)
    print(f"wrote {out.relative_to(REPO)} ({len(page)} bytes)")


if __name__ == "__main__":
    main()
