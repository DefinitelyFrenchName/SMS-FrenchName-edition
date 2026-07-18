-- test_regression.lua — unified regression suite (base game + per-patch).
--
-- PLAN / DESIGN
--   Layer 0 (static): PRG-ROM fingerprints auto-DETECT which of patches 1-13 are in
--     the loaded ROM (stable signature bytes extracted clean-vs-standalone-vs-stack);
--     damage-matrix integrity rows (0/10/48) asserted on every ROM (no patch may edit).
--   Layer 1 (base): engine invariants that must hold on ANY build (clean or stacked) —
--     deterministic damage rolls, counter-hit −2 columns, posture tables, proximity
--     normals, throw toss path, desperation types/totals (Jupiter strike, Uranus
--     hybrid+toss, Pluto drain grab, Neptune corrected input), dash distance and the
--     2HP→dash cancel gate (expectations switch on detected p5/p1).
--   Layer 2 (patch): nominal + edge cases per detected patch — p7 dual-mode (Pluto 5HP
--     hits crouching Mercury iff patched; Chibi still whiffs at default height), p8
--     dual-mode (mash at grab+14 techs iff patched; grab+4 always techs = base), p10
--     combo counter, p11 L+R menu + P1-HP-LOW navigation, p12 taunt (nominal, R-held
--     exclusion, act-gate edge), p13 Guts (grant, interrupt, special scaling, throw
--     exemption, Uranus toss, Pluto ticks, round-reset clears levels) and the
--     cross-patch counter-hit×Guts case (72 → 29, exercising the v3.3 wide tables).
--   Base also covers the full 9-character desperation compendium (types + totals) and
--     three crouch-mechanism edges (Uranus 51 hit-count, Mercury 62 column, Chibi 24).
--   Values are single-roll deterministic (fixed savestate + fixed input frames).
--
-- Config tools/test_regression_cfg.lua (optional):
--   EXPECT = "clean"|"all"  (assert detection result), ONLY = "pattern" (filter tests)
-- Output: traces/regression.txt, final line "ALL PASS (n)" or "FAILURES (k/n)".
pcall(dofile, "/Users/koneko/Developer/SailorMoonS/tools/test_regression_cfg.lua")
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "regression.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local PRG = emu.memType.snesPrgRom
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end
local function rom(a) return emu.read(a, PRG) end

-- ===== Layer 0: fingerprints =====
local SIGS = {
  p1 = { { 0x01874D, 0x20 }, { 0x01874E, 0xBE }, { 0x01BE22, 0xC9 }, { 0x01BE23, 0x04 } },
  p2 = { { 0x0188ED, 0x2A }, { 0x0188EE, 0xBE }, { 0x01BE2A, 0x20 } },
  p3 = { { 0x00884B, 0xA9 }, { 0x00884C, 0x0C }, { 0x00884F, 0x65 } },
  p4 = { { 0x00FFC8, 0x20 }, { 0x00FFC9, 0x46 }, { 0x00FFCA, 0x72 } },  -- " Fr(enchName)"
  p5 = { { 0x0188EA, 0x40 }, { 0x0188EB, 0x06 } },
  p6 = { { 0x009CCD, 0x22 }, { 0x009CCE, 0x85 }, { 0x009CCF, 0xBE } },
  p7 = { { 0x0AF0DE, 0x3E } },
  p8 = { { 0x016C70, 0x01 } },
  p9 = { { 0x0AFD5D, 0xF5 }, { 0x0AFD65, 0xF5 }, { 0x0AFD6D, 0xF5 } },
  p10 = { { 0x00D56F, 0x5C }, { 0x00D5E8, 0x5C } },
  p11 = { { 0x008373, 0x5C }, { 0x008374, 0x90 }, { 0x008375, 0x01 } },
  p12 = { { 0x008377, 0x5C }, { 0x008378, 0x00 }, { 0x008379, 0x00 } },
  p13 = { { 0x00837B, 0x5C }, { 0x00C09C, 0x22 }, { 0x00C09D, 0xC2 } },
}
local MATRIX_ROWS = {
  [0] = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
  [10] = { 0x15, 0x15, 0x14, 0x14, 0x13, 0x11, 0x0F, 0x0D, 0x0A, 0x08, 0x07, 0x06, 0x05, 0x05, 0x05, 0x05 },
  [48] = { 0x48, 0x48, 0x48, 0x48, 0x48, 0x48, 0x48, 0x3E, 0x30, 0x25, 0x20, 0x1C, 0x1A, 0x18, 0x18, 0x17 },
}
local has = {}

-- ===== harness =====
local t, needLoad, stateFile = -1, false, nil
local results, curTest, testT0 = {}, nil, 0
local pulse = {}
local hits = {}

