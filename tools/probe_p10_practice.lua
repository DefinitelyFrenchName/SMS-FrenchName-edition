-- probe_p10_practice.lua — does patch 10's compute stub run in practice mode?
-- Run on a bundle with p10+p11 (compute stub at $EA:0000, e.g. v0.21):
--   ROM=<bundle> tools/run.sh tools/probe_p10_practice.lua 120
-- Loads traces/training_p11.mss (practice match), counts stub executions vs frames.
-- Out: traces/probe_p10_practice.txt

local WRAM = emu.memType.snesWorkRam
local ROOT = "/Users/koneko/Developer/SailorMoonS/"
local STATE = ROOT .. "traces/training_p11.mss"
local OUT = ROOT .. "traces/probe_p10_practice.txt"

local t, execs, MAXT = 0, 0, 300
local __loaded = false

emu.addMemoryCallback(function()
  if not __loaded then
    local f = io.open(STATE, "rb"); local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss); __loaded = true
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function()
  if __loaded then execs = execs + 1 end
end, emu.callbackType.exec, 0xEA0000, 0xEA0000, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if not __loaded then return end
  t = t + 1
  if t >= MAXT then
    local log = io.open(OUT, "w")
    log:write(string.format("mode $008D=%d frames=%d p10-compute execs=%d -> %s\n",
      emu.read(0x8D, WRAM), t, execs,
      execs == 0 and "producer NEVER runs in practice (p10 counter impossible here)"
      or "producer RUNS in practice"))
    log:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)

print("probe_p10_practice.lua loaded")
