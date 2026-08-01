
-- probe_ko_forceact.lua — force the victim into a KO act and watch the chain.
-- GAME=supers|sms, ACT=1E (default). Uses the proven force-act write set.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local GAME = os.getenv("GAME") or "sms"
local ACT = tonumber(os.getenv("ACT") or "1E", 16)
local LOG = assert(io.open(ENV.TRACE .. "saturn/koforce_" .. GAME .. "_" .. string.format("%02X", ACT) .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local wcount = 0
local STATE = (GAME == "supers") and "saturn/saturn_vs_uranus_supers.mss" or "uranus_vs_jupiter_f5.mss"
local HOOK = (GAME == "supers") and 0x808347 or 0x808353
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, HOOK, HOOK, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
for _, spec in ipairs({{0xEFD2D2, "handler-entry"}, {0xEFD2FD, "handler-perframe"},
                       {0xEF036E, "turn/land"}, {0xEF0204, "tail-0204"},
                       {0xEF0216, "tail-rts"}, {0xEFDB70, "helper"}, {0xC115C8, "ministub"}, {0xEFDB30, "tramp3"}, {0xC1259E, "disp-259E"}, {0xC11708, "disp-1708"}}) do
  emu.addMemoryCallback(function()
    if t and t >= 101 and t <= 103 then
      local ok2, st2 = pcall(emu.getState)
      local xx = st2 and (st2["cpu.x"] or st2["snes.cpu.x"]) or -1
      log(string.format("  t=%d EXEC %s X=%04X obj1200=%02X obj1280=%02X tblEntry=%02X%02X",
        t, spec[2], xx, ram(0x1200), ram(0x1280),
        ram(0x10000 + 0) or 0, 0))
    end
  end, emu.callbackType.exec, spec[1], spec[1], emu.cpuType.snes, emu.memType.snesMemory)
end
local trail, trailing = {}, false
emu.addMemoryCallback(function(addr)
  if trailing and #trail < 120 then trail[#trail+1] = string.format("%06X", addr) end
end, emu.callbackType.exec, 0xC10000, 0xC1FFFF, emu.cpuType.snes, emu.memType.snesMemory)
local perframe = {}
for _, spec in ipairs({{0xC1007C, "hook007C"}, {0xC10000, "mainloop0000"},
                       {0xC12584, "loop1200"}, {0xC116EE, "loop1100"},
                       {0xC115C8, "ministub"}, {0xEFDA60, "tramp3"},
                       {0xEFC6F7, "saturn-dispatch"}, {0xC1259E, "disp259E"}}) do
  emu.addMemoryCallback(function()
    perframe[spec[2]] = (perframe[spec[2]] or 0) + 1
  end, emu.callbackType.exec, spec[1], spec[1], emu.cpuType.snes, emu.memType.snesMemory)
end
local ex83 = {}
emu.addMemoryCallback(function()
  if t and t >= 100 and t <= 104 then
    ex83[#ex83+1] = string.format("%02X", ram(0x88))
  end
end, emu.callbackType.exec, 0xC10083, 0xC10083, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function()
  if t and t >= 100 and t <= 104 then
    log(string.format("  t=%d DISPATCH-RET(0083) obj=$%02X", t, ram(0x88)))
  end
end, emu.callbackType.exec, 0xC10083, 0xC10083, emu.cpuType.snes, emu.memType.snesMemory)
for _, a in ipairs({0x7E1025, 0x001025}) do
  emu.addMemoryCallback(function(addr, value)
    if t and t >= 100 and t <= 106 and wcount < 24 then
      wcount = wcount + 1
      local ok, st = pcall(emu.getState)
      local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
      local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
      log(string.format("  t=%d W y <= %02X @ %02X:%04X", t, value or -1, k, pc))
    end
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 and GAME == "sms" then
    wr(0x1000, 0x1C)
    for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
  end
  if t == 100 then
    wr(0x1049, 0)                                   -- HP 0
    wr(0x1001, ACT); wr(0x1002, 0); wr(0x1004, ACT); wr(0x1006, 0); wr(0x1007, 0)
    log(string.format("forced act %02X (id=%02X)", ACT, ram(0x1000)))
  end
  if t == 102 then trailing = true end
  if t == 104 and #trail > 0 then
    log("TRAIL: " .. table.concat(trail, " "))
    trail = {}; trailing = false
  end
  if t >= 98 and t <= 108 then
    local parts = {}
    for k, v in pairs(perframe) do parts[#parts+1] = k .. "=" .. v end
    table.sort(parts)
    log(string.format("  t=%d calls: %s | pool1200 ids: %02X %02X %02X %02X", t,
      table.concat(parts, " "), ram(0x1200), ram(0x1280), ram(0x1300), ram(0x1380)))
    perframe = {}
  end
  if t >= 100 and t <= 140 then
    log(string.format("t=%03d act=%02X st=%02X pose=%02X y=%02X%02X vx=%02X%02X vy=%02X%02X f16=%02X",
      t, ram(0x1001), ram(0x1002), ram(0x1005),
      ram(0x1026), ram(0x1025), ram(0x1033), ram(0x1032), ram(0x1035), ram(0x1034), ram(0x1016)))
  end
  if t > 430 then
    log(ram(0x1001) == ACT and "STUCK" or ("progressed to " .. string.format("%02X", ram(0x1001))))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("koforce loaded")
