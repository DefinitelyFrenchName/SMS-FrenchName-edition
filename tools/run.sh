#!/bin/bash
# usage: tools/run.sh <script.lua> [timeout]
# Works from any cwd; scripts resolve repo paths via tools/sms_env.lua
# (SMS_ROOT exported here is one of its fallbacks).
cd "$(dirname "$0")/.."
export SMS_ROOT="$(pwd)"
exec ./tools/Mesen.app/Contents/MacOS/Mesen --testrunner --timeout=${2:-300} \
  --debug.scriptWindow.allowIoOsAccess=true --debug.scriptWindow.scriptTimeout=300 \
  --snes.port1.type=SnesController --snes.port2.type=SnesController \
  --snes.ramPowerOnState=AllZeros \
  "${ROM:-roms/Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc}" "$1"
