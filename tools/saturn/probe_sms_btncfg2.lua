
-- probe_sms_btncfg2.lua — config-screen RE, synced to the screen init
-- ($80:8DB8 zeroes $1C4A): watch ALL writes in $1C40-$1C6F with writer PCs,
-- press SELECT then LEFT/RIGHT at known offsets, screenshot after each.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/btncfg2.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local cfg0 = nil          -- frame the config screen initialized
local function beat(on) return (frames % 10) < 2 and on or {} end
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)
-- init sync: exec at $80:8DB8
emu.addMemoryCallback(function()
  if frames > 1400 and cfg0 == nil then cfg0 = frames; log("CONFIG-INIT f=" .. frames) end
end, emu.callbackType.exec, 0x808DB8, 0x808DB8, emu.cpuType.snes, emu.memType.snesMemory)
-- write watch with PC
emu.addMemoryCallback(function(addr, value)
  if cfg0 == nil then return end
  local ok, st = pcall(emu.getState)
  local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
  local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
  local off = addr % 0x10000
  if value ~= 0 or ram(off) ~= value then end
  log(string.format("f=%d W %04X <= %02X @ %02X:%04X", frames, off, value or -1, k, pc))
end, emu.callbackType.write, 0x7E1C40, 0x7E1C6F, emu.cpuType.snes, emu.memType.snesMemory)
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
  function() return cfg0 ~= nil and frames > cfg0 + 30 end,   -- config live
  function() shot("cfg2_entry"); log("at config, pressing SELECT"); return true end,
  function() pulse[0] = (sf < 3) and {select=true} or {}; return sf > 20 end,
  function() shot("cfg2_afterselect"); return true end,
  function() pulse[0] = (sf < 3) and {right=true} or {}; return sf > 20 end,
  function() shot("cfg2_afterright"); return true end,
  function() pulse[0] = (sf < 3) and {left=true} or {}; return sf > 20 end,
  function() shot("cfg2_afterleft"); return true end,
  function() pulse[0] = (sf < 3) and {down=true} or {}; return sf > 20 end,
  function() pulse[0] = (sf < 3) and {right=true} or {}; return sf > 20 end,
  function() shot("cfg2_row2right"); log("done seq"); return true end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 5000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("btncfg2 loaded")
