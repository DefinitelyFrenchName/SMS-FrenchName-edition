
-- probe_sms_btnconfig.lua — map the VS-config button-mapping screen: reach it
-- via the VS flow, then cycle options while diffing WRAM $1B00-$1C7F +
-- logging what changes; also find the "Auto" value.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/btnconfig.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local function beat(on) return (frames % 10) < 2 and on or {} end
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)
local snap = {}
for _, a in ipairs({0x7E1C4A, 0x001C4A, 0x7E1C4C, 0x001C4C}) do
  emu.addMemoryCallback(function(addr, value)
    if frames < 1500 then return end
    local ok, st = pcall(emu.getState)
    local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
    local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
    log(string.format("f=%d W %06X <= %02X @ %02X:%04X", frames, addr, value or -1, k, pc))
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
local RANGES = {{0x0000, 0x0100}, {0x1B00, 0x1D00}}
local function snapshot()
  local t = {}
  for _, r in ipairs(RANGES) do
    for a = r[1], r[2] - 1 do t[a] = ram(a) end
  end
  return t
end
local function diff(tag, old)
  local new = snapshot()
  local out = {}
  for a, v in pairs(new) do
    if v ~= old[a] and a ~= 0x1B1C then out[#out+1] = string.format("%04X:%02X->%02X", a, old[a], v) end
  end
  table.sort(out)
  log(tag .. " " .. (#out > 0 and table.concat(out, " ") or "(no change)"))
  return new
end
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() return sf>300 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>120 end,   -- P1 confirm
  function() pulse[1]=beat({a=true}); return ram(0x1B82)==1 or sf>120 end,   -- P2 confirm
  function()
    if sf == 100 or sf == 250 or sf == 400 or sf == 550 or sf == 700 then
      local png = emu.takeScreenshot()
      local f = assert(io.open(ENV.TRACE .. "saturn/btncfg_" .. sf .. ".png", "wb"))
      f:write(png); f:close()
      log(string.format("shot sf=%d 1B10=%02X 1B1C=%02X 8D=%02X 70=%02X", sf, ram(0x1B10), ram(0x1B1C), ram(0x8D), ram(0x70)))
    end
    return sf > 720
  end,
  function()
    snap = snapshot(); log(string.format("AT CONFIG timer1B1C=%02X", ram(0x1B1C)))
    return true
  end,
  function() pulse[0]=beat({select=true}); if sf>14 then snap = diff("p1 SELECT:", snap); return true end return false end,
  function() pulse[0]=beat({right=true}); if sf>14 then snap = diff("p1 RIGHT(mode?):", snap); return true end return false end,
  function()
    local png = emu.takeScreenshot()
    local f = assert(io.open(ENV.TRACE .. "saturn/btncfg_auto.png", "wb"))
    f:write(png); f:close()
    return true
  end,
  function() pulse[0]=beat({right=true}); if sf>14 then snap = diff("p1 RIGHT2:", snap); return true end return false end,
  function() pulse[0]=beat({left=true}); if sf>14 then snap = diff("p1 LEFT:", snap); return true end return false end,
  function() pulse[0]=beat({down=true}); if sf>14 then snap = diff("p1 DOWN(row2):", snap); return true end return false end,
  function() pulse[0]=beat({right=true}); if sf>14 then snap = diff("p1 RIGHT(row2):", snap); return true end return false end,
  function()
    local png = emu.takeScreenshot()
    local f = assert(io.open(ENV.TRACE .. "saturn/btncfg_end.png", "wb"))
    f:write(png); f:close()
    return true
  end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 4500 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("btnconfig loaded")
