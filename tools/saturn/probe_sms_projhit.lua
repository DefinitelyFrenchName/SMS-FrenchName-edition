
-- probe_sms_projhit.lua — does a projectile despawn after HITTING? Compare
-- victim=Saturn vs victim=Jupiter. VICTIM env: sat | jup. Caster = P2 (slot B).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local VICTIM = os.getenv("VICTIM") or "sat"
local NIB = tonumber(os.getenv("NIB") or "9")
local CASTER = os.getenv("CASTER") or "p2"
local LOG = assert(io.open(ENV.TRACE .. "saturn/projhit_" .. CASTER .. "_" .. VICTIM .. "_" .. NIB .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
local cbase = (CASTER == "p1") and 0x1000 or 0x1080
local vbase = (CASTER == "p1") and 0x1080 or 0x1000
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(cbase, 0x1C)                                   -- caster = Saturn
    for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(cbase + o, 0) end
    if VICTIM == "sat" then
      wr(vbase, 0x1C)
      for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(vbase + o, 0) end
    end
    wr(0x1021, 0x70); wr(0x1022, 0x00); wr(0x10A1, 0xB0); wr(0x10A2, 0x00)  -- in range
  end
  if t == 120 then wr(cbase + 0x51, NIB) end
  if t >= 120 and t <= 500 and t % 15 == 0 then
    log(string.format("t=%03d caster act=%02X | victim id=%02X act=%02X hp=%d | projA %02X/%02X projB %02X/%02X",
      t, ram(cbase + 1), ram(vbase), ram(vbase + 1), ram(vbase + 0x49),
      ram(0x1100), ram(0x1101), ram(0x1180), ram(0x1181)))
  end
  if t > 520 then
    local stuck = (ram(0x1100) ~= 0) or (ram(0x1180) ~= 0)
    local casterstuck = ram(cbase + 1) >= 0x6A and ram(cbase + 1) <= 0x71
    log(string.format("victim hp=%d", ram(vbase + 0x49)))
    log((stuck or casterstuck) and "STUCK (proj or caster)" or "clean")
    emu.stop((stuck or casterstuck) and 1 or 0)
  end
end, emu.eventType.endFrame)
print("projhit loaded")
