
-- probe_sms_btncfg6.lua — config screen: btncfg5 retry — watch $1846
-- reads/writes through the snesWorkRam address space (offset 0x1846) instead
-- of bus addresses; keeps the arrow-press WRAM diffs + screenshots and the
-- $1840-4F/$18C0-CF write watches.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/btncfg6.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local cfg0 = nil
local function beat(on) return (frames % 10) < 2 and on or {} end
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  if frames > 1400 and cfg0 == nil then cfg0 = frames; log("CONFIG-INIT f=" .. frames) end
end, emu.callbackType.exec, 0x808DB8, 0x808DB8, emu.cpuType.snes, emu.memType.snesMemory)
local snap = nil
emu.addMemoryCallback(function(addr, value)
  if cfg0 == nil then return end
  local ok, st = pcall(emu.getState)
  local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
  local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
  log(string.format("f=%d W %04X <= %02X @ %02X:%04X", frames, addr % 0x10000, value or -1, k, pc))
end, emu.callbackType.write, 0x7E1840, 0x7E184F, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function(addr, value)
  if cfg0 == nil then return end
  local ok, st = pcall(emu.getState)
  local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
  local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
  log(string.format("f=%d Wdp %04X <= %02X @ %02X:%04X", frames, addr % 0x10000, value or -1, k, pc))
end, emu.callbackType.write, 0x001840, 0x00184F, emu.cpuType.snes, emu.memType.snesMemory)
local rlog = 0
emu.addMemoryCallback(function(addr, value)
  if cfg0 == nil or rlog > 40 then return end
  rlog = rlog + 1
  local ok, st = pcall(emu.getState)
  local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
  local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
  log(string.format("f=%d Rw %06X = %02X @ %02X:%04X", frames, addr, value or -1, k, pc))
end, emu.callbackType.read, 0x1846, 0x1846, emu.cpuType.snes, emu.memType.snesWorkRam)
emu.addMemoryCallback(function(addr, value)
  if cfg0 == nil then return end
  local ok, st = pcall(emu.getState)
  local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
  local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
  log(string.format("f=%d Ww %06X <= %02X @ %02X:%04X", frames, addr, value or -1, k, pc))
end, emu.callbackType.write, 0x1846, 0x1846, emu.cpuType.snes, emu.memType.snesWorkRam)
emu.addMemoryCallback(function(addr, value)
  if cfg0 == nil then return end
  local ok, st = pcall(emu.getState)
  local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
  local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
  log(string.format("f=%d Wp2 %04X <= %02X @ %02X:%04X", frames, addr % 0x10000, value or -1, k, pc))
end, emu.callbackType.write, 0x0018C0, 0x0018CF, emu.cpuType.snes, emu.memType.snesMemory)
local function snapshot()
  local t = {}
  for a = 0x0100, 0x1FFF do t[a] = ram(a) end
  return t
end
local function diff(tag)
  local new = snapshot()
  local out = {}
  for a = 0x0100, 0x1FFF do
    if new[a] ~= snap[a] then
      -- skip OAM shadow + HUD staging noise
      if not (a >= 0x0200 and a < 0x0B00) then
        out[#out+1] = string.format("%04X:%02X->%02X", a, snap[a], new[a])
      end
    end
  end
  log(tag .. " " .. (#out > 0 and table.concat(out, " ") or "(no change)"))
  snap = new
end
local function shot(name)
  local png = emu.takeScreenshot()
  local f = assert(io.open(ENV.TRACE .. "saturn/" .. name .. ".png", "wb"))
  f:write(png); f:close()
end
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() return sf>300 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>120 end,
  function() pulse[1]=beat({a=true}); return ram(0x1B82)==1 or sf>120 end,
  function() return cfg0 ~= nil and frames > cfg0 + 150 end,
  function() shot("cfg3_live"); snap = snapshot(); return true end,
  function() pulse[0] = (sf < 3) and {right=true} or {}; return sf > 18 end,
  function() diff("RIGHT:"); shot("cfg3_right"); return true end,
  function() pulse[0] = (sf < 3) and {left=true} or {}; return sf > 18 end,
  function() diff("LEFT:"); shot("cfg3_left"); return true end,
  function() pulse[0] = (sf < 3) and {down=true} or {}; return sf > 18 end,
  function() diff("DOWN:"); return true end,
  function() pulse[0] = (sf < 3) and {up=true} or {}; return sf > 18 end,
  function() diff("UP:"); shot("cfg3_up"); return true end,
  function() pulse[0] = (sf < 3) and {y=true} or {}; return sf > 18 end,
  function() diff("Y:"); return true end,
  function() pulse[1] = (sf < 3) and {right=true} or {}; return sf > 18 end,
  function() diff("P2-RIGHT:"); shot("cfg3_p2right"); return true end,
  function() pulse[1] = (sf < 3) and {left=true} or {}; return sf > 18 end,
  function() diff("P2-LEFT:"); return true end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 5200 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("btncfg3 loaded")
