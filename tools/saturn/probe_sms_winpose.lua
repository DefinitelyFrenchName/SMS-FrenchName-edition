
-- probe_sms_winpose.lua — KO P2 with Saturn P1; log her acts/poses through the
-- win sequence; verify poses resolve to valid cels; screenshot the win pose.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/winpose.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
local buttons = {}
emu.addEventCallback(function()
  emu.setInput(PL.pad(buttons), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
local acts, shots = {}, 0
local winat = nil
-- who writes P1 act + script-cursor fields around the win moment
local wlog = 0
for _, a in ipairs({0x7E1001, 0x001001}) do
  emu.addMemoryCallback(function(addr, value)
    if t > 200 and wlog < 20 then
      wlog = wlog + 1
      local ok, st = pcall(emu.getState)
      local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
      local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
      log(string.format("t=%03d W act <= %02X @ %02X:%04X", t, value or -1, k, pc))
    end
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
local lastact = -1
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
    wr(0x10A1, 0xA8); wr(0x10A2, 0x00)   -- P2 in jab range
    wr(0x10C9, 1)                         -- P2 at 1 HP
  end
  if t == 120 then buttons = {y = true} end   -- 5LP for the KO (round 1)
  if t == 124 then buttons = {} end
  -- round 2: same setup once the round restarts
  if t == 900 then wr(0x10A1, 0xA8); wr(0x10A2, 0x00); wr(0x10C9, 1); wr(0x1049, 0x60) end
  if t == 930 then buttons = {y = true} end
  if t == 934 then buttons = {} end
  if t >= 1600 and t <= 2400 and t % 100 == 0 then
    local ok, st = pcall(emu.getState)
    local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
    local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
    log(string.format("t=%d seq: 1E05=%02X 1E06=%02X 1E01=%02X 8D=%02X 70=%02X pc=%02X:%04X",
      t, ram(0x1E05), ram(0x1E06), ram(0x1E01), ram(0x8D), ram(0x70), k, pc))
  end
  if t == 1280 or t == 1400 or t == 1520 or t == 1700 or t == 1850 or t == 2000 or t == 2200 then
    local png = emu.takeScreenshot()
    local f = assert(io.open(ENV.TRACE .. "saturn/winmatch_" .. t .. ".png", "wb"))
    f:write(png); f:close()
    log(string.format("t=%d matchshot act=%02X", t, ram(0x1001)))
  end
  if t >= 120 and t <= 880 then
    local a = ram(0x1001)
    if a == 0x24 and t % 20 == 0 then
      log(string.format("t=%03d act24 pose=%02X", t, ram(0x1005)))
    end
    if a ~= lastact then
      lastact = a
      log(string.format("t=%03d P1 act=%02X pose=%02X | p2 act=%02X hp=%d | clock80D=%02X",
        t, a, ram(0x1005), ram(0x1081), ram(0x10C9), ram(0x80D)))
    end
    if a == 0x24 and winat == nil then winat = t end
    if winat and shots < 4 and (t == winat + 60 or t == winat + 150 or t == winat + 250 or t == winat + 350) then
      shots = shots + 1
      local png = emu.takeScreenshot()
      local f = assert(io.open(ENV.TRACE .. "saturn/winpose_" .. shots .. ".png", "wb"))
      f:write(png); f:close()
      log(string.format("t=%03d screenshot %d (act=%02X pose=%02X)", t, shots, a, ram(0x1005)))
    end
    -- also one mid-visible-window shot
    if t == 260 then
      local png = emu.takeScreenshot()
      local f = assert(io.open(ENV.TRACE .. "saturn/winpose_idle.png", "wb"))
      f:write(png); f:close()
    end
  end
  if t > 2450 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)
print("winpose loaded")
