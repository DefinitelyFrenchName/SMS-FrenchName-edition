
-- probe_sms_winpose_ctrl.lua — CONTROL for the winpose probe: same savestate and
-- KO flow but with NO Saturn poke (P1 stays the savestate's Uranus); log
-- acts/poses through the win sequence and screenshot, for A/B against Saturn.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/winposec_ctrl.txt", "w"))
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
local lastact = -1
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x10A1, 0xA8); wr(0x10A2, 0x00)   -- P2 in jab range
    wr(0x10C9, 1)                         -- P2 at 1 HP
  end
  if t == 120 then buttons = {y = true} end   -- 5LP for the KO
  if t == 124 then buttons = {} end
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
      local f = assert(io.open(ENV.TRACE .. "saturn/winposec_" .. shots .. ".png", "wb"))
      f:write(png); f:close()
      log(string.format("t=%03d screenshot %d (act=%02X pose=%02X)", t, shots, a, ram(0x1005)))
    end
    -- also one mid-visible-window shot
    if t == 260 then
      local png = emu.takeScreenshot()
      local f = assert(io.open(ENV.TRACE .. "saturn/winposec_idle.png", "wb"))
      f:write(png); f:close()
    end
  end
  if t > 900 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)
print("winpose loaded")
