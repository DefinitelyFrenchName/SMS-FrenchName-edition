#!/bin/bash
# usage: tools/run.sh <script.lua> [timeout]
# Works from any cwd; scripts resolve repo paths via tools/sms_env.lua
# (SMS_ROOT exported here is one of its fallbacks).
# Default ROM (when $ROM is unset) resolves like tools/smspaths.py:
#   $SMS_ROM_DIR -> roms/ -> ../roms/   (ROMs are never tracked in git)
# resolve caller-relative paths BEFORE the cd (issue #52: `cd tools && ./run.sh x.lua`
# used to resolve the script against the repo root instead of the caller's cwd)
abspath() { python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"; }
SCRIPT="$(abspath "$1")"
[ -n "${ROM:-}" ] && ROM="$(abspath "$ROM")"
cd "$(dirname "$0")/.."
export SMS_ROOT="$(pwd)"
CLEAN_NAME="Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc"
if [ -z "$ROM" ]; then
  for d in "${SMS_ROM_DIR:-}" roms ../roms; do
    [ -n "$d" ] && [ -f "$d/$CLEAN_NAME" ] && ROM="$d/$CLEAN_NAME" && break
  done
  if [ -z "$ROM" ]; then
    echo "run.sh: clean ROM not found (looked in \$SMS_ROM_DIR, roms/, ../roms/)" >&2
    echo "        set SMS_ROM_DIR=/path/to/rom/dir or pass ROM=<rom>" >&2
    exit 1
  fi
fi
exec ./tools/Mesen.app/Contents/MacOS/Mesen --testrunner --timeout=${2:-300} \
  --debug.scriptWindow.allowIoOsAccess=true --debug.scriptWindow.scriptTimeout=300 \
  --snes.port1.type=SnesController --snes.port2.type=SnesController \
  --snes.ramPowerOnState=AllZeros \
  "$ROM" "$SCRIPT"
