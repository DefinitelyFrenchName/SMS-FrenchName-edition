#!/bin/bash
# test_donorpatch.sh — the two-ROM Rev. SS patch: Python applier, browser page and node agree, and refuse what they must.
#
# Needs both clean ROMs (smspaths); SKIPs loudly without them. Node and Chrome legs
# SKIP if the tool is absent. Legs:
#   1. tools/saturn/apply_donorpatch.py rebuilds the target SHA-1 from the two ROMs
#      (given in the "wrong" order, one with a copier header) and equals build/'s ROM
#      if that exists;
#   2. the JS EXTRACTED FROM THE SHIPPED PAGE, run under node, gives the same bytes;
#   3. the shipped page, opened from file:// in headless Chrome with its CSP intact and
#      driven through its own file input and button, reports Done with the target SHA-1;
#   controls (must fail): a ROM with one flipped byte, and a patch with one flipped
#   byte, are refused by Python and by the JS; in Chrome, the flipped ROM is refused.
set -uo pipefail
cd "$(dirname "$0")/../.."
REV="$(python3 -c 'import sys;sys.path.insert(0,"tools");import smspaths;print(smspaths.REV_SS)')"
PATCH="release/Rev.SS-$REV.donor.bps"; PAGE="release/Rev.SS-$REV.html"
SMS="$(python3 -c 'import sys;sys.path.insert(0,"tools");import smspaths as p;print(p.clean_rom())')"
SUP="$(python3 -c 'import sys;sys.path.insert(0,"tools");import smspaths as p;print(p.supers_rom())')"
[ -f "$SMS" ] && [ -f "$SUP" ] || { echo "SKIP: test_donorpatch needs both clean ROMs"; exit 0; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fails=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }
WANT="$(python3 -c "import sys;sys.path.insert(0,'tools/saturn');import donorpatch as D;print(D.read_meta(open('$PATCH','rb').read())['target_sha1'])")"

