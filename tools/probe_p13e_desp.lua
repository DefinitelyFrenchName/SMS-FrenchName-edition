-- probe_p13e_desp.lua: desperation measurement (motions courtesy of the maintainer;
-- trigger condition: performer hp <= 0x18). Config probe_p13e_desp_cfg.lua:
--   STATE, MOTION = {"2","3","6",...} (numpad, P1-on-left view), BTN = "x"|"a",
--   STEPF = frames per motion step (default 3),
--   POKES = { {addr=..., val=...}, ... }  (applied after load; e.g. LV2, +0x74)
-- P1 performs; logs P1 acts >= 0x2B with a44, all P2 hp writes (PC, damage), and any
-- $C1:0B49 dispatcher hit (Y + record dump). Output: appends traces/p13e_desp.txt
dofile("/Users/koneko/Developer/SailorMoonS/tools/probe_p13e_desp_cfg.lua")
STEPF = STEPF or 3
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p13e_desp.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

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
    local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
    log(string.format("  hp->%02X (dealt %d) pc=%06X p1act=%02X p1a44=%02X j1a44=%02X LV2=%d",
      value, ram(0x10C9) - value >= 0 and (0x60 - value) or -1, pc, ram(0x1001), ram(0x1044), ram(0x1144), ram(0x1F802)))
  end
end, emu.callbackType.write, 0x10C9, 0x10C9, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function()
  if t and t >= 0 then
    local st = emu.getState()
    if st["cpu.x"] == 0x1000 then
      local y = st["cpu.y"]
      local b = {}
      for i = 0, 7 do b[i] = emu.read(0x10000 + y + i, emu.memType.snesPrgRom) end
      log(string.format("  rec@C1:%04X = %02X %02X %02X %02X %02X %02X %02X %02X (misfire=%02X)",
        y, b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[6]))
    end
  end
end, emu.callbackType.exec, 0xC10B49, 0xC10B49, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local DIR = {
  ["1"] = { down = true, left = true }, ["2"] = { down = true }, ["3"] = { down = true, right = true },
  ["4"] = { left = true }, ["6"] = { right = true },
  ["7"] = { up = true, left = true }, ["8"] = { up = true }, ["9"] = { up = true, right = true },
}
local seen = {}
emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  if t == 2 then log(string.format("=== %s motion=%s+%s stepf=%d", STATE, table.concat(MOTION), BTN, STEPF)) end
  if t == 5 then
    wr(0x1049, 0x10)               -- performer low HP (desperation gate)
    if POKES then for _, p in ipairs(POKES) do wr(p.addr, p.val) end end
  end
  -- one attempt per 200f, restore hp each time
  local ph = t
  if ph == 10 then
    wr(0x1049, 0x10); wr(0x10C9, 0x60); wr(0x800, 0x10); wr(0x801, 0x60)
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    local gap = RANGE or 30
    wr(0x10A1, (p1x + gap) % 256); wr(0x10A2, math.floor((p1x + gap) / 256))
  end
  local sd = math.floor((ph - 14) / STEPF) + 1
  if ph >= 14 and sd <= #MOTION then
    pulse[0] = DIR[MOTION[sd]]
  elseif ph >= 14 and sd == #MOTION + 1 then
    local p = {}
    for k, v in pairs(DIR[MOTION[#MOTION]]) do p[k] = v end
    p[BTN] = true
    pulse[0] = p
  elseif ph >= 14 and sd == #MOTION + 2 then
    pulse[0] = nil
  end
  if WALKIN and ph >= 30 and ph <= 120 then pulse[1] = { left = true } elseif WALKIN and ph == 121 then pulse[1] = nil end
  local j = ram(0x1100)
  if j ~= 0 and j ~= (seen.lastj or 0) then
    seen.lastj = j
    log(string.format("  proj spawn id=%02X act=%02X a44=%02X t=%d", j, ram(0x1101), ram(0x1144), t))
  end
  local hpnow = ram(0x10C9)
  if seen.prevhp and hpnow ~= seen.prevhp then
    log(string.format("  POLL p2hp %02X->%02X t=%d p1act=%02X", seen.prevhp, hpnow, t))
  end
  seen.prevhp = hpnow
  local cc = ram(0x8B0)
  if seen.prevcc and cc ~= seen.prevcc then
    log(string.format("  p10-counter %d->%d t=%d", seen.prevcc, cc, t))
  end
  seen.prevcc = cc
  local a = ram(0x1001)
  if a >= 0x2B and not seen[a] then
    seen[a] = true
    log(string.format("  p1 act %02X a44=%02X t=%d", a, ram(0x1044), t))
  end
  if a >= 0x2B and ram(0x1040) ~= 0 and not seen.hb then
    seen.hb = true
    log(string.format("  ACTIVE: act %02X hb=%02X t=%d", a, ram(0x1040), t))
  end
  if t == 60 or t == 100 or t == 140 then
    local f = io.open(TRACE .. string.format("p13e_desp_%d.png", t), "wb")
    f:write(emu.takeScreenshot()); f:close()
  end
  if t == 620 then
    log(string.format("=== end: p2hp=%02X", ram(0x10C9)))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("probe_p13e_desp loaded")
