-- probe_sms_sndcheck.lua — verify the sfx translator: fire specials, watch $78
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/sndcheck.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
for _, base in ipairs({ 0x000078, 0x7E0078 }) do
  emu.addMemoryCallback(function(addr, value)
    if t >= 0 and (value or 0) ~= 0 then
      log(string.format("t=%03d SFX $78 <= %02X", t, value or -1))
    end
  end, emu.callbackType.write, base, base, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  local p1 = PL.pad()
  if t >= 340 and t <= 341 then p1 = PL.pad({ y = true })      -- 5LP: expect whoosh 05
  elseif t >= 200 and t <= 201 then p1 = PL.pad({ a = true })  -- 5HK: expect whoosh 06
  end
  emu.setInput(p1, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1000 + o, 0) end
  end
  if t == 120 then wr(0x1051, 8) end   -- second special
  if t == 260 then wr(0x1051, 4) end   -- qcf special
  if t == 400 then log("DONE"); emu.stop(0) end
end, emu.eventType.endFrame)
print("sndcheck loaded")
