-- probe_supers_secondspecial.lua — ground truth for Saturn's second special (HP):
-- poke +0x51=9 on the Super S fixture, log P1 act + projectile slot life ($1100:
-- id/act/pose/x) to compare against the SMS port's behavior.
-- ROM=<Super S> tools/run.sh tools/saturn/probe_supers_secondspecial.lua 200
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/supers_second.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn/saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 230 then
    local px = ram(0x1021) + 256 * ram(0x1022)
    local x = px + 90
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
  end
  if t == 240 then wr(0x1051, 9) end
  if t > 240 and t <= 330 then
    log(string.format("t=%03d p1 act=%02X | s1100 id=%02X act=%02X pose=%02X x=%d y=%d",
      t, ram(0x1001), ram(0x1100), ram(0x1101), ram(0x1105),
      ram(0x1121) + 256 * ram(0x1122), ram(0x1125) + 256 * ram(0x1126)))
  end
  if t == 425 then log("DONE"); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_supers_secondspecial loaded")
