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
[ -n "${MESEN:-}" ] && MESEN="$(abspath "$MESEN")"
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
# Mesen binary: $MESEN overrides (any platform); default is the vendored macOS
# bundle, with ./tools/Mesen as the conventional drop-in name elsewhere (#52).
if [ -z "${MESEN:-}" ]; then
  case "$(uname -s)" in
    Darwin) MESEN=./tools/Mesen.app/Contents/MacOS/Mesen ;;
    *)      MESEN=./tools/Mesen ;;
  esac
fi
[ -x "$MESEN" ] || { echo "run.sh: Mesen not found or not executable at $MESEN" >&2
                     echo "        set MESEN=/path/to/mesen (see docs/toolchain.md)" >&2; exit 1; }
# NB the old --debug.scriptWindow.scriptTimeout=300 flag is gone: measured 2026-08-06
# (issue #52), it has NO effect under --testrunner — every Lua entry (script load and
# each callback) is capped at a hard 1 second whatever value is passed, so the flag
# was dead cargo and never conflicted with --timeout (which bounds the whole run).
exec "$MESEN" --testrunner --timeout=${2:-300} \
  --debug.scriptWindow.allowIoOsAccess=true \
  --snes.port1.type=SnesController --snes.port2.type=SnesController \
  --snes.ramPowerOnState=AllZeros \
  "$ROM" "$SCRIPT"
