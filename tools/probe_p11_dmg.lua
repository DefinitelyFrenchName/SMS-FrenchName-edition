-- probe_p11_dmg.lua (patch 11, P1): mode 4 vs 5 damage semantics + producer liveness.
-- Phase A: jab at close range in mode 4 (expect: no damage, no hitstun?)
-- Phase B: poke $8D=5, jab again (expect: damage? hitstun?), watch producer exec + HUD
-- Output: traces/p11_dmg.txt (+ p11_dmg_mode5.png)
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p11_dmg.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end
local function wr(a, v) emu.write(a, v, emu.memType.snesWorkRam) end

local t, needLoad = -1, true
local prod, upl = 0, 0
emu.addMemoryCallback(function() prod = prod + 1 end, emu.callbackType.exec, 0x80D5E8, 0x80D5E8, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function() upl = upl + 1 end, emu.callbackType.exec, 0x80D56F, 0x80D56F, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
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

local prev = {}
local function trackByte(name, addr)
  local v = ram(addr)
  if prev[name] ~= v then
    log(string.format("chg t=%d %s %s->%02X", t, name, prev[name] and string.format("%02X", prev[name]) or "--", v))
    prev[name] = v
  end
end
local pp, pu = 0, 0
local function live(tag)
  log(string.format("live %s t=%d prod=%d upl=%d", tag, t, prod - pp, upl - pu)); pp, pu = prod, upl
end

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  trackByte("mode", 0x8D)
  trackByte("p2hp", 0x10C9); trackByte("p2act", 0x1081)
  trackByte("bar1", 0x800); trackByte("bar2", 0x801)
  trackByte("p1act", 0x1001)

  if t == 20 then wr(0x10A1, 0xE0); wr(0x10A2, 0x00); log("poke P2 X->00E0 (mode 4 jab)") end
  if t >= 24 and t <= 25 then pulse[0] = { y = true } end
  if t == 26 then pulse[0] = nil end
  if t == 70 then live("mode4jab"); log(string.format("verdict4 p2hp=%02X p2act=%02X", ram(0x10C9), ram(0x1081))) end

  if t == 80 then wr(0x8D, 0x05); log("poke $8D->05") end
  if t == 90 then wr(0x10A1, 0xE0); wr(0x10A2, 0x00); log("poke P2 X->00E0 (mode 5 jab)") end
  if t >= 94 and t <= 95 then pulse[0] = { y = true } end
  if t == 96 then pulse[0] = nil end
  if t == 150 then
    live("mode5jab"); log(string.format("verdict5 p2hp=%02X p2act=%02X bar2=%02X", ram(0x10C9), ram(0x1081), ram(0x801)))
    local f = io.open(TRACE .. "p11_dmg_mode5.png", "wb"); f:write(emu.takeScreenshot()); f:close()
  end
  if t == 160 then wr(0x8D, 0x04); log("poke $8D->04") end
  if t == 200 then live("backto4"); log("done"); emu.stop(0) end
end, emu.eventType.endFrame)

print("probe_p11_dmg loaded")
