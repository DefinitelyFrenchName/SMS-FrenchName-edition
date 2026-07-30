-- probe_supers_projgfx.lua — how does SATURN'S FIREBALL get its graphics in
-- Super S? Fires qcf+LP on the Saturn fixture; logs the projectile slot $1100
-- (id/act/pose/+0x0A tile base/+0x0C..0x15 cel fields), writer PC on $110C, and
-- VRAM-bound DMA activity during the fireball's life ($43x2-4 A-bus sources when
-- B-bus=$2118), to identify static-vs-streamed and the source data.
-- ROM=<Super S> tools/run.sh tools/saturn/probe_supers_projgfx.lua 200
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/supers_projgfx.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram

local t, needLoad = -1, true
local wlog = 0

local function pcstr()
  local ok, st = pcall(emu.getState)
  local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"])
  local k = st and (st["cpu.k"] or st["snes.cpu.k"])
  return pc and string.format("%02X:%04X", k or 0, pc) or "?"
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn/saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)

for _, base in ipairs({ 0x00110C, 0x7E110C }) do
  emu.addMemoryCallback(function(addr, value)
    if t >= 0 and wlog < 10 then
      wlog = wlog + 1
      log(string.format("t=%03d W %06X <= %02X @ %s", t, base, value or -1, pcstr()))
    end
  end, emu.callbackType.write, base, base, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  local p1 = PL.pad()
  local q = 240
  if t == q or t == q + 1 then p1 = PL.pad({ down = true })
  elseif t == q + 2 or t == q + 3 then p1 = PL.pad({ down = true, right = true })
  elseif t == q + 4 or t == q + 5 then p1 = PL.pad({ right = true })
  elseif t == q + 6 or t == q + 7 then p1 = PL.pad({ right = true, y = true }) end
  emu.setInput(p1, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t >= 245 and t <= 320 and t % 6 == 0 then
    log(string.format("t=%03d proj id=%02X act=%02X pose05=%02X f18=%02X cel=%02X%02X%02X sz=%02X%02X cel2=%02X%02X%02X sz2=%02X%02X tile0A=%02X%02X x=%d",
      t, ram(0x1100), ram(0x1101), ram(0x1105), ram(0x1118),
      ram(0x110E), ram(0x110D), ram(0x110C), ram(0x1113), ram(0x1112),
      ram(0x1111), ram(0x1110), ram(0x110F), ram(0x1115), ram(0x1114),
      ram(0x110B), ram(0x110A), ram(0x1121) + 256 * ram(0x1122)))
  end
  if t == 280 then
    for s = 0, 50 do
      local o = 0x0200 + 4 * s
      local x, y, tile, attr = ram(o), ram(o + 1), ram(o + 2), ram(o + 3)
      if y < 0xE0 then
        log(string.format("  oam%02d: x=%02X y=%02X tile=%02X attr=%02X", s, x, y, tile, attr))
      end
    end
  end
  if t == 322 then log("DONE"); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_supers_projgfx loaded")
