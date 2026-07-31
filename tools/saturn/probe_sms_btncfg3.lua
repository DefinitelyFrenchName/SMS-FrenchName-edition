
-- probe_sms_btncfg3.lua — config screen, fully live: arrow presses with
-- full-WRAM snapshot diffs + screenshots.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/btncfg3.txt", "w"))
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
  function() diff("Y:"); shot("cfg3_y"); return true end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 5200 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("btncfg3 loaded")
