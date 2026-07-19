-- probe_hitzone.lua: normals damage vs contact zone / defender activity.
-- Config probe_hitzone_cfg.lua: STATE, PLAYER (attacker), BTN ("y"=LP "x"=HP "b"=LK "a"=HK),
--   RANGE, ALIFT (px to levitate attacker during the attack -> raises contact zone),
--   CROUCH (defender holds down), DBTN/DPH (defender presses DBTN at phase DPH),
--   TAG. One attempt per 200f cycle, 2 cycles max. Logs every defender-hp write with
--   t, damage, both acts, both y positions. Output: appends traces/hitzone.txt
dofile("/Users/koneko/Developer/SailorMoonS/tools/probe_hitzone_cfg.lua")
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "hitzone.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local ab = (PLAYER == 1) and 0x1000 or 0x1080
local db = (PLAYER == 1) and 0x1080 or 0x1000
local dhp = db + 0x49

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr, value)
  if t and t >= 0 then
    local st = emu.getState()
    log(string.format("  W48 t=%d ->%02X pc=%06X", t, value, st["cpu.k"] * 65536 + st["cpu.pc"]))
  end
end, emu.callbackType.write, 0x10C8, 0x10C8, emu.cpuType.snes, emu.memType.snesWorkRam)

emu.addMemoryCallback(function(addr, value)
  if t and t >= 0 then
    local st = emu.getState()
    local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
    local d = ram(db + 0x49) - value
    log(string.format("  HIT t=%d dmg=%d ->%02X pc=%06X aact=%02X dact=%02X a45=%02X d48=%02X d18=%02X mod00=%02X",
      t, 0x60 - value, value, pc, ram(ab + 1), ram(db + 1),
      ram(ab + 0x45), ram(db + 0x48), ram(db + 0x18), ram(0)))
  end
end, emu.callbackType.write, dhp, dhp, emu.cpuType.snes, emu.memType.snesWorkRam)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local groundY = nil
emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  local ph = t % 200
  if t > 400 then log(string.format("== %s done", TAG or STATE)); emu.stop(0); return end
  if ph == 5 then
    wr(db + 0x49, 0x60); wr(0x800 + (2 - PLAYER), 0x60)
    local ax = ram(ab + 0x21) + 256 * ram(ab + 0x22)
    local dx2 = ram(db + 0x21) + 256 * ram(db + 0x22)
    local L = ax <= dx2
    local nx = L and (ax + (RANGE or 40)) or (ax - (RANGE or 40))
    wr(db + 0x21, nx % 256); wr(db + 0x22, math.floor(nx / 256))
    groundY = ram(ab + 0x25) + 256 * ram(ab + 0x26)
    log(string.format("-- %s attempt range=%d alift=%d crouch=%s dbtn=%s dph=%s",
      TAG or STATE, RANGE or 40, ALIFT or 0, tostring(CROUCH or false),
      tostring(DBTN), tostring(DPH)))
  end
  if CROUCH and ph >= 6 then pulse[2 - PLAYER] = { down = true } end
  if DBTN and DPH and ph >= DPH and ph <= DPH + 1 then
    local p = pulse[2 - PLAYER] or {}
    p[DBTN] = true
    pulse[2 - PLAYER] = p
  elseif DBTN and DPH and ph == DPH + 2 and not CROUCH then
    pulse[2 - PLAYER] = nil
  end
  if ADOWN and ph >= 26 and ph <= 36 then
    local p = pulse[PLAYER - 1] or {}
    p.down = true
    pulse[PLAYER - 1] = p
  end
  if ph >= 30 and ph <= 31 then
    local p = pulse[PLAYER - 1] or {}
    p[BTN] = true
    pulse[PLAYER - 1] = p
  elseif ph == 32 and not ADOWN then
    pulse[PLAYER - 1] = nil
  elseif ph == 37 then
    pulse[PLAYER - 1] = nil
  end
  if ALIFT and ALIFT ~= 0 and groundY and ph >= 28 and ph <= 70 then
    local ny = (groundY - ALIFT) % 65536
    wr(ab + 0x25, ny % 256); wr(ab + 0x26, math.floor(ny / 256))
  end
end, emu.eventType.endFrame)
print("probe_hitzone loaded")
