-- probe_p13f_desp.lua: desperation compendium probe. Config probe_p13f_desp_cfg.lua:
--   STATE, PLAYER (performer), MOTION="632146" (numpad, auto-mirrored by side),
--   BTN="x"|"a", RANGES={70,40,110} (retry list), CROUCH=true (defender crouches),
--   AIR=true (jump first, then the motion), TOFF=0 (extra frames before the attempt,
--   to sample a different damage roll), TAG="name" (log label)
-- Per attempt (400f cycle): restore hp/positions at start, perform, log every
-- defender-hp write with t+PC+class, defender grab state, performer acts+a44.
-- Output: appends traces/p13f_desp.txt
dofile("/Users/koneko/Developer/SailorMoonS/tools/probe_p13f_desp_cfg.lua")
TOFF = TOFF or 0
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p13f_desp.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local pb = (PLAYER == 1) and 0x1000 or 0x1080     -- performer
local db = (PLAYER == 1) and 0x1080 or 0x1000     -- defender
local dhp = db + 0x49

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local hits = {}
emu.addMemoryCallback(function(addr, value)
  if t and t >= 0 then
    local st = emu.getState()
    local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
    local lo = pc % 0x10000
    local kind = "other"
    if pc >= 0x80C000 and pc < 0x80C300 then kind = "MELEE"
    elseif pc >= 0x80C300 and pc < 0x80C700 then kind = "PROJ"
    elseif lo >= 0x0D50 and lo <= 0x0D70 then kind = "TICK"
    elseif lo >= 0x0820 and lo <= 0x0870 then kind = "TOSS"
    end
    local sb = (PLAYER == 1) and 0x1100 or 0x1180
    hits[#hits + 1] = { t = t, v = value, pc = pc, kind = kind,
      a1 = ram(0x1044), a2 = ram(0x10C4), act1 = ram(0x1001), act2 = ram(0x1081),
      dy = ram(db + 0x25) + 256 * ram(db + 0x26), sy = ram(sb + 0x25) + 256 * ram(sb + 0x26) }
  end
end, emu.callbackType.write, dhp, dhp, emu.cpuType.snes, emu.memType.snesWorkRam)

if LOGROW then
  local nlog = 0
  emu.addMemoryCallback(function(addr, value)
    if t and t >= 0 and nlog < 60 then
      local st = emu.getState()
      local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
      local fo = addr % 0x400000
      local po = pc % 0x400000
      if fo >= po and fo <= po + 3 then return end
      if pc == 0x80D4A1 then return end
      nlog = nlog + 1
      local m = fo - 0xD081
      log(string.format("  MATRD t=%d file=%06X (m%d = r%d c%d) v=%02X pc=%06X", t, fo,
        m, math.floor(m / 16), m % 16, value, pc))
    end
  end, emu.callbackType.read, 0xD000, 0xD4FF, emu.cpuType.snes, emu.memType.snesPrgRom)
end

if LOGREC then
  emu.addMemoryCallback(function()
    if t and t >= 0 then
      local st = emu.getState()
      if st["cpu.x"] == ((PLAYER == 1) and 0x1000 or 0x1080) then
        local y = st["cpu.y"]
        local b = {}
        for i = 0, 7 do b[i] = emu.read(0x10000 + y + i, emu.memType.snesPrgRom) end
        log(string.format("   REC t=%d @C1:%04X = %02X %02X %02X %02X %02X %02X %02X", t, y,
          b[0], b[1], b[2], b[3], b[4], b[5], b[6]))
      end
    end
  end, emu.callbackType.exec, 0xC10B49, 0xC10B49, emu.cpuType.snes, emu.memType.snesMemory)
end

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local function posxpb() return ram(pb + 0x21) + 256 * ram(pb + 0x22) end
local function onLeft()
  local px = ram(pb + 0x21) + 256 * ram(pb + 0x22)
  local dx = ram(db + 0x21) + 256 * ram(db + 0x22)
  return px <= dx
end
local function dirpad(c, L)
  local m = { down = (c == "1" or c == "2" or c == "3"), up = (c == "7" or c == "8" or c == "9") }
  local fwd = (c == "3" or c == "6" or c == "9")
  local back = (c == "1" or c == "4" or c == "7")
  if fwd then if L then m.right = true else m.left = true end end
  if back then if L then m.left = true else m.right = true end end
  return m
end

