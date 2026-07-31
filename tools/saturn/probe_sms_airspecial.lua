
-- probe_sms_airspecial.lua — repro the field-reported j.632K crash: transform
-- P1 to Saturn, jump, feed 6/3/2+K in the air (and also sweep +0x51 request
-- nibbles while airborne); watch acts, projectile slots, INIDISP writes and
-- the PC for a wedge/black-screen signature.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/airspecial.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local phase = "real-input"
local seq = nil
local inidisp = -1

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

for _, base in ipairs({0x002100, 0x802100}) do
  emu.addMemoryCallback(function(addr, value)
    inidisp = value or -1
  end, emu.callbackType.write, base, base, emu.cpuType.snes, emu.memType.snesMemory)
end

local buttons = {}
emu.addEventCallback(function()
  emu.setInput(PL.pad(buttons), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

local function st(field)
  local ok, s = pcall(emu.getState)
  return s and (s["cpu." .. field] or s["snes.cpu." .. field]) or -1
end

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
    wr(0x10A1, 0x30); wr(0x10A2, 0x01)          -- park P2 far
  end
  -- real-input attempt: jump straight up at t=120, then 6,3,2+K
  if t == 120 then buttons = {up = true} end
  if t == 126 then buttons = {} end
  if t == 140 then buttons = {right = true} end
  if t == 144 then buttons = {right = true, down = true} end
  if t == 148 then buttons = {down = true} end
  if t == 152 then buttons = {down = true, x = true} end   -- X=LK per act notes? (Y=LP X=HP B=LK A=HK from tester header: B=LK!)
  if t == 156 then buttons = {} end
  if t >= 120 and t <= 260 and t % 4 == 0 then
    log(string.format("t=%03d act=%02X pose=%02X y=%02X%02X req51=%02X proj[%02X %02X %02X] inidisp=%02X pc=%02X:%04X",
      t, ram(0x1001), ram(0x1005), ram(0x102B), ram(0x102A), ram(0x1051),
      ram(0x1100), ram(0x1180), ram(0x1200), inidisp, st("k"), st("pc")))
  end
  -- second attempt with B=LK at t=300
  if t == 300 then buttons = {up = true} end
  if t == 306 then buttons = {} end
  if t == 320 then buttons = {right = true} end
  if t == 324 then buttons = {right = true, down = true} end
  if t == 328 then buttons = {down = true} end
  if t == 332 then buttons = {down = true, b = true} end
  if t == 336 then buttons = {} end
  if t >= 300 and t <= 440 and t % 4 == 0 then
    log(string.format("t=%03d act=%02X pose=%02X req51=%02X proj[%02X %02X %02X] inidisp=%02X pc=%02X:%04X",
      t, ram(0x1001), ram(0x1005), ram(0x1051),
      ram(0x1100), ram(0x1180), ram(0x1200), inidisp, st("k"), st("pc")))
  end
  -- airborne request-nibble sweep: jump then poke +0x51
  if t == 480 then buttons = {up = true} end
  if t == 486 then buttons = {} end
  if t == 495 then wr(0x1051, 0x0C) end          -- try nibble 0x0C (air?)
  if t >= 495 and t <= 560 and t % 3 == 0 then
    log(string.format("t=%03d SWEEPC act=%02X pose=%02X proj[%02X %02X %02X] inidisp=%02X pc=%02X:%04X",
      t, ram(0x1001), ram(0x1005),
      ram(0x1100), ram(0x1180), ram(0x1200), inidisp, st("k"), st("pc")))
  end
  if t > 560 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)
print("airspecial probe loaded")
