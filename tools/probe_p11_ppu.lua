-- probe_p11_ppu.lua (patch 11, P9b): why is BG3 invisible in training mode?
-- Config probe_p11_ppu_cfg.lua: STATE = savestate to inspect.
--  - dumps all emu.getState() keys containing screen/bright/mode
--  - watches writes to $212C/$212D (TM/TS) logging value+scanline (first 12)
--  - dumps CGRAM words 0-31 (BG 2bpp palettes 0-7)
-- Output: appends traces/p11_ppu.txt
dofile("/Users/koneko/Developer/SailorMoonS/tools/probe_p11_ppu_cfg.lua")
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p11_ppu.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local tmLogs = 0
emu.addMemoryCallback(function(addr, value)
  if t >= 0 and tmLogs < 12 then
    tmLogs = tmLogs + 1
    log(string.format("  TM/TS write $%04X = %02X @scanline %d", addr, value, emu.getState()["ppu.scanline"]))
  end
end, emu.callbackType.write, 0x212C, 0x212D, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 1 then log("=== STATE=" .. STATE) end
  if t == 10 then
    local st = emu.getState()
    for k, v in pairs(st) do
      if type(k) == "string" and (k:find("creen") or k:find("right") or k:find("ode") or k:find("orced")) then
        log(string.format("state %s = %s", k, tostring(v)))
      end
    end
    local s = "cgram[0..31]:"
    for i = 0, 31 do
      local lo = emu.read(i * 2, emu.memType.snesCgRam)
      local hi = emu.read(i * 2 + 1, emu.memType.snesCgRam)
      s = s .. string.format(" %04X", hi * 256 + lo)
      if i == 15 then s = s .. " |" end
    end
    log(s)
  end
  if t == 40 then log("---"); emu.stop(0) end
end, emu.eventType.endFrame)

print("probe_p11_ppu loaded")
