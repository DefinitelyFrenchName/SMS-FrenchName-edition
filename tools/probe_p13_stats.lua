-- probe_p13_stats.lua (patch 13, D2): do the ACS stats / first_hit_defense feed the
-- damage formula? Pokes P2 +0x71 (defense), P1 +0x70 (attack), P2 +0x48 (first-hit
-- defense) through a value sweep, measuring Uranus 2LP damage each time (hp restored
-- between hits). Also exec-watches $C0:D055 (scaling-matrix lookup) during hits.
-- Output: traces/p13_stats.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p13_stats.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
local d055 = 0
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function() if t and t >= 0 then d055 = d055 + 1 end end,
  emu.callbackType.exec, 0x80D055, 0x80D055, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function() if t and t >= 0 then d055 = d055 + 1 end end,
  emu.callbackType.exec, 0xC0D055, 0xC0D055, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

-- sweep: {label, setup(v), values}
local SWEEP = {
  { name = "P2 +0x71 defense", addr = 0x10F1, vals = { 0, 1, 3, 7, 15, 255 } },
  { name = "P1 +0x70 attack",  addr = 0x1070, vals = { 0, 1, 3, 7, 15, 255 } },
  { name = "P2 +0x48 fhdef",   addr = 0x10C8, vals = { 0, 1, 3, 7, 15, 255 } },
}
local si, vi = 1, 1
emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  if t == 5 then wr(0x8D, 5) end
  local ph = t % 80
  if ph == 10 then
    local s = SWEEP[si]
    if not s then log("done"); emu.stop(0); return end
    wr(0x10C9, 0x60)                      -- restore hp
    wr(s.addr, s.vals[vi])
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    wr(0x10A1, (p1x + 16) % 256); wr(0x10A2, math.floor((p1x + 16) / 256))
    d055 = 0
  end
  if ph >= 14 and ph <= 15 then pulse[0] = { down = true, y = true } elseif ph == 16 then pulse[0] = nil end
  if ph == 60 then
    local s = SWEEP[si]
    if s then
      log(string.format("%s = %3d -> 2LP dmg = %d (d055 execs=%d)", s.name, s.vals[vi], 0x60 - ram(0x10C9), d055))
      -- restore the poked stat to 0 before next
      wr(s.addr, (s.name:find("fhdef")) and 0 or 0)
      vi = vi + 1
      if vi > #s.vals then vi = 1; si = si + 1 end
    end
  end
end, emu.eventType.endFrame)
print("probe_p13_stats loaded")
