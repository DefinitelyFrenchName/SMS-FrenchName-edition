-- probe_p13b_acs.lua (patch 13 v3, P2): do ACS +0x73 (buff_special) / +0x74 (buff_secret)
-- scale SPECIAL-move damage? Neptune P1 214LP vs P2, stat swept, hp restored between.
-- Output: traces/p13b_acs.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p13b_acs.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "neptune_vs_jupiter.mss", "rb"))
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

local SWEEP = {
  { name = "P1 +0x73 special", addr = 0x1073, vals = { 0, 1, 3, 7, 15, 255 } },
  { name = "P1 +0x74 secret",  addr = 0x1074, vals = { 0, 1, 3, 7, 15, 255 } },
}
local si, vi = 1, 1
emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  local ph = t % 130
  if ph == 10 then
    local s = SWEEP[si]
    if not s then log("done"); emu.stop(0); return end
    wr(0x10C9, 0x60)
    wr(s.addr, s.vals[vi])
  end
  if ph == 14 then pulse[0] = { down = true } end
  if ph == 17 then pulse[0] = { down = true, left = true } end
  if ph == 20 then pulse[0] = { left = true, y = true } end
  if ph == 23 then pulse[0] = nil end
  if ph == 110 then
    local s = SWEEP[si]
    if s then
      log(string.format("%s = %3d -> 214LP dmg = %d", s.name, s.vals[vi], 0x60 - ram(0x10C9)))
      wr(s.addr, 0)
      vi = vi + 1
      if vi > #s.vals then vi = 1; si = si + 1 end
    end
  end
end, emu.eventType.endFrame)
print("probe_p13b_acs loaded")
