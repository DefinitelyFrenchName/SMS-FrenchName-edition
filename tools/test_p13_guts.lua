-- test_p13_guts.lua (patch 13): Guts defense-buff suite. Config test_p13_guts_cfg.lua:
--   MODE = "solo"  -> on a patch-13-only ROM (misfire acts forced by poke)
--   MODE = "stack" -> on an 11+12+13 ROM (real L-taunt E2E grant)
-- Damage expectations assume default --l1/l2/l3 = 10/25/45 and the deterministic
-- fixed-timing rolls (2HP=7, throw=24, tech=12, fireball chip=2).
-- Output: traces/p13_guts.txt; exit 0 = all pass.
dofile("/Users/koneko/Developer/SailorMoonS/tools/test_p13_guts_cfg.lua")
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p13_guts.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end
local function lv(p) return ram(0x1F800 + p) end            -- $7F:F801/F802
local function setlv(p, v) wr(0x1F800 + p, v) end
local fails = 0
local function check(name, ok, detail)
  log((ok and "PASS " or "FAIL ") .. name .. (detail and (" " .. detail) or ""))
  if not ok then fails = fails + 1 end
end
local function forceact(base, act)
  wr(base + 1, act); wr(base + 2, 1); wr(base + 4, act); wr(base + 6, 0); wr(base + 7, 0)
end

local CUR_STATE = "training_p11.mss"
local phase, pt, needLoad = 1, nil, true
local saw = {}
local pulse = {}

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. CUR_STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; pt = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local function p2close(gap)
  local p1x = ram(0x1021) + 256 * ram(0x1022)
  local x = p1x + (gap or 16)
  wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
end

local function dmgphase(name, level, expect)
  -- 2HP (a NORMAL) at fixed timing: base roll 5 -- v3: normals must be IMMUNE at any level
  return { name = name, state = "training_p11.mss", dur = 140,
    tick = function(pt)
      if pt == 5 then wr(0x8D, 5); stwlv = true end
      if pt == 6 then setlv(1, 0); setlv(2, level) end
      if pt == 80 then p2close() end
      if pt >= 84 and pt <= 85 then pulse[0] = { down = true, x = true } elseif pt == 86 then pulse[0] = nil end
    end,
    fin = function()
      local dealt = 0x60 - ram(0x10C9)
      check(name, dealt == expect, string.format("dealt=%d want=%d lv2=%d", dealt, expect, lv(2)))
    end }
end


local function specialphase(name, level, expect)
  -- Neptune 214LP direct at fixed timing: base roll 8
  return { name = name, state = "neptune_vs_jupiter.mss", dur = 110,
    tick = function(pt)
      if pt == 6 then setlv(1, 0); setlv(2, level) end
      if pt == 14 then pulse[0] = { down = true } end
      if pt == 17 then pulse[0] = { down = true, left = true } end
      if pt == 20 then pulse[0] = { left = true, y = true } end
      if pt == 23 then pulse[0] = nil end
    end,
    fin = function()
      local dealt = 0x60 - ram(0x10C9)
      check(name, dealt == expect, string.format("dealt=%d want=%d lv2=%d", dealt, expect, lv(2)))
    end }