# inputs: the player's order is not ours, and a header is allowed
cp "$SUP" "$W/a.sfc"
{ head -c 512 /dev/zero; cat "$SMS"; } > "$W/b.smc"
python3 - "$SMS" "$W/bad.sfc" <<'PY'
import sys; d = bytearray(open(sys.argv[1], "rb").read()); d[0x1234] ^= 1; open(sys.argv[2], "wb").write(d)
PY
python3 - "$PATCH" "$W/badpatch.bps" <<'PY'
import sys; d = bytearray(open(sys.argv[1], "rb").read()); d[len(d) // 2] ^= 1; open(sys.argv[2], "wb").write(d)
PY

# 1. Python, the tool of record
if python3 tools/saturn/apply_donorpatch.py "$PATCH" "$W/a.sfc" "$W/b.smc" "$W/py.sfc" >/dev/null \
   && [ "$(shasum "$W/py.sfc" | cut -d' ' -f1)" = "$WANT" ]; then ok "python: target ${WANT:0:8}…"; else bad "python did not rebuild the target"; fi
BUILT="build/SailorMoonS_Rev_SS-$REV.sfc"
if [ -f "$BUILT" ]; then cmp -s "$BUILT" "$W/py.sfc" && ok "python == $BUILT" || bad "python output differs from $BUILT"; fi
python3 tools/saturn/apply_donorpatch.py "$PATCH" "$W/a.sfc" "$W/bad.sfc" "$W/x.sfc" >/dev/null 2>&1 && bad "control: python accepted a damaged ROM" || ok "control: python refuses a damaged ROM"
python3 tools/saturn/apply_donorpatch.py "$W/badpatch.bps" "$W/a.sfc" "$W/b.smc" "$W/x.sfc" >/dev/null 2>&1 && bad "control: python accepted a damaged patch" || ok "control: python refuses a damaged patch"

# 2. node, running the code the page actually carries
if command -v node >/dev/null; then
  python3 - "$PAGE" "$W/page.js" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(re.search(r"<script>\n(.*?)\n</script>", s, re.S).group(1))
PY
  run_js() { node -e '
const A=require(process.argv[1]); const fs=require("fs");
const rd=(f)=>new Uint8Array(fs.readFileSync(f));
A.apply(rd(process.argv[2]),[{name:"a",bytes:rd(process.argv[3])},{name:"b",bytes:rd(process.argv[4])}])
 .then(r=>fs.writeFileSync(process.argv[5],r.bytes)).catch(e=>{console.error(e.message);process.exit(1)});' "$W/page.js" "$@"; }
  if run_js "$PATCH" "$W/a.sfc" "$W/b.smc" "$W/js.sfc" && cmp -s "$W/js.sfc" "$W/py.sfc"; then ok "node (the page's JS) == python, byte for byte"; else bad "node output differs from python"; fi
  run_js "$PATCH" "$W/a.sfc" "$W/bad.sfc" "$W/x.sfc" 2>/dev/null && bad "control: JS accepted a damaged ROM" || ok "control: JS refuses a damaged ROM"
  run_js "$W/badpatch.bps" "$W/a.sfc" "$W/b.smc" "$W/x.sfc" 2>/dev/null && bad "control: JS accepted a damaged patch" || ok "control: JS refuses a damaged patch"
else
  echo "  SKIP  node not installed"
fi

# 3. the shipped page in a real engine, from file://
CHROME="${CHROME_BIN:-}"
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" google-chrome chromium chromium-browser; do
  [ -n "$CHROME" ] && break
  { [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; } && CHROME="$c"
done
if [ -n "$CHROME" ]; then
  cp "$PAGE" "$W/page.html"; cp tools/saturn/applier/test_driver.html "$W/driver.html"
  cmp -s "$PAGE" "$W/page.html" || bad "the page under test is not the shipped page"
  drive_once() {
    "$CHROME" --headless --disable-gpu --no-sandbox --allow-file-access-from-files \
      --virtual-time-budget=600000 --dump-dom \
      "file://$W/driver.html?page=page.html&a=$1&b=$2" 2>/dev/null \
    | python3 -c 'import html,re,sys;m=re.search(r"<pre id=\"verdict\">(.*?)</pre>",sys.stdin.read(),re.S);print(html.unescape(m.group(1)) if m else "")'
  }
  drive() {   # drive <rom a> <rom b> -> verdict text. An INCOMPLETE run (no DONE=1, or no
              # status at all) is retried once; a run that produced a verdict never is.
    local v; v="$(drive_once "$1" "$2")"
    if ! grep -q '^DONE=1$' <<<"$v" || grep -q '^STATUS=$' <<<"$v"; then
      echo "  note  incomplete browser run — retrying once" >&2
      v="$(drive_once "$1" "$2")"
    fi
    printf '%s\n' "$v"
  }
  V="$(drive a.sfc b.smc)"
  if grep -q "^STATUS=Done. SHA-1 $WANT, verified." <<<"$V" && grep -q "^DOWNLOAD=SailorMoonS_Rev_SS-$REV.sfc blob:" <<<"$V"; then
    ok "chrome: the shipped page builds ${WANT:0:8}… and offers the download"
  else bad "chrome: page did not build — $(tr '\n' ' ' <<<"$V")"; fi
  V="$(drive a.sfc bad.sfc)"
  grep -q "^STATUS=Not built: bad.sfc: SHA-1" <<<"$V" && ok "control: chrome page refuses a damaged ROM, by name" || bad "control: chrome page did not refuse the damaged ROM — $(tr '\n' ' ' <<<"$V")"
else
  echo "  SKIP  no Chrome/Chromium (set CHROME_BIN)"
fi

[ "$fails" = 0 ] && echo "test_donorpatch: PASS" || { echo "test_donorpatch: FAIL ($fails)"; exit 1; }
