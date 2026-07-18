-- probe_p8cal.lua: calibrate the Venus 6HP mash-escape window. P1 Venus throws P2;
-- P2 mashes starting at grab+D for D in {0,2,4,6,8,10,12,14}; log outcome per D
-- (toss write lo<0x850 vs tech write lo>=0x850, damage). Run on clean AND patched.
-- Output: appends traces/p8cal.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p8cal.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "venus_vs_jupiter_clean.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local writes = {}
emu.addMemoryCallback(function(addr, value)
  if t and t >= 0 then
    local st = emu.getState()
    local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
    writes[#writes + 1] = { t = t, v = value, pc = pc }
  end
end, emu.callbackType.write, 0x10C9, 0x10C9, emu.cpuType.snes, emu.memType.snesWorkRam)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local DS = { 0, 2, 4, 6, 8, 10, 12, 14 }
local grabT = nil
emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  local cyc = math.floor(t / 200) + 1
  local ph = t % 200
  local D = DS[cyc]
  if not D then
    log("=== p8cal done"); emu.stop(0); return
  end
  if ph == 5 then
    writes = {}; grabT = nil
    wr(0x10C9, 0x60); wr(0x801, 0x60); wr(0x1049, 0x60); wr(0x800, 0x60)
    local vx = ram(0x1021) + 256 * ram(0x1022)
    local dx = ram(0x10A1) + 256 * ram(0x10A2)
    local L = vx <= dx
    local nx = L and (vx + 14) or (vx - 14)
    wr(0x10A1, nx % 256); wr(0x10A2, math.floor(nx / 256))
  end
  if ph >= 14 and ph <= 17 then
    local vx = ram(0x1021) + 256 * ram(0x1022)
    local dx = ram(0x10A1) + 256 * ram(0x10A2)
    local p = { x = true }
    if vx <= dx then p.right = true else p.left = true end
    pulse[0] = p
  elseif ph == 18 then pulse[0] = nil end
  if not grabT and ram(0x1081) == 0x1C then grabT = ph end
  if grabT and ph >= grabT + D and ph <= grabT + D + 10 then
    pulse[1] = (ph % 2 == 0) and { y = true } or { b = true, a = true }
  elseif grabT and ph == grabT + D + 11 then pulse[1] = nil end
  if ph == 199 then
    local desc = ""
    for _, w in ipairs(writes) do
      local lo = w.pc % 0x10000
      desc = desc .. string.format(" %s@t%d->%02X(pc%04X)", lo >= 0x850 and "TECH" or (lo >= 0x820 and "TOSS" or "OTH"), w.t % 200, w.v, lo)
    end
    log(string.format("D=%2d grabT=%s p2hp=%02X writes:%s", D, tostring(grabT), ram(0x10C9), desc))
  end
end, emu.eventType.endFrame)
print("probe_p8cal loaded")