end
local SOLO = {
  { name = "grant-on-completion", state = "training_p11.mss", dur = 200,
    tick = function(pt)
      if pt == 30 then forceact(0x1000, 0x65) end
      if pt == 25 then saw.lv0 = lv(1) end
    end,
    fin = function()
      check("grant-pre-zero", saw.lv0 == 0, string.format("%d", saw.lv0 or -1))
      check("grant-lv1", lv(1) == 1, string.format("lv=%d p1act=%02X", lv(1), ram(0x1001)))
      local function vword(w) return emu.read(w * 2, emu.memType.snesVideoRam) + 256 * emu.read(w * 2 + 1, emu.memType.snesVideoRam) end
      check("indicator-p1-digit1", vword(0x10E1) == 0x2C51, string.format("%04X", vword(0x10E1)))
      check("indicator-p2-blank", vword(0x10FE) == 0x2000, string.format("%04X", vword(0x10FE)))
    end },
  { name = "indicator-levels", state = "training_p11.mss", dur = 60,
    tick = function(pt)
      if pt == 20 then setlv(1, 3); setlv(2, 2) end
    end,
    fin = function()
      local function vword(w) return emu.read(w * 2, emu.memType.snesVideoRam) + 256 * emu.read(w * 2 + 1, emu.memType.snesVideoRam) end
      check("indicator-p1-3", vword(0x10E1) == 0x2C53, string.format("%04X", vword(0x10E1)))
      check("indicator-p2-2", vword(0x10FE) == 0x2C52, string.format("%04X", vword(0x10FE)))
    end },
  { name = "no-grant-on-interrupt", state = "training_p11.mss", dur = 220,
    tick = function(pt)
      if pt == 10 then p2close(24) end
      if pt == 30 then forceact(0x1000, 0x65) end
      if pt >= 60 and pt <= 61 then pulse[1] = { down = true, y = true } elseif pt == 62 then pulse[1] = nil end
      local a = ram(0x1001)
      if a >= 0x10 and a <= 0x16 then saw.hit = true end
    end,
    fin = function()
      check("interrupt-hit-landed", saw.hit)
      check("interrupt-no-grant", lv(1) == 0, string.format("lv=%d", lv(1)))
    end },
  { name = "stack-and-cap", state = "training_p11.mss", dur = 700,
    tick = function(pt)
      if pt == 30 or pt == 190 or pt == 350 or pt == 510 then forceact(0x1000, 0x65) end
      if pt == 180 then saw.l1 = lv(1) end
      if pt == 340 then saw.l2 = lv(1) end
      if pt == 500 then saw.l3 = lv(1) end
    end,
    fin = function()
      check("stack-1", saw.l1 == 1, string.format("%d", saw.l1 or -1))
      check("stack-2", saw.l2 == 2, string.format("%d", saw.l2 or -1))
      check("stack-3", saw.l3 == 3, string.format("%d", saw.l3 or -1))
      check("stack-cap", lv(1) == 3, string.format("%d", lv(1)))
    end },
  specialphase("special-l0-baseline", 0, 8),
  specialphase("special-l1-20pct", 1, 6),   -- round(8*0.80)=6
  specialphase("special-l2-40pct", 2, 5),   -- round(8*0.60)=5
  specialphase("special-l3-60pct", 3, 3),   -- round(8*0.40)=3
  dmgphase("normal-immune-l0", 0, 5),
  dmgphase("normal-immune-l1", 1, 5),
  dmgphase("normal-immune-l2", 2, 5),
  dmgphase("normal-immune-l3", 3, 5),
  { name = "dmg-p1-defender", state = "training_p11.mss", dur = 140,
    tick = function(pt)
      if pt == 5 then wr(0x8D, 5) end
      if pt == 6 then setlv(1, 3); setlv(2, 0) end
      if pt == 80 then p2close() end
      if pt >= 84 and pt <= 85 then pulse[1] = { down = true, y = true } elseif pt == 86 then pulse[1] = nil end
    end,
    fin = function()
      local dealt = 0x60 - ram(0x1049)
      check("p1-normal-full-damage", dealt >= 1, string.format("dealt=%d (normals immune, full roll)", dealt))
    end },
  { name = "throw-immune", state = "training_p11.mss", dur = 200,
    tick = function(pt)
      if pt == 5 then wr(0x8D, 5) end
      if pt == 6 then setlv(2, 3) end
      if pt == 100 then p2close(14) end
      if pt >= 104 and pt <= 107 then pulse[0] = { right = true, x = true } elseif pt == 108 then pulse[0] = nil end
    end,
    fin = function()
      local dealt = 0x60 - ram(0x10C9)
      check("throw-immune-l3", dealt == 24, string.format("dealt=%d want=24 (throws untouched)", dealt))
    end },
  { name = "tech-immune", state = "training_p11.mss", dur = 260,
    tick = function(pt)
      if pt == 5 then wr(0x8D, 5) end
      if pt == 6 then setlv(2, 3) end
      if pt == 100 then p2close(14) end
      if pt >= 104 and pt <= 107 then pulse[0] = { right = true, x = true } elseif pt == 108 then pulse[0] = nil end
      if pt >= 108 and pt <= 170 then
        if pt % 2 == 0 then pulse[1] = { a = true } else pulse[1] = nil end
      end
      if pt == 171 then pulse[1] = nil end
      if ram(0x1081) == 0x23 then saw.tech = true end
    end,
    fin = function()
      check("tech-happened", saw.tech)
      local dealt = 0x60 - ram(0x10C9)
      check("tech-immune-l3", dealt == 12, string.format("dealt=%d want=12 (throws untouched)", dealt))
    end },
  { name = "chip-scaled", state = "neptune_vs_jupiter.mss", dur = 220,
    tick = function(pt)
      if pt == 6 then setlv(2, 3) end
      if pt >= 122 and pt <= 190 then pulse[1] = { right = true, down = true } end
      if pt == 124 then pulse[0] = { down = true } end
      if pt == 127 then pulse[0] = { down = true, left = true } end
      if pt == 130 then pulse[0] = { left = true, y = true } end
      if pt == 133 then pulse[0] = nil end
      if pt == 191 then pulse[1] = nil end
    end,
    fin = function()
      local dealt = 0x60 - ram(0x10C9)
      check("chip-l3-floor1", dealt == 1, string.format("dealt=%d want=1 (chip 2 cut to floor)", dealt))
    end },
  { name = "round-reset", state = "uranus_vs_jupiter_f5.mss", dur = 900,
    tick = function(pt)
      if pt == 6 then setlv(1, 3); setlv(2, 2) end
      if pt == 10 then wr(0x10C9, 0x01); p2close() end
      -- kill with 2HP: even at LV2=2 the scaled heavy still exceeds 1 hp
      if pt >= 14 and pt <= 15 then pulse[0] = { down = true, x = true } elseif pt == 16 then pulse[0] = nil end
      if pt == 100 then saw.midlv = lv(1) end
      if not saw.resetT and ram(0x1049) == 0x60 and ram(0x10C9) == 0x60
         and ram(0x1001) == 0 and ram(0x1081) == 0 and pt > 120 then saw.resetT = pt end
    end,
    fin = function()
      check("reset-held-during-round", saw.midlv == 3, string.format("%d", saw.midlv or -1))
      check("reset-round2-detected", saw.resetT ~= nil, tostring(saw.resetT))
      check("reset-lv-cleared", lv(1) == 0 and lv(2) == 0, string.format("lv1=%d lv2=%d", lv(1), lv(2)))
    end },
}

