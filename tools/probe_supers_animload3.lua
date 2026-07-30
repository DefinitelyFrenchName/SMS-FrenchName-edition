-- probe_supers_animload3.lua — anim/sprite hunt, take 3 (method inverted):
--   * PRG-read watch on the shared manifest field target $E0:F328 (file 0x20F328) and
--     on Saturn's manifest record (file 0x20AC6A..+15) — identifies the consumers.
--   * DMA->VRAM ($2118/2119 B-bus) logger during the load — A-bus sources = her
--     sprite/CHR data locations (the CHR census for the port budget).
-- ROM=<Super S> tools/run.sh tools/probe_supers_animload3.lua 120
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "supers_animload3.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local BUS = emu.memType.snesMemory
local f328, manif, dmav = 0, 0, 0

emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

emu.addMemoryCallback(function(addr, value)
  if f328 >= 12 or step < 5 then return end
  f328 = f328 + 1
  local st = emu.getState()
  log(string.format("READ F328+%X=%02X PC=%02X:%04X X=%04X Y=%04X f=%d s=%d",
    addr - 0x20F328, value, st["cpu.k"], st["cpu.pc"], st["cpu.x"], st["cpu.y"], frames, step))
end, emu.callbackType.read, 0x20F328, 0x20F33F, emu.cpuType.snes, emu.memType.snesPrgRom)

emu.addMemoryCallback(function(addr, value)
  if manif >= 12 or step < 5 then return end
  manif = manif + 1
  local st = emu.getState()
  log(string.format("READ SATMANIF+%X=%02X PC=%02X:%04X f=%d s=%d",
    addr - 0x20AC6A, value, st["cpu.k"], st["cpu.pc"], frames, step))
end, emu.callbackType.read, 0x20AC6A, 0x20AC79, emu.cpuType.snes, emu.memType.snesPrgRom)

emu.addMemoryCallback(function(addr, value)
  if dmav >= 40 or step < 9 then return end
  for ch = 0, 7 do
    if value & (1 << ch) ~= 0 then
      local base = 0x4300 + ch * 0x10
      local bbus = emu.read(base + 1, BUS)
      if bbus == 0x18 or bbus == 0x19 then
        dmav = dmav + 1
        local alo = emu.read(base + 2, BUS) | (emu.read(base + 3, BUS) << 8)
        local abk = emu.read(base + 4, BUS)
        local sz = emu.read(base + 5, BUS) | (emu.read(base + 6, BUS) << 8)
        local vaddr = emu.read(0x2116, BUS) | (emu.read(0x2117, BUS) << 8)
        log(string.format("DMA->VRAM ch%d src=%02X:%04X size=%04X vram=%04X f=%d s=%d",
          ch, abk, alo, sz, vaddr, frames, step))
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
  if not STEPS[step] then log(string.format("DONE f328=%d manif=%d dmav=%d", f328, manif, dmav)); emu.stop(0) end
  if frames > 4500 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_supers_animload3 loaded")
