#!/bin/bash
# usage: tools/run.sh <script.lua> [timeout]
cd "$(dirname "$0")/.."
exec ./tools/Mesen.app/Contents/MacOS/Mesen --testrunner --timeout=${2:-300} \
  --debug.scriptWindow.allowIoOsAccess=true --debug.scriptWindow.scriptTimeout=300 \
  --snes.port1.type=SnesController --snes.port2.type=SnesController \
  --snes.ramPowerOnState=AllZeros \
  "Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc" "$1"
