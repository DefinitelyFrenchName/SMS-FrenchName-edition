
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/noauto.txt", "w"))
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
  if frames > 1400 and cfg0 == nil then cfg0 = frames end
end, emu.callbackType.exec, 0x808DB8, 0x808DB8, emu.cpuType.snes, emu.memType.snesMemory)
local function shot(n)
  local png = emu.takeScreenshot()
  local f = assert(io.open(ENV.TRACE .. "saturn/" .. n .. ".png", "wb"))
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
  function() log(string.format("config: p1row +04=%02X +06=%02X | p2 +04=%02X +06=%02X",
                 ram(0x1804), ram(0x1806), ram(0x1884), ram(0x1886)))
             shot("noauto_entry"); return true end,
  -- mash RIGHT on the mode row (cursor starts there) many times
  function()
    pulse[0] = (sf % 12 < 3) and {right=true} or {}
    if sf > 150 then return true end
    return false
  end,
  function() log(string.format("after RIGHT x N: p1 +04=%02X +06=%02X | p2 +04=%02X +06=%02X",
                 ram(0x1804), ram(0x1806), ram(0x1884), ram(0x1886)))
             shot("noauto_after"); return true end,
  function() pulse[0] = (sf % 12 < 3) and {left=true} or {}; return sf > 90 end,
  function() log(string.format("after LEFT x N:  p1 +04=%02X +06=%02X", ram(0x1804), ram(0x1806)))
             shot("noauto_left"); return true end,
  -- sanity: move down a row and change a BUTTON option (must still work)
  function() pulse[0] = (sf % 12 < 3) and {down=true} or {}; return sf > 20 end,
  function() pulse[0] = (sf % 12 < 3) and {right=true} or {}; return sf > 60 end,
  function() log(string.format("button row after RIGHT: +04=%02X +06=%02X", ram(0x1804), ram(0x1806)))
             shot("noauto_btnrow"); return true end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 5000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("noauto probe loaded")
