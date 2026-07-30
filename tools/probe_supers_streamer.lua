-- probe_supers_streamer.lua — identify the sprite-cel streamer: log the PC that
-- writes a sprite-bank value ($D0-$DF) into any DMA A-bus bank register ($43n4),
-- plus the configured source. That PC's routine consumes the per-frame cel table
-- (the animation-script successor of SMS's manifest anim payload).
-- ROM=<Super S> tools/run.sh tools/probe_supers_streamer.lua 60
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "supers_streamer.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local BUS = emu.memType.snesMemory
local t, needLoad, events = -1, true, 0

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  local b = PL.pad()
  if t >= 240 and t <= 241 then b = PL.pad({ x = true }) end
  emu.setInput(b, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

local cb = function(addr, value)
  if t < 235 or t > 260 or events >= 16 then return end
  if value < 0xD0 or value > 0xDF then return end
  local reg = addr & 0xFFFF
  if reg % 0x10 ~= 4 then return end   -- $43n4 only
  events = events + 1
  local base = (addr & 0xFF0000) | (reg - 4)
  local st = emu.getState()
  log(string.format("$%04X=%02X (A-bus bank) src=%02X%02X vram-b=%02X PC=%02X:%04X t=%d",
    reg, value, emu.read(base + 3, BUS), emu.read(base + 2, BUS), emu.read(base + 1, BUS),
    st["cpu.k"], st["cpu.pc"], t))
end
emu.addMemoryCallback(cb, emu.callbackType.write, 0x004300, 0x00437F, emu.cpuType.snes, BUS)
emu.addMemoryCallback(cb, emu.callbackType.write, 0x804300, 0x80437F, emu.cpuType.snes, BUS)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t > 280 then log("DONE events=" .. events); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_supers_streamer loaded")
