-- probe_supers_guardpose.lua — find the CALLER that puts the defender into pre-block
-- pose (act 0x0C) in Super S. On every $1081 <= 0x0C write (setter is common code
-- $C1:022E), dump SP + raw stack bytes so the JSR/JSL return chain identifies the
-- guard-proximity decision site. One case is enough (far 5HK @ 40px).
-- ROM=<Super S> tools/run.sh tools/saturn/probe_supers_guardpose.lua 200 -> traces/saturn/supers_guardpose.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/supers_guardpose.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local t, needLoad, done = -1, true, false
local PRESS = 240

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn/saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr, value)
  if t >= PRESS - 30 and value == 0x0C and not done then
    local ok, st = pcall(emu.getState)
    local sp = st and (st["cpu.sp"] or st["snes.cpu.sp"]) or 0
    local row = {}
    for a = sp + 1, sp + 24 do row[#row + 1] = string.format("%02X", ram(a)) end
    log(string.format("t=%03d 1081<=0C sp=%04X stack: %s", t, sp, table.concat(row, " ")))
  end
end, emu.callbackType.write, 0x1081, 0x1081, emu.cpuType.snes, emu.memType.snesWorkRam)

emu.addEventCallback(function()
  local p1 = PL.pad()
  if t >= PRESS and t <= PRESS + 1 then p1 = PL.pad({ a = true }) end
  local p2 = (t >= 200) and PL.pad({ right = true }) or PL.pad()
  emu.setInput(p1, 0, 0); emu.setInput(p2, 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == PRESS - 12 then
    local px = ram(0x1021) + 256 * ram(0x1022)
    local x = px + 40
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
  end
  if t == PRESS + 20 then log("DONE"); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_supers_guardpose loaded")
