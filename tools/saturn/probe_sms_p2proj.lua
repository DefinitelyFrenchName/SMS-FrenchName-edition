
-- probe_sms_p2proj.lua — is the projectile wedge P2-specific (slot B) rather
-- than mirror-specific? Make ONLY P2 Saturn (P1 stays Jupiter), fire each
-- special from P2, and watch the projectile slots despawn (or not).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/p2proj.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local WHO = os.getenv("WHO") or "p2"     -- p1 | p2
local NIB = tonumber(os.getenv("NIB") or "9")   -- 4/5 qcf, 8/9 qcb
local NIB2 = tonumber(os.getenv("NIB2") or "9")
local DELAY = tonumber(os.getenv("DELAY") or "0")
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
local base = (WHO == "p1") and 0x1000 or 0x1080
local BOTH = (WHO == "both")
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    for _, b in ipairs(BOTH and {0x1000, 0x1080} or {base}) do
      wr(b, 0x1C)
      for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(b + o, 0) end
    end
    wr(0x1021, 0x60); wr(0x1022, 0x00); wr(0x10A1, 0xC0); wr(0x10A2, 0x00)
  end
  if t == 120 then
    if BOTH then
      wr(0x1051, NIB); wr(0x10D1, NIB2)
      log(string.format("-- BOTH fire: p1 nib %X, p2 nib %X (offset %d)", NIB, NIB2, DELAY))
    else
      wr(base + 0x51, NIB); log(string.format("-- %s fires nibble %X", WHO, NIB))
    end
  end
  if BOTH and DELAY > 0 and t == 120 + DELAY then wr(0x10D1, NIB2) end
  if t >= 120 and t <= 460 and t % 10 == 0 then
    log(string.format("t=%03d p1act=%02X p2act=%02X | projA id=%02X act=%02X x=%d | projB id=%02X act=%02X x=%d",
      t, ram(0x1001), ram(0x1081),
      ram(0x1100), ram(0x1101), ram(0x1121) + 256*ram(0x1122),
      ram(0x1180), ram(0x1181), ram(0x11A1) + 256*ram(0x11A2)))
  end
  if t > 470 then
    local stuck = (ram(0x1100) ~= 0) or (ram(0x1180) ~= 0)
    log(stuck and "PROJECTILE STUCK" or "clean despawn")
    emu.stop(stuck and 1 or 0)
  end
end, emu.eventType.endFrame)
print("p2proj loaded")
