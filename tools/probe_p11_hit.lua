-- probe_p11_hit.lua (patch 11): does a point-blank 2LP connect? Config: probe_p11_hit_cfg.lua
--   STATE = savestate filename, MODEPOKE = nil or value for $8D, GAP = px gap (default 16)
-- Logs P1 act/hitbox/connect-latch and P2 act/hp each frame around the press.
-- Output: appends to traces/p11_hit.txt
dofile("/Users/koneko/Developer/SailorMoonS/tools/probe_p11_hit_cfg.lua")
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p11_hit.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end
local function wr(a, v) emu.write(a, v, emu.memType.snesWorkRam) end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k,v in pairs(b) do base[k]=v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

log(string.format("=== STATE=%s MODEPOKE=%s GAP=%d", STATE, tostring(MODEPOKE), GAP or 16))
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 10 and MODEPOKE then wr(0x8D, MODEPOKE); log("poke $8D->" .. MODEPOKE) end
  if t == 20 then
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    local x = p1x + (GAP or 16)
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
    log(string.format("mode=%02X p1x=%04X p2x->%04X", ram(0x8D), p1x, x))
  end
  if t >= 24 and t <= 25 then pulse[0] = { y = true, down = true } end
  if t == 26 then pulse[0] = nil end
  if t >= 24 and t <= 48 then
    log(string.format("t=%d p1act=%02X p1hb=%02X p1conn=%02X p2act=%02X p2hp=%02X p2hs=%02X",
      t, ram(0x1001), ram(0x1040), ram(0x1043), ram(0x1081), ram(0x10C9), ram(0x10C7)))
  end
  if t == 60 then
    log(string.format("VERDICT state=%s mode=%02X p2hp=%02X p2act=%02X", STATE, ram(0x8D), ram(0x10C9), ram(0x1081)))
    emu.stop(0)
  end
end, emu.eventType.endFrame)

print("probe_p11_hit loaded")
