-- probe_supers_movereq.lua — find the consumer of the move-request register +0x51
-- (written by the button handler $C1:161F and the command recognizers $C1:1339).
-- Logs reads of $1051 with reader PC while Saturn presses 5LP then attempts a
-- fireball motion (236+P), plus resulting act changes.
-- ROM=<Super S> tools/run.sh tools/saturn/probe_supers_movereq.lua 200 -> traces/saturn/supers_movereq.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/supers_movereq.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram

local t, needLoad = -1, true
local PRESS = 240
local seen = {}

local function pcstr()
  local ok, st = pcall(emu.getState)
  if not ok then return "?" end
  local pc = st["cpu.pc"] or st["snes.cpu.pc"]
  local k  = st["cpu.k"]  or st["snes.cpu.k"]
  if pc == nil then return "?" end
  return string.format("%02X:%04X", k or 0, pc)
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn/saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr, value)
  if t >= PRESS - 2 and t <= PRESS + 40 then
    local pc = pcstr()
    if not seen[pc] then
      seen[pc] = true
      log(string.format("t=%03d READ 1051 (=%02X) @ %s p1act=%02X", t, ram(0x1051), pc, ram(0x1001)))
    end
  end
end, emu.callbackType.read, 0x1051, 0x1051, emu.cpuType.snes, emu.memType.snesWorkRam)

-- bus-mirror watches (direct-page indexed writes land at $00:1051, not $7E:1051)
for _, base in ipairs({ 0x001051, 0x7E1051 }) do
  emu.addMemoryCallback(function(addr, value)
    if t >= PRESS - 2 and t <= PRESS + 140 and (value or 0) ~= 0 then
      log(string.format("t=%03d BUSWRITE %06X <= %02X @ %s p1act=%02X", t, base, value or -1, pcstr(), ram(0x1001)))
    end
  end, emu.callbackType.write, base, base, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addMemoryCallback(function(addr, value)
  if t >= PRESS - 2 and t <= PRESS + 60 then
    log(string.format("t=%03d WRITE 1051 <= %02X @ %s p1act=%02X", t, value or -1, pcstr(), ram(0x1001)))
  end
end, emu.callbackType.write, 0x1051, 0x1051, emu.cpuType.snes, emu.memType.snesWorkRam)

emu.addEventCallback(function()
  local p1 = PL.pad()
  -- 5LP at PRESS, then a 236+LP (qcf) attempt at PRESS+120
  if t >= PRESS and t <= PRESS + 1 then p1 = PL.pad({ y = true }) end
  local q = PRESS + 120
  if t == q or t == q + 1 then p1 = PL.pad({ down = true })
  elseif t == q + 2 or t == q + 3 then p1 = PL.pad({ down = true, right = true })
  elseif t == q + 4 or t == q + 5 then p1 = PL.pad({ right = true })
  elseif t == q + 6 or t == q + 7 then p1 = PL.pad({ right = true, y = true }) end
  emu.setInput(p1, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

local lastact = -1
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  local a = ram(0x1001)
  if a ~= lastact and t >= PRESS - 2 then
    log(string.format("t=%03d p1 ACT -> %02X (req51=%02X)", t, a, ram(0x1051)))
    lastact = a
  end
  if t == PRESS + 180 then log("DONE"); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_supers_movereq loaded")
