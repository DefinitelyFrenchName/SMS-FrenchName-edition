-- probe_supers_animload2.lua — anim-payload hunt, take 2. The $6A00 fill is invisible
-- to WRAM write callbacks (port/DMA path), so watch the mechanisms instead:
--   * CPU writes to WMADD $2181-83 (WRAM port target) — log PC + target
--   * CPU writes to $420B (DMA trigger) — dump every enabled channel's config; flag
--     channels targeting $2180 (WMDATA = WRAM fill) and log their A-bus SOURCE.
-- Armed through the whole Saturn load. ROM=<Super S> tools/run.sh ... 120
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "supers_animload2.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local BUS = emu.memType.snesMemory
local wmaddEvents, dmaEvents = 0, 0

emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

-- WMADD low writes (WRAM port target set)
emu.addMemoryCallback(function(addr, value)
  if wmaddEvents >= 30 or step < 5 then return end
  wmaddEvents = wmaddEvents + 1
  local st = emu.getState()
  log(string.format("WMADD $%04X=%02X PC=%02X:%04X f=%d step=%d", addr, value, st["cpu.k"], st["cpu.pc"], frames, step))
end, emu.callbackType.write, 0x2181, 0x2183, emu.cpuType.snes, BUS)

-- DMA trigger: dump channels targeting WMDATA ($2180)
emu.addMemoryCallback(function(addr, value)
  if dmaEvents >= 60 or step < 5 then return end
  for ch = 0, 7 do
    if value & (1 << ch) ~= 0 then
      local base = 0x4300 + ch * 0x10
      local bbus = emu.read(base + 1, BUS)
      if bbus == 0x80 then   -- $2180 WMDATA
        dmaEvents = dmaEvents + 1
        local st = emu.getState()
        local alo = emu.read(base + 2, BUS) | (emu.read(base + 3, BUS) << 8)
        local abk = emu.read(base + 4, BUS)
        local sz = emu.read(base + 5, BUS) | (emu.read(base + 6, BUS) << 8)
        log(string.format("DMA->WRAM ch%d src=%02X:%04X size=%04X  WMADD=%02X%02X%02X  PC=%02X:%04X f=%d step=%d",
          ch, abk, alo, sz, emu.read(0x2183, BUS) & 1, emu.read(0x2182, BUS), emu.read(0x2181, BUS),
          st["cpu.k"], st["cpu.pc"], frames, step))
      end
    end
  end
end, emu.callbackType.write, 0x420B, 0x420B, emu.cpuType.snes, BUS)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() return sf>240 end,
  function() wr(0x1B40, 10); wr(0x1B80, 6); return sf>20 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>90 end,
  function() pulse[0]={}; return sf>30 end,
  function() pulse[1]=beat({a=true}); return sf>60 end,
  function() return sf>240 end,
  function() pulse[0]=beat({start=true}); pulse[1]=beat({start=true})
             return (ram(0x1000)==10 and ram(0x1080)~=0) or sf>600 end,
  function() return sf>60 end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log(string.format("DONE wmadd=%d dma=%d", wmaddEvents, dmaEvents)); emu.stop(0) end
  if frames > 4500 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_supers_animload2 loaded")