emu.addMemoryCallback(function()
  if needLoad and stateFile then
    local f = assert(io.open(TRACE .. stateFile, "rb"))
    emu.loadSavestate(f:read("*a")); f:close()
    needLoad = false
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

for _, a in ipairs({ 0x1049, 0x10C9 }) do
  emu.addMemoryCallback(function(addr, value)
    if curTest then
      local st = emu.getState()
      local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
      local lo = pc % 0x10000
      local kind = "other"
      if pc >= 0x80C000 and pc < 0x80C300 then kind = "MELEE"
      elseif pc >= 0x80C300 and pc < 0x80C700 then kind = "PROJ"
      elseif lo >= 0x0D50 and lo <= 0x0D70 then kind = "TICK"
      elseif lo >= 0x0820 and lo <= 0x0870 then kind = "TOSS" end
      hits[#hits + 1] = { pt = t - testT0, addr = addr % 0x10000, v = value, pc = pc,
        kind = kind, a1 = ram(0x1044), a2 = ram(0x10C4), act1 = ram(0x1001), act2 = ram(0x1081) }
    end
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesWorkRam)
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

-- helpers -----------------------------------------------------------------
local function struct(p) return (p == 1) and 0x1000 or 0x1080 end
local function posx(b) return ram(b + 0x21) + 256 * ram(b + 0x22) end
local function setx(b, x) wr(b + 0x21, x % 256); wr(b + 0x22, math.floor(x / 256)) end
local function park(att, range)          -- defender parked `range` px from attacker
  local ab, db = struct(att), struct(3 - att)
  local ax = posx(ab)
  local L = ax <= posx(db)
  setx(db, L and (ax + range) or (ax - range))
  wr(db + 0x49, 0x60); wr(0x800 + (2 - att), 0x60)
end
local function onLeft(att)
  return posx(struct(att)) <= posx(struct(3 - att))
end
local function dirpad(c, L)
  local m = { down = (c == "1" or c == "2" or c == "3"), up = (c == "7" or c == "8" or c == "9") }
  local fwd = (c == "3" or c == "6" or c == "9")
  local back = (c == "1" or c == "4" or c == "7")
  if fwd then if L then m.right = true else m.left = true end end
  if back then if L then m.left = true else m.right = true end end
  return m
end
-- motion driver: from pt0, 3f per step, button on step n+1 (neutral or with last dir)
local function motion(api, player, mstr, btn, pt0, neutralBtn)
  local pt = api.pt
  local L = onLeft(player)
  local sd = math.floor((pt - pt0) / 3) + 1
  if pt >= pt0 and sd <= #mstr then
    pulse[player - 1] = dirpad(mstr:sub(sd, sd), L)
  elseif pt >= pt0 and sd == #mstr + 1 then
    local p = neutralBtn and {} or dirpad(mstr:sub(#mstr, #mstr), L)
    p[btn] = true
    pulse[player - 1] = p
  elseif pt >= pt0 and sd == #mstr + 2 then
    pulse[player - 1] = nil
  end
end
local function total()
  local tot, byk, prev = 0, {}, 0x60
  for _, h in ipairs(hits) do
    local d = prev - h.v; prev = h.v
    if d > 0 then tot = tot + d; byk[h.kind] = (byk[h.kind] or 0) + d end
  end
  return tot, byk
end
local function ck(cond, msg) return cond, msg end

-- ===== test list =====
-- spec: name, group ("base"|"pN"|"stack"), need = fn()->bool|nil, state, dur,
--        frame(api), verdict(api) -> ok, detail
local T = {}
local function add(s) T[#T + 1] = s end

-- Layer 1: base --------------------------------------------------------------
add{ name = "base-damage-determinism", group = "base", state = "uranus_vs_jupiter.mss", dur = 80,
  frame = function(api)
    if api.pt == 5 then park(1, 40) end
    if api.pt >= 30 and api.pt <= 31 then pulse[0] = { x = true } elseif api.pt == 32 then pulse[0] = nil end
  end,
  verdict = function() return ck(#hits == 1 and hits[1].v == 0x58, "5HP idle expects dmg 8, got " .. tostring(hits[1] and (0x60 - hits[1].v))) end }

add{ name = "base-counterhit-minus2col", group = "base", state = "uranus_vs_jupiter.mss", dur = 80,
  frame = function(api)
    if api.pt == 5 then park(1, 40) end
    if api.pt >= 30 and api.pt <= 31 then pulse[0] = { x = true } elseif api.pt == 32 then pulse[0] = nil end
    if api.pt >= 40 and api.pt <= 41 then pulse[1] = { x = true } elseif api.pt == 42 then pulse[1] = nil end
  end,
  verdict = function() return ck(#hits == 1 and 0x60 - hits[1].v == 12, "counter 5HP expects 12, got " .. tostring(hits[1] and (0x60 - hits[1].v))) end }

add{ name = "base-posture-stand", group = "base", state = "uranus_vs_jupiter.mss", dur = 80,
  frame = function(api)
    if api.pt == 5 then park(1, 30) end
    if api.pt >= 26 and api.pt <= 36 then
      local p = { down = true }; if api.pt >= 30 and api.pt <= 31 then p.x = true end
      pulse[0] = p
    elseif api.pt == 37 then pulse[0] = nil end
  end,
  verdict = function() return ck(#hits == 1 and 0x60 - hits[1].v == 5, "2HP vs stand expects 5, got " .. tostring(hits[1] and (0x60 - hits[1].v))) end }

add{ name = "base-posture-crouch", group = "base", state = "uranus_vs_jupiter.mss", dur = 80,
  frame = function(api)
    if api.pt == 5 then park(1, 30) end
    if api.pt >= 6 then pulse[1] = { down = true } end
    if api.pt >= 26 and api.pt <= 36 then
      local p = { down = true }; if api.pt >= 30 and api.pt <= 31 then p.x = true end
      pulse[0] = p
    elseif api.pt == 37 then pulse[0] = nil end
  end,
  verdict = function() return ck(#hits == 1 and 0x60 - hits[1].v == 7, "2HP vs crouch expects 7, got " .. tostring(hits[1] and (0x60 - hits[1].v))) end }

add{ name = "base-proximity-normal", group = "base", state = "uranus_vs_jupiter.mss", dur = 80,
  frame = function(api)
    if api.pt == 5 then park(1, 34) end
    if api.pt >= 30 and api.pt <= 31 then pulse[0] = { x = true } elseif api.pt == 32 then pulse[0] = nil end
  end,
  verdict = function() return ck(#hits == 1 and 0x60 - hits[1].v == 9, "near-5HP expects 9, got " .. tostring(hits[1] and (0x60 - hits[1].v))) end }

add{ name = "base-throw-toss20", group = "base", state = "neptune_vs_jupiter.mss", dur = 120,
  frame = function(api)
    if api.pt == 5 then park(1, 14) end
    if api.pt >= 14 and api.pt <= 17 then
      local p = { x = true }; if onLeft(1) then p.right = true else p.left = true end
      pulse[0] = p
    elseif api.pt == 18 then pulse[0] = nil end
  end,
  verdict = function()
    local tot, byk = total()
    return ck(tot == 20 and (byk.TOSS or 0) == 20 and hits[1] and hits[1].a1 == 0,
      string.format("throw expects TOSS 20 a44=0, got tot=%d toss=%d a44=%02X", tot, byk.TOSS or 0, hits[1] and hits[1].a1 or 255))
  end }

add{ name = "base-desp-jupiter-strike48", group = "base", state = "jupiter_vs_venus_clean.mss", dur = 150,
  frame = function(api)
    if api.pt == 5 then wr(0x1049, 0x10); wr(0x800, 0x10); park(1, 70) end
    motion(api, 1, "2141236", "x", 10, false)
  end,
  verdict = function()
    local tot, byk = total()
    return ck(tot == 48 and #hits == 1 and hits[1].kind == "MELEE",
      string.format("Jupiter desperation expects single MELEE 48, got tot=%d n=%d", tot, #hits))
  end }

add{ name = "base-desp-uranus-hybrid67", group = "base", state = "uranus_vs_jupiter.mss", dur = 380,
  frame = function(api)
    if api.pt == 5 then wr(0x1049, 0x10); wr(0x800, 0x10); park(1, 70) end
    motion(api, 1, "632141236", "a", 10, false)
  end,
  verdict = function()
    local tot, byk = total()
    return ck(tot == 67 and (byk.TOSS or 0) == 32,
      string.format("Uranus desperation expects 67 with TOSS 32, got tot=%d toss=%d", tot, byk.TOSS or 0))
  end }

add{ name = "base-desp-pluto-drain48", group = "base", state = "pluto_vs_1.mss", dur = 260,
  frame = function(api)
    if api.pt == 5 then wr(0x1049, 0x10); wr(0x800, 0x10); park(1, 70) end
    motion(api, 1, "632146", "x", 10, false)
  end,
  verdict = function()
    local tot, byk = total()
    local ticks = 0
    for _, h in ipairs(hits) do if h.kind == "TICK" then ticks = ticks + 1 end end
    return ck(tot == 48 and ticks >= 10,
      string.format("Pluto desperation expects 48 with >=10 ticks, got tot=%d ticks=%d", tot, ticks))
  end }

add{ name = "base-desp-neptune-input37", group = "base", state = "neptune_vs_jupiter.mss", dur = 150,
  frame = function(api)
    if api.pt == 5 then wr(0x1049, 0x10); wr(0x800, 0x10); park(1, 60) end
    motion(api, 1, "6236236", "x", 10, true)
  end,
  verdict = function()
    local tot = total()
    return ck(tot == 37 and #hits == 1, string.format("Neptune desperation expects single 37, got tot=%d n=%d", tot, #hits))
  end }

-- dash distance / cancel gate: measured, expectation switches on p5/p1
local dashMeas = {}
add{ name = "base-dash-distance", group = "base", state = "uranus_vs_jupiter.mss", dur = 140,
  frame = function(api)
    if api.pt == 5 then park(1, 200) end
    if api.pt == 10 then dashMeas.x0 = posx(0x1000) end
    if api.pt == 12 or api.pt == 16 then pulse[0] = { [onLeft(1) and "right" or "left"] = true }
    elseif api.pt == 13 or api.pt == 17 then pulse[0] = nil end
    if api.pt == 120 then dashMeas.x1 = posx(0x1000) end
  end,
  verdict = function()
    local d = math.abs((dashMeas.x1 or 0) - (dashMeas.x0 or 0))
    local exp = has.p5 and 89 or 145
    return ck(math.abs(d - exp) <= 4, string.format("dash distance expects ~%d (p5=%s), got %d", exp, tostring(has.p5), d))
  end }

-- Layer 2: patch-specific ----------------------------------------------------
add{ name = "p7-pluto5hp-vs-croucher", group = "p7", need = function() return true end,  -- dual-mode (Mercury: vanilla whiffs, p7 hits)
  state = "pluto_vs_2.mss", dur = 90,
  frame = function(api)
    if api.pt == 5 then park(1, 30) end
    if api.pt >= 6 then pulse[1] = { down = true } end
    if api.pt >= 20 and api.pt <= 21 then local p = { x = true, down = false }; pulse[0] = p
    elseif api.pt == 22 then pulse[0] = nil end
  end,
  verdict = function()
    if has.p7 then return ck(#hits >= 1, "p7 present: Pluto 5HP must hit crouching Mercury, got no hits")
    else return ck(#hits == 0, "p7 absent: Pluto 5HP must whiff on crouching Mercury, got " .. #hits .. " hits") end
  end }

add{ name = "p7-chibi-still-whiffs", group = "p7", need = function() return has.p7 end,
  state = "pluto_vs_chibi_v07.mss", dur = 90,
  frame = function(api)
    if api.pt == 5 then park(1, 30) end
    if api.pt >= 6 then pulse[1] = { down = true } end
    if api.pt >= 20 and api.pt <= 21 then pulse[0] = { x = true }
    elseif api.pt == 22 then pulse[0] = nil end
  end,
  verdict = function()
    return ck(#hits == 0, "p7 default h=62: crouching Chibi must still whiff, got " .. #hits .. " hits")
  end }

add{ name = "p10-combo-counter", group = "p10", need = function() return has.p10 end,
  state = "uranus_vs_jupiter.mss", dur = 90,
  frame = function(api)
    if api.pt == 5 then park(1, 40); wr(0x8B0, 0) end
    if api.pt >= 30 and api.pt <= 31 then pulse[0] = { x = true } elseif api.pt == 32 then pulse[0] = nil end
  end,
  verdict = function() return ck(ram(0x8B0) >= 1, "combo counter $08B0 expects >=1 after hit, got " .. ram(0x8B0)) end }

add{ name = "p11-menu-toggle", group = "p11", need = function() return has.p11 end,
  state = "training_p11.mss", dur = 80,
  frame = function(api)
    if api.pt >= 20 and api.pt <= 22 then pulse[0] = { l = true, r = true } elseif api.pt == 23 then pulse[0] = nil end
  end,
  verdict = function() return ck(ram(0x1F005) == 1, "L+R expects MENUOPEN=1, got " .. ram(0x1F005)) end }

add{ name = "p12-taunt-nominal", group = "p12", need = function() return has.p12 end,
  state = "uranus_vs_jupiter.mss", dur = 160,
  frame = function(api)
    if api.pt == 5 then park(1, 120) end
    if api.pt >= 20 and api.pt <= 21 then pulse[0] = { l = true } elseif api.pt == 22 then pulse[0] = nil end
    if api.pt >= 23 then
      local a = ram(0x1001)
      if a == 0x65 or a == 0x66 then api.mem.taunted = true end
      if api.mem.taunted and a == 0x2A then api.mem.tail = true end
    end
  end,
  verdict = function(api) return ck(api.mem.taunted and api.mem.tail, "L expects Uranus misfire act 65/66 then 0x2A tail") end }

add{ name = "p12-taunt-Rheld-excluded", group = "p12", need = function() return has.p12 end,
  state = "uranus_vs_jupiter.mss", dur = 80,
  frame = function(api)
    if api.pt == 5 then park(1, 120) end
    if api.pt >= 20 and api.pt <= 22 then pulse[0] = { l = true, r = true } elseif api.pt == 23 then pulse[0] = nil end
    if api.pt >= 23 then
      local a = ram(0x1001)
      if a == 0x65 or a == 0x66 then api.mem.taunted = true end
    end
  end,
  verdict = function(api) return ck(not api.mem.taunted, "L+R must NOT taunt (p11 menu combo / R exclusion)") end }

add{ name = "p12-taunt-actgate-edge", group = "p12", need = function() return has.p12 end,
  state = "uranus_vs_jupiter.mss", dur = 90,
  frame = function(api)
    if api.pt == 5 then park(1, 120) end
    if api.pt >= 20 and api.pt <= 30 then
      local p = { down = true }
      if api.pt >= 22 and api.pt <= 23 then p.x = true end   -- 2HP
      if api.pt >= 27 and api.pt <= 28 then p.l = true end   -- L during the attack act
      pulse[0] = p
    elseif api.pt == 31 then pulse[0] = nil end
    if api.pt >= 24 then
      local a = ram(0x1001)
      if a == 0x65 or a == 0x66 then api.mem.taunted = true end
    end
  end,
  verdict = function(api) return ck(not api.mem.taunted, "L during 2HP act must not taunt") end }

add{ name = "p13-grant-and-interrupt", group = "p13", need = function() return has.p12 and has.p13 end,
  state = "uranus_vs_jupiter.mss", dur = 400,
  frame = function(api)
    -- phase A (pt 5-200): P2 taunts uninterrupted -> LV2 == 1
    if api.pt == 5 then park(1, 120); wr(0x1F800, 0xA5); wr(0x1F802, 0) end
    if api.pt >= 20 and api.pt <= 21 then pulse[1] = { l = true } elseif api.pt == 22 then pulse[1] = nil end
    if api.pt == 200 then api.mem.lvA = ram(0x1F802) end
    -- phase B (pt 210+): P2 taunts, P1 interrupts with 5HP -> LV stays
    if api.pt == 210 then park(1, 40); wr(0x1F802, 0) end
    if api.pt >= 214 and api.pt <= 215 then pulse[1] = { l = true } elseif api.pt == 216 then pulse[1] = nil end
    if api.pt >= 220 and api.pt <= 221 then pulse[0] = { x = true } elseif api.pt == 222 then pulse[0] = nil end
    if api.pt == 390 then api.mem.lvB = ram(0x1F802) end
  end,
  verdict = function(api)
    return ck(api.mem.lvA == 1 and api.mem.lvB == 0,
      string.format("grant expects LV 1 then interrupt 0, got %s/%s", tostring(api.mem.lvA), tostring(api.mem.lvB)))
  end }

add{ name = "p13-desp-scaled-L3", group = "p13", need = function() return has.p13 end,
  state = "jupiter_vs_venus_clean.mss", dur = 150,
  frame = function(api)
    if api.pt == 5 then wr(0x1049, 0x10); wr(0x800, 0x10); park(1, 70); wr(0x1F800, 0xA5); wr(0x1F802, 3) end
    motion(api, 1, "2141236", "x", 10, false)
  end,
  verdict = function()
    local tot = total()
    return ck(tot == 19, "Jupiter desperation at defender L3 expects 19, got " .. tot)
  end }

add{ name = "p13-throw-exempt-L3", group = "p13", need = function() return has.p13 end,
  state = "neptune_vs_jupiter.mss", dur = 120,
  frame = function(api)
    if api.pt == 5 then park(1, 14); wr(0x1F800, 0xA5); wr(0x1F802, 3) end
    if api.pt >= 14 and api.pt <= 17 then
      local p = { x = true }; if onLeft(1) then p.right = true else p.left = true end
      pulse[0] = p
    elseif api.pt == 18 then pulse[0] = nil end
  end,
  verdict = function()
    local tot, byk = total()
    return ck(tot == 20 and (byk.TOSS or 0) == 20, "normal throw at L3 must stay 20, got " .. tot)
  end }

add{ name = "p13-uranus-toss-scaled", group = "p13", need = function() return has.p13 end,
  state = "uranus_vs_jupiter.mss", dur = 380,
  frame = function(api)
    if api.pt == 5 then wr(0x1049, 0x10); wr(0x800, 0x10); park(1, 70); wr(0x1F800, 0xA5); wr(0x1F802, 3) end
    motion(api, 1, "632141236", "a", 10, false)
  end,
  verdict = function()
    local tot, byk = total()
    return ck(tot == 34 and (byk.TOSS or 0) == 13,
      string.format("Uranus desperation at L3 expects 34 (toss 13), got %d (toss %d)", tot, byk.TOSS or 0))
  end }

add{ name = "p13-pluto-ticks-scaled", group = "p13", need = function() return has.p13 end,
  state = "pluto_vs_1.mss", dur = 260,
  frame = function(api)
    if api.pt == 5 then wr(0x1049, 0x10); wr(0x800, 0x10); park(1, 70); wr(0x1F800, 0xA5); wr(0x1F802, 3) end
    motion(api, 1, "632146", "x", 10, false)
  end,
  verdict = function()
    local tot = total()
    return ck(tot == 19, "Pluto desperation at defender L3 expects 19, got " .. tot)
  end }

add{ name = "stack-counterhit-x-guts-72to29", group = "stack", need = function() return has.p12 and has.p13 end,
  state = "jupiter_vs_venus_clean.mss", dur = 150,
  frame = function(api)
    if api.pt == 5 then wr(0x1049, 0x10); wr(0x800, 0x10); park(1, 70); wr(0x1F800, 0xA5); wr(0x1F802, 3) end
    if api.pt >= 45 and api.pt <= 46 then pulse[1] = { l = true } elseif api.pt == 47 then pulse[1] = nil end
    motion(api, 1, "2141236", "x", 10, false)
  end,
  verdict = function()
    local tot = total()
    return ck(tot == 29, "countered desperation (72) at L3 expects 29 (v3.3 wide tables), got " .. tot)
  end }


add{ name = "base-desp-moon-proj48", group = "base", state = "moon_vs_moon.mss", dur = 160,
  frame = function(api)
    if api.pt == 5 then wr(0x1049, 0x10); wr(0x800, 0x10); park(1, 40) end
    motion(api, 1, "2363214", "a", 10, true)
  end,
  verdict = function()
    local tot, byk = total()
    return ck(tot == 48 and (byk.PROJ or 0) == 48, string.format("Moon desperation expects PROJ 48, got tot=%d proj=%d", tot, byk.PROJ or 0))
  end }

add{ name = "base-desp-mercury-strike48", group = "base", state = "pluto_vs_2.mss", dur = 150,
  frame = function(api)
    if api.pt == 5 then wr(0x10C9, 0x10); wr(0x801, 0x10); park(2, 70) end
    motion(api, 2, "632146", "a", 10, false)
  end,
  verdict = function()
    local tot = total()
    return ck(tot == 48 and #hits == 1, string.format("Mercury desperation expects single 48, got tot=%d n=%d", tot, #hits))
  end }

add{ name = "base-desp-mars-proj32", group = "base", state = "pluto_vs_3.mss", dur = 150,
  frame = function(api)
    if api.pt == 5 then wr(0x10C9, 0x10); wr(0x801, 0x10); park(2, 70) end
    motion(api, 2, "6321412", "a", 10, false)
  end,
  verdict = function()
    local tot, byk = total()
    return ck(tot == 32 and (byk.PROJ or 0) == 32, string.format("Mars desperation expects PROJ 32, got tot=%d proj=%d", tot, byk.PROJ or 0))
  end }

add{ name = "base-desp-venus-strike37", group = "base", state = "venus_vs_jupiter_clean.mss", dur = 150,
  frame = function(api)
    if api.pt == 5 then wr(0x1049, 0x10); wr(0x800, 0x10); park(1, 70) end
    motion(api, 1, "4123632", "x", 10, false)
  end,
  verdict = function()
    local tot = total()
    return ck(tot == 37 and #hits == 1, string.format("Venus desperation expects single 37, got tot=%d n=%d", tot, #hits))
  end }

add{ name = "base-desp-chibi-air52", group = "base", state = "pluto_vs_chibi_v07.mss", dur = 220,
  frame = function(api)
    if api.pt == 5 then wr(0x10C9, 0x10); wr(0x801, 0x10); park(2, 50) end
    if api.pt >= 10 and api.pt <= 12 then pulse[1] = { up = true } elseif api.pt == 13 then pulse[1] = nil end
    if api.pt >= 22 then motion(api, 2, "63214", "x", 22, false) end
  end,
  verdict = function()
    local tot, byk = total()
    return ck(tot == 52 and (byk.PROJ or 0) == 52, string.format("Chibi air desperation expects PROJ 52, got tot=%d proj=%d", tot, byk.PROJ or 0))
  end }

add{ name = "base-desp-uranus-crouch51", group = "base", state = "uranus_vs_jupiter.mss", dur = 380,
  frame = function(api)
    if api.pt == 5 then wr(0x1049, 0x10); wr(0x800, 0x10); park(1, 70) end
    if api.pt >= 6 then pulse[1] = { down = true } end
    motion(api, 1, "632141236", "a", 10, false)
  end,
  verdict = function()
    local tot, byk = total()
    return ck(tot == 51 and (byk.TOSS or 0) == 32,
      string.format("Uranus desperation vs crouch expects 51 (toss 32, fewer rush hits), got %d (toss %d)", tot, byk.TOSS or 0))
  end }

add{ name = "base-desp-mercury-crouch62", group = "base", state = "pluto_vs_2.mss", dur = 150,
  frame = function(api)
    if api.pt == 5 then wr(0x10C9, 0x10); wr(0x801, 0x10); park(2, 70) end
    if api.pt >= 6 then pulse[0] = { down = true } end
    motion(api, 2, "632146", "a", 10, false)
  end,
  verdict = function()
    local tot = total()
    return ck(tot == 62, "Mercury desperation vs crouch expects 62 (crouch column shift), got " .. tot)
  end }

add{ name = "base-desp-chibi-crouch24", group = "base", state = "pluto_vs_chibi_v07.mss", dur = 220,
  frame = function(api)
    if api.pt == 5 then wr(0x10C9, 0x10); wr(0x801, 0x10); park(2, 50) end
    if api.pt >= 6 and api.pt > 13 then pulse[0] = { down = true } end
    if api.pt >= 6 and api.pt <= 13 then pulse[0] = { down = true } end
    if api.pt >= 10 and api.pt <= 12 then pulse[1] = { up = true } elseif api.pt == 13 then pulse[1] = nil end
    if api.pt >= 22 then motion(api, 2, "63214", "x", 22, false) end
  end,
  verdict = function()
    local tot = total()
    return ck(tot == 24, "Chibi air desperation vs crouch expects 24 (hits whiff), got " .. tot)
  end }

add{ name = "base-throwtech-early-mash", group = "base", state = "venus_vs_jupiter_clean.mss", dur = 120,
  frame = function(api)
    if api.pt == 5 then park(1, 14) end
    if api.pt >= 14 and api.pt <= 17 then
      local p = { x = true }; if onLeft(1) then p.right = true else p.left = true end
      pulse[0] = p
    elseif api.pt == 18 then pulse[0] = nil end
    if not api.mem.grabT and ram(0x1081) == 0x1C then api.mem.grabT = api.pt end
    local g = api.mem.grabT
    if g and api.pt >= g + 4 and api.pt <= g + 14 then
      pulse[1] = (api.pt % 2 == 0) and { y = true } or { b = true, a = true }
    elseif g and api.pt == g + 15 then pulse[1] = nil end
  end,
  verdict = function()
    local ok = #hits == 1 and hits[1].pc % 0x10000 >= 0x850
    return ck(ok, "early mash (grab+4) expects TECH escape, got " .. (#hits > 0 and string.format("pc=%04X", hits[1].pc % 0x10000) or "no writes"))
  end }

add{ name = "p8-tech-window-late-mash", group = "p8", need = function() return true end,  -- dual-mode
  state = "venus_vs_jupiter_clean.mss", dur = 120,
  frame = function(api)
    if api.pt == 5 then park(1, 14) end
    if api.pt >= 14 and api.pt <= 17 then
      local p = { x = true }; if onLeft(1) then p.right = true else p.left = true end
      pulse[0] = p
    elseif api.pt == 18 then pulse[0] = nil end
    if not api.mem.grabT and ram(0x1081) == 0x1C then api.mem.grabT = api.pt end
    local g = api.mem.grabT
    if g and api.pt >= g + 14 and api.pt <= g + 24 then
      pulse[1] = (api.pt % 2 == 0) and { y = true } or { b = true, a = true }
    elseif g and api.pt == g + 25 then pulse[1] = nil end
  end,
  verdict = function()
    if #hits ~= 1 then return ck(false, "expected exactly one throw resolution write, got " .. #hits) end
    local tech = hits[1].pc % 0x10000 >= 0x850
    if has.p8 then return ck(tech, "p8 present: mash at grab+14 must TECH (13f window), got TOSS")
    else return ck(not tech, "p8 absent: mash at grab+14 must be too late (6f-ish window), got TECH") end
  end }

add{ name = "p11-p1hp-low-toggle", group = "p11", need = function() return has.p11 end,
  state = "training_p11.mss", dur = 220,
  frame = function(api)
    if api.pt >= 10 and api.pt <= 12 then pulse[0] = { l = true, r = true } elseif api.pt == 13 then pulse[0] = nil end
    -- cursor starts at row 1: 10 downs at 12f pace (30Hz-safe edges), then right = LOW
    local dn = math.floor((api.pt - 50) / 12)
    if api.pt >= 50 and api.pt < 170 and (api.pt - 50) % 12 < 2 and dn < 10 then pulse[0] = { down = true }
    elseif api.pt >= 50 and api.pt < 170 then pulse[0] = nil end
    if api.pt >= 180 and api.pt <= 181 then pulse[0] = { right = true } elseif api.pt == 182 then pulse[0] = nil end
  end,
  verdict = function()
    return ck(ram(0x1049) == 0x17, string.format("P1 HP LOW expects $1049=0x17, got %02X", ram(0x1049)))
  end }

add{ name = "p13-round-reset-clears-levels", group = "p13", need = function() return has.p13 end,
  state = "uranus_vs_jupiter.mss", dur = 900,
  frame = function(api)
    if api.pt == 5 then
      park(1, 30)
      wr(0x10C9, 0x02); wr(0x801, 0x02)
      wr(0x1F800, 0xA5); wr(0x1F802, 3)
    end
    if api.pt >= 26 and api.pt <= 36 then
      local p = { down = true }; if api.pt >= 30 and api.pt <= 31 then p.x = true end
      pulse[0] = p
    elseif api.pt == 37 then pulse[0] = nil end
    if api.pt > 100 and not api.mem.newRound then
      if ram(0x10C9) == 0x60 and ram(0x1081) == 0 and ram(0x1001) == 0 then
        api.mem.newRound = api.pt
      end
    end
    if api.mem.newRound and api.pt == api.mem.newRound + 60 then
      api.mem.lvAfter = ram(0x1F802)
    end
  end,
  verdict = function(api)
    return ck(api.mem.newRound and api.mem.lvAfter == 0,
      string.format("round reset expects LV cleared, newRound=%s lv=%s", tostring(api.mem.newRound), tostring(api.mem.lvAfter)))
  end }

-- ===== runner =====
local idx, phase, settle = 0, "boot", 0
emu.addEventCallback(function()
  t = t + 1
  if t == 0 then
    -- static layer
    log("=== regression run ===")
    for pn, sig in pairs(SIGS) do
      local ok = true
      for _, s in ipairs(sig) do if rom(s[1]) ~= s[2] then ok = false break end end
      has[pn] = ok
    end
    local det = {}
    for i = 1, 13 do det[#det + 1] = "p" .. i .. "=" .. (has["p" .. i] and "Y" or "-") end
    log("detect: " .. table.concat(det, " "))
    local nfail = 0
    for r, exp in pairs(MATRIX_ROWS) do
      for c = 0, 15 do
        if rom(0xD081 + r * 16 + c) ~= exp[c + 1] then nfail = nfail + 1 end
      end
    end
    results[#results + 1] = { name = "static-matrix-integrity", ok = nfail == 0, msg = nfail .. " byte mismatches" }
    log(string.format("%s static-matrix-integrity", nfail == 0 and "PASS" or "FAIL"))
    if EXPECT == "clean" then
      local any = false
      for i = 1, 13 do if has["p" .. i] then any = true end end
      results[#results + 1] = { name = "static-expect-clean", ok = not any, msg = "patches detected on clean ROM" }
    elseif EXPECT == "all" then
      local all = true
      for i = 1, 13 do if not has["p" .. i] then all = false end end
      results[#results + 1] = { name = "static-expect-all", ok = all, msg = "missing patches on all-patches ROM" }
    end
    phase = "next"
  end
  if phase == "next" then
    idx = idx + 1
    while T[idx] and ((T[idx].need and not T[idx].need()) or (ONLY and not T[idx].name:find(ONLY, 1, true))) do
      if not (ONLY and not T[idx].name:find(ONLY, 1, true)) then
        log("SKIP " .. T[idx].name .. " (patch absent)")
      end
      idx = idx + 1
    end
    if not T[idx] then
      local np, nf = 0, 0
      for _, r in ipairs(results) do if r.ok then np = np + 1 else nf = nf + 1; log("  FAILED: " .. r.name .. " — " .. r.msg) end end
      log(nf == 0 and ("ALL PASS (" .. np .. ")") or ("FAILURES (" .. nf .. "/" .. (np + nf) .. ")"))
      emu.stop(0); return
    end
    stateFile = T[idx].state; needLoad = true
    phase = "settle"; settle = 0
    return
  end
  if phase == "settle" then
    settle = settle + 1
    if not needLoad and settle >= 3 then
      phase = "run"; testT0 = t; hits = {}; pulse = {}
      curTest = T[idx]; curTest.mem = {}
    end
    return
  end
  if phase == "run" then
    local api = { pt = t - testT0, mem = curTest.mem }
    curTest.frame(api)
    if api.pt >= curTest.dur then
      local ok, msg = curTest.verdict({ pt = api.pt, mem = curTest.mem })
      results[#results + 1] = { name = curTest.name, ok = ok, msg = msg or "" }
      log(string.format("%s %s%s", ok and "PASS" or "FAIL", curTest.name, ok and "" or (" — " .. (msg or ""))))
      curTest = nil; pulse = {}
      phase = "next"
    end
  end
end, emu.eventType.endFrame)
print("test_regression loaded")
