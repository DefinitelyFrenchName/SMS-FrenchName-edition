-- probe_p13b_throws.lua (patch 13 v3, P3, knowledge): per-character throw damage-apply
-- sites. Config probe_p13b_throws_cfg.lua: STATE, PLAYER (thrower). Walks the thrower in
-- and presses fwd+HP repeatedly; logs every defender-HP write with PC.
-- Output: appends traces/p13b_throws.txt
dofile("/Users/koneko/Developer/SailorMoonS/tools/probe_p13b_throws_cfg.lua")
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p13b_throws.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
local tbase = (PLAYER == 1) and 0x1000 or 0x1080
local vbase = (PLAYER == 1) and 0x1080 or 0x1000
local vhp = vbase + 0x49
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr, value)
  if t and t >= 0 then
    local st = emu.getState()
    local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
    log(string.format("  %s p%d(cid%d) t=%d hpwrite ->%02X pc=%06X vact=%02X", STATE, PLAYER,
      ram(tbase), t, value, pc, ram(vbase + 1)))
  end
end, emu.callbackType.write, vhp, vhp, emu.cpuType.snes, emu.memType.snesWorkRam)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  if t == 2 then wr(0x8D, 5) end     -- ensure damage in case of a Practice-tagged state
  local ph = t % 150
  if ph == 10 then
    -- park thrower adjacent (side-aware)
    local vx = ram(vbase + 0x21) + 256 * ram(vbase + 0x22)
    local tx = ram(tbase + 0x21) + 256 * ram(tbase + 0x22)
    local nx = (tx <= vx) and (vx - 14) or (vx + 14)
    wr(tbase + 0x21, nx % 256); wr(tbase + 0x22, math.floor(nx / 256))
    wr(vbase + 0x49, 0x60)
  end
  local L = (ram(tbase + 0x21) + 256 * ram(tbase + 0x22)) <= (ram(vbase + 0x21) + 256 * ram(vbase + 0x22))
  if ph >= 14 and ph <= 17 then
    local p = { x = true }
    if L then p.right = true else p.left = true end
    pulse[PLAYER - 1] = p
  elseif ph == 18 then pulse[PLAYER - 1] = nil end
  if t == 460 then log(string.format("=== done %s p%d", STATE, PLAYER)); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_p13b_throws loaded")