local attempt, saw = 0, {}
emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  local ph = t % 400
  if ph == 5 then
    attempt = attempt + 1
    local r = RANGES[attempt]
    if not r or attempt > #RANGES then
      log(string.format("== %s: NO MORE ATTEMPTS", TAG or STATE))
      emu.stop(0); return
    end
    hits = {}; saw = {}
    local php = NOLOWHP and 0x60 or 0x10
    wr(pb + 0x49, php); wr(0x800 + (PLAYER - 1), php)
    wr(db + 0x49, DEFHP or 0x60); wr(0x800 + (2 - PLAYER), DEFHP or 0x60)
    -- park defender at range r (side-aware)
    local px = ram(pb + 0x21) + 256 * ram(pb + 0x22)
    local L = onLeft()
    local nx = L and (px + r) or (px - r)
    wr(db + 0x21, nx % 256); wr(db + 0x22, math.floor(nx / 256))
    if POKES then for _, p in ipairs(POKES) do wr(p.addr, p.val) end end
    log(string.format("-- %s attempt %d range=%d crouch=%s toff=%d", TAG or STATE, attempt, r, tostring(CROUCH or false), TOFF))
  end
  if DEFJUMP and ph >= DEFJUMP and ph <= DEFJUMP + 2 then pulse[2 - PLAYER] = { up = true }
  elseif DEFJUMP and ph == DEFJUMP + 3 then pulse[2 - PLAYER] = nil end
  if DTAUNT and ph >= DTAUNT and ph <= DTAUNT + 1 then pulse[2 - PLAYER] = { l = true }
  elseif DTAUNT and ph == DTAUNT + 2 then pulse[2 - PLAYER] = nil end
  if DEFBLOCK and ph >= (DEFBLOCKAT or 6) then
    local L = onLeft()   -- performer on left -> defender blocks by holding right... away = same dir as performer->defender? defender holds AWAY from performer
    local p = {}
    if L then p.right = true else p.left = true end
    if DEFBLOCK == "crouch" then p.down = true end
    pulse[2 - PLAYER] = p
  end
  -- defender crouch hold
  if CROUCH and ph >= 6 then pulse[2 - PLAYER + 0] = { down = true } end
  if CROUCH and ph < 6 then pulse[2 - PLAYER + 0] = nil end
  -- AIR: jump at ph 10, motion from ph 22 (airborne)
  local m0 = AIR and 22 or 10
  local L = onLeft()
  if AIR and ph >= 10 + TOFF and ph <= 12 + TOFF then pulse[PLAYER - 1] = { up = true } end
  local sf = STEPF or 3
  local sd = math.floor((ph - m0 - TOFF) / sf) + 1
  if ph >= m0 + TOFF and sd <= #MOTION then
    pulse[PLAYER - 1] = dirpad(MOTION:sub(sd, sd), L)
  elseif ph >= m0 + TOFF and sd == #MOTION + 1 then
    local p = NEUTRALBTN and {} or dirpad(MOTION:sub(#MOTION, #MOTION), L)
    if not NOBTN then p[BTN] = true end
    pulse[PLAYER - 1] = p
  elseif ph >= m0 + TOFF and sd == #MOTION + 2 then
    pulse[PLAYER - 1] = HOLDDIR and dirpad(HOLDDIR, onLeft(PLAYER and nil) == nil and true or onLeft()) or nil
  end
  if HOLDDIR and ph >= m0 + TOFF and sd > #MOTION + 2 then
    pulse[PLAYER - 1] = dirpad(HOLDDIR, onLeft())
  end
  if PROJY then
    local sb = (PLAYER == 1) and 0x1100 or 0x1180
    if ram(sb) ~= 0 then
      local dy = ram(db + 0x25) + 256 * ram(db + 0x26)
      local ny = (dy + PROJY) % 65536
      wr(sb + 0x25, ny % 256); wr(sb + 0x26, math.floor(ny / 256))
    end
  end
  if LOGFD then
    local tup = string.format("pact=%02X hb=%02X hu=%02X slot=%02X sx=%04X px=%04X dact=%02X",
      ram(pb + 1), ram(pb + 0x40), ram(pb + 0x41), ram((PLAYER == 1) and 0x1100 or 0x1180),
      ram(((PLAYER == 1) and 0x1100 or 0x1180) + 0x21) + 256 * ram(((PLAYER == 1) and 0x1100 or 0x1180) + 0x22),
      posxpb(), ram(db + 1))
    if tup ~= saw.fdt then
      local slim = tup:gsub(" sx=%x+", ""):gsub(" px=%x+", "")
      if slim ~= (saw.fds or "") then log(string.format("   FD t=%d %s", t, tup)) end
      saw.fdt = tup; saw.fds = slim
    end
  end
  -- track performer acts + defender grab
  local a = ram(pb + 1)
  if a >= 0x2B and not saw[a] then
    saw[a] = true
    log(string.format("   act %02X a44=%02X t=%d", a, ram(pb + 0x44), t))
  end
  if ram(db + 1) == 0x1C and not saw.grab then saw.grab = true; log("   defender GRABBED (act 1C) t=" .. t) end
  if LOGDACT then
    local da = ram(db + 1)
    if da ~= saw.pda then log(string.format("   dact %02X->%02X t=%d", saw.pda or 0, da, t)); saw.pda = da end
  end
  -- end of attempt: report
  if ph == 399 then
    if #hits > 0 then
      local total, kinds = 0, {}
      local prev = 0x60
      local detail = ""
      for _, h in ipairs(hits) do
        local d = prev - h.v
        prev = h.v
        if d > 0 then total = total + d end
        kinds[h.kind] = (kinds[h.kind] or 0) + math.max(d, 0)
        detail = detail .. string.format(" %s:%d(a44=%02X/%02X act=%02X/%02X)", h.kind, d, h.a1, h.a2, h.act1, h.act2) .. string.format("[t=%d dy=%04X sy=%04X]", h.t, h.dy, h.sy)
      end
      local ks = ""
      for k, v in pairs(kinds) do ks = ks .. string.format(" %s=%d", k, v) end
      log(string.format("== %s RESULT: total=%d grabbed=%s byPath:%s", TAG or STATE, total, tostring(saw.grab or false), ks))
      log("   hits:" .. detail)
      emu.stop(0)
    end
  end
end, emu.eventType.endFrame)
print("probe_p13f_desp loaded")