local STACK = {
  { name = "taunt-grants-e2e", state = "training_p11.mss", dur = 260,
    tick = function(pt)
      if pt >= 20 and pt <= 22 then pulse[0] = { l = true } elseif pt == 23 then pulse[0] = nil end
      if ram(0x1001) == 0x65 then saw.taunt = true end
    end,
    fin = function()
      check("stack-taunted", saw.taunt)
      check("stack-granted", lv(1) == 1, string.format("lv=%d", lv(1)))
    end },
  { name = "interrupted-taunt-no-grant", state = "training_p11.mss", dur = 220,
    tick = function(pt)
      if pt == 10 then p2close(24) end
      if pt >= 20 and pt <= 22 then pulse[0] = { l = true } elseif pt == 23 then pulse[0] = nil end
      if pt >= 50 and pt <= 51 then pulse[1] = { down = true, y = true } elseif pt == 52 then pulse[1] = nil end
      local a = ram(0x1001)
      if a >= 0x10 and a <= 0x16 then saw.hit = true end
    end,
    fin = function()
      check("stack-interrupted", saw.hit)
      check("stack-no-grant", lv(1) == 0, string.format("lv=%d", lv(1)))
    end },
}

local PHASES = (MODE == "stack") and STACK or SOLO

emu.addEventCallback(function()
  if not pt then return end
  pt = pt + 1
  local P = PHASES[phase]
  P.tick(pt)
  if pt >= P.dur then
    P.fin()
    log("--- phase done: " .. P.name .. " (" .. MODE .. ")")
    phase = phase + 1
    saw = {}; pulse = {}
    if phase > #PHASES then
      log(fails == 0 and ("ALL PASS (" .. MODE .. ")") or (fails .. " FAILURES (" .. MODE .. ")"))
      emu.stop(fails == 0 and 0 or 1)
      return
    end
    CUR_STATE = PHASES[phase].state
    needLoad = true; pt = nil
  end
end, emu.eventType.endFrame)
print("test_p13_guts loaded " .. MODE)
