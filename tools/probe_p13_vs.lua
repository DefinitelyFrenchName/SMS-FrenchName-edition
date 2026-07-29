-- probe_p13_vs.lua (patch 13 QA): real-taunt E2E in VS mode on the v0.11 ROM.
-- Config probe_p13_vs_cfg.lua: TAUNTS = 0|3. P1 (Uranus) taunts via L, LV1 logged
-- after each; then at a FIXED absolute frame P2 (Jupiter) throws P1 (identical timing
-- both runs -> comparable roll). Output: appends traces/p13_vs.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
dofile(ENV.TOOLS .. "probe_p13_vs_cfg.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p13_vs.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local prevLv = -1
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 2 then log(string.format("=== VS run TAUNTS=%d mode=%02X f70=%02X", TAUNTS, ram(0x8D), ram(0x70))) end
  local lv = ram(0x1F801)
  if lv ~= prevLv then log(string.format("  t=%d LV1 %d->%d p1act=%02X", t, prevLv, lv, ram(0x1001))); prevLv = lv end
  if TAUNTS >= 1 and t >= 30 and t <= 32 then pulse[0] = { l = true } elseif TAUNTS >= 1 and t == 33 then pulse[0] = nil end
  if TAUNTS >= 2 and t >= 220 and t <= 222 then pulse[0] = { l = true } elseif TAUNTS >= 2 and t == 223 then pulse[0] = nil end
  if TAUNTS >= 3 and t >= 410 and t <= 412 then pulse[0] = { l = true } elseif TAUNTS >= 3 and t == 413 then pulse[0] = nil end
  if t == 650 then
    -- park P2 adjacent to P1 for the throw (Jupiter on right, faces left; throw = back?? fwd+HP toward P1 = LEFT+x)
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    local x = p1x + 14
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
    log(string.format("  t=%d pre-throw LV1=%d p1hp=%02X", t, ram(0x1F801), ram(0x1049)))
  end
  if t >= 654 and t <= 657 then pulse[1] = { left = true, x = true } elseif t == 658 then pulse[1] = nil end
  if t == 780 then
    log(string.format("  VERDICT: p1hp=%02X dealt=%d LV1=%d", ram(0x1049), 0x60 - ram(0x1049), ram(0x1F801)))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("probe_p13_vs loaded")
