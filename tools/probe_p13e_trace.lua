-- probe_p13e_trace.lua: full timeline of Pluto's desperation (632146+HP, hp<=0x18).
-- Logs per-frame act/hp changes for both players + every write to BOTH hp bytes with
-- t and PC + $08B0/$0802 changes. Single attempt. Output: traces/p13e_trace.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
pcall(dofile, "/Users/koneko/Developer/SailorMoonS/tools/probe_p13e_trace_cfg.lua")
local LOG = assert(io.open(TRACE .. "p13e_trace.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "pluto_vs_1.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

for _, a in ipairs({ 0x10C9, 0x1049 }) do
  emu.addMemoryCallback(function(addr, value)
    if t and t >= 0 then
      local st = emu.getState()
      log(string.format("  WR t=%d $%04X ->%02X pc=%06X", t, addr % 0x10000, value, st["cpu.k"] * 65536 + st["cpu.pc"]))
    end
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesWorkRam)
end

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local prev = {}
local function trackByte(name, addr)
  local v = ram(addr)
  if prev[name] ~= v then
    log(string.format("chg t=%d %s %s->%02X", t, name, prev[name] and string.format("%02X", prev[name]) or "--", v))
    prev[name] = v
  end
end

local MOTION = { "6", "3", "2", "1", "4", "6" }
local DIR = {
  ["1"] = { down = true, left = true }, ["2"] = { down = true }, ["3"] = { down = true, right = true },
  ["4"] = { left = true }, ["6"] = { right = true },
}
emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  trackByte("p1act", 0x1001); trackByte("p2act", 0x1081)
  trackByte("p1hp", 0x1049); trackByte("p2hp", 0x10C9)
  trackByte("p10cnt", 0x8B0)
  if t == 10 then
    wr(0x1049, 0x10); wr(0x800, 0x10)
    if POKES then for _, p in ipairs(POKES) do wr(p.addr, p.val) end end
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    wr(0x10A1, (p1x + 70) % 256); wr(0x10A2, math.floor((p1x + 70) / 256))
  end
  local sd = math.floor((t - 14) / 3) + 1
  if t >= 14 and sd <= #MOTION then pulse[0] = DIR[MOTION[sd]]
  elseif t >= 14 and sd == #MOTION + 1 then pulse[0] = { right = true, x = true }
  elseif t >= 14 and sd == #MOTION + 2 then pulse[0] = nil end
  if t == 500 then
    log(string.format("FINAL p2hp=%02X totaldealt=%d", ram(0x10C9), 0x60 - ram(0x10C9)))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("probe_p13e_trace loaded")
