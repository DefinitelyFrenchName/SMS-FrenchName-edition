-- probe_p89_padleak.lua — issue #89: trainer.lua's dummy must force unnamed buttons FALSE.
--
-- Simulates a held physical P2 pad (down+Y) with an inputPolled callback registered
-- BEFORE trainer.lua's, so it runs first each poll — trainer's sparse setInput then
-- decides whether the press leaks through. Dummy mode 1 ("Off") passes an empty
-- table, so on the unfixed script P2 crouch-jabs all run long; fixed, P2 stays idle.
--   PASS: P2 never enters an attack act (>= 0x2B) while mode 1 drives it.
--   FAIL: the held button leaked into the dummy.
-- Run: ROM=build/SailorMoonS_FrenchName_v0.7_all5.sfc tools/run.sh tools/probe_p89_padleak.lua 60
-- Out: traces/probe_p89_padleak.txt

local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local WRAM = emu.memType.snesWorkRam
local STATE = ENV.ROOT .. "traces/uranus_vs_jupiter_v07.mss"
local OUT = ENV.ROOT .. "traces/probe_p89_padleak.txt"

local HELD = { a=false,b=false,x=false,y=true,l=false,r=false,
               up=false,down=true,left=false,right=false,start=false,select=false }
emu.addEventCallback(function()
  emu.setInput(HELD, 0, 1)   -- the "physical" P2 pad; trainer's callback runs after this
end, emu.eventType.inputPolled)

dofile(ENV.TOOLS .. "trainer.lua")   -- MODE = 1 (Off) is its default

local t, leakAct = 0, nil
local __loaded = false
emu.addMemoryCallback(function()
  if not __loaded then
    local f = io.open(STATE, "rb")
    if not f then print("probe_p89: missing savestate " .. STATE); emu.stop(1); return end
    emu.loadSavestate(f:read("*a")); f:close(); __loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if not __loaded then return end
  t = t + 1
  local a2 = emu.read(0x1081, WRAM)
  if t > 10 and a2 >= 0x2B and not leakAct then leakAct = { t = t, act = a2 } end
  if t == 200 then
    local log = io.open(OUT, "w")
    log:write(leakAct
      and string.format("FAIL (leak): P2 act=%02X at t=%d with dummy mode 1\n", leakAct.act, leakAct.t)
      or "PASS: held physical P2 buttons did not reach the mode-1 dummy\n")
    log:close()
    emu.stop(leakAct and 1 or 0)
  end
end, emu.eventType.endFrame)

print("probe_p89_padleak loaded")
