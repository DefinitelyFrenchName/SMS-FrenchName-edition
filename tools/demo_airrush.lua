-- demo_airrush.lua — the anime-fighter feasibility DEMO: one scripted
-- sequence exercising every Phase 2-6 mechanism, no pokes anywhere.
--
--   ROM=build/exp_anime_stack.sfc tools/run.sh tools/demo_airrush.lua 120
--   -> traces/demo_airrush.txt
--
-- The string (Uranus vs a jumping Jupiter, fixture uranus_vs_jupiter_clean):
--   1. 5HP anti-air         -> victim launched into air hitstun, TARGETABLE
--                              (exp_juggle: +0x46=0x20, not 0xA0)
--   2. jump + 66            -> AIR FRONT DASH chase (11 px/f — a plain jump
--                              cannot close on the launch drift; measured)
--   3. HP during the dash   -> DASH-CANCEL j.HP, connecting on the floating
--                              victim = the JUGGLE hit
--   4. 66 during that hit   -> GATLING second air dash (budget 2)
--   5. land                 -> budget resets (exp_aircounter)
--
-- Success = at least TWO airborne hits on the victim in one sequence plus
-- the gatling dash and the dash-cancel normal, all visible in the trace.
-- Knobs: SMS_D1 (anti-air press, default 12), SMS_D2 (chase j.HP press,
-- default 10), SMS_JD (frames after launch before the chase jump, default 4).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local D1 = tonumber(os.getenv("SMS_D1") or "12")
local D2 = tonumber(os.getenv("SMS_D2") or "10")
local JD = tonumber(os.getenv("SMS_JD") or "4")
local LOG = assert(io.open(ENV.TRACE .. "demo_airrush.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local STATE = "uranus_vs_jupiter_clean.mss"
local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local rows = {}

local function r(base, o) return PL.ram(base + o) end
local function x16(base) return r(base, 0x21) + 256 * r(base, 0x22) end
local function air(base) return (r(base, 0x16) & 0x80) == 0 end
local function fwdDir() return x16(P1) < x16(P2) and "right" or "left" end
local function setPhase(p)
  log(string.format("t=%4d  %-9s -> %-9s (a:%02X v:%02X vy=%d ctr=%02X)",
      t, phase, p, r(P1, 0x01), r(P2, 0x01), r(P2, 0x25), r(P1, 0x7F)))
  phase, phaseStart = p, t
end

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("demo_airrush: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  local k, b1, b2 = t - phaseStart, {}, {}
  local fwd = fwdDir()
  if phase == "approach" then
    b1[fwd] = true
  elseif phase == "vjump" then
    if k < 6 then b2.up = true end
  elseif phase == "antiair" then
    if k >= D1 and k < D1 + 4 then b1.x = true end
  elseif phase == "chase" then
    if k < 6 then b1.up = true; b1[fwd] = true end
  elseif phase == "dash66" then
    if (k >= 0 and k < 5) or (k >= 9 and k < 14) then b1[fwd] = true end
  elseif phase == "cancel" then
    if k >= D2 and k < D2 + 4 then b1.x = true end
  elseif phase == "tap66b" then
    if (k >= 2 and k < 6) or (k >= 10 and k < 14) then b1[fwd] = true end
  end
  emu.setInput(PL.pad(b1), 0, 0)
  emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)

local function snap()
  return string.format("t=%4d | a.act=%02X stp=%02X st=%02X y=%3d x=%4d ctr=%02X 43=%02X | v.act=%02X st=%02X 46=%02X hp=%3d y=%3d x=%4d hst=%02X",
      t, r(P1, 0x01), r(P1, 0x02), r(P1, 0x16), r(P1, 0x25), x16(P1), r(P1, 0x7F), r(P1, 0x43),
      r(P2, 0x01), r(P2, 0x16), r(P2, 0x46), r(P2, 0x49), r(P2, 0x25), x16(P2), r(P2, 0x4D))
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  local va, aa = r(P2, 0x01), r(P1, 0x01)
  if phase ~= "settle" and phase ~= "report" then rows[#rows + 1] = snap() end

  if phase == "settle" then
    if k > 70 then setPhase("approach") end
  elseif phase == "approach" then
    if math.abs(x16(P1) - x16(P2)) <= 44 then setPhase("vjump")
    elseif k > 150 then log("SETUP-FAIL approach"); LOG:close(); emu.stop(1) end
  elseif phase == "vjump" then
    if k > 2 and air(P2) then setPhase("antiair")
    elseif k > 30 then log("SETUP-FAIL victim jump"); LOG:close(); emu.stop(1) end
  elseif phase == "antiair" then
    if va >= 0x0E and va <= 0x20 and air(P2) then setPhase("wait1") end
    if k > D1 + 45 then log("SETUP-FAIL anti-air whiffed"); LOG:close(); emu.stop(1) end
  elseif phase == "wait1" then
    -- wait out the launcher's recovery, then chase
    if aa == 0x00 or aa == 0x01 then
      if k >= JD then setPhase("chase") end
    end
    if k > 60 then setPhase("chase") end
  elseif phase == "chase" then
    if k > 2 and air(P1) then setPhase("dash66")
    elseif k > 30 then log("SETUP-FAIL chase jump"); LOG:close(); emu.stop(1) end
  elseif phase == "dash66" then
    if aa == 0x2C then setPhase("cancel") end
    if k > 40 then setPhase("landout") end
  elseif phase == "cancel" then
    if aa == 0x50 then setPhase("tap66b") end
    if k > D2 + 25 then setPhase("landout") end
  elseif phase == "tap66b" then
    if k > 25 then setPhase("landout") end
  elseif phase == "landout" then
    if (not air(P1)) and aa == 0x00 then setPhase("report") end
    if k > 90 then setPhase("report") end
  elseif phase == "report" then
    log("")
    for _, s in ipairs(rows) do log("   " .. s) end
    log("")
    -- verdicts
    local hits, prevHst, prevHP = {}, 0, nil
    local gatling, cancelHP, juggleHit = nil, nil, nil
    local prevA = nil
    for _, s in ipairs(rows) do
      local tt = tonumber(s:match("t=%s*(%d+)"))
      local aact = tonumber(s:match("a%.act=(%x+)"), 16)
      local vhp = tonumber(s:match("hp=%s*(%d+)"))
      local vst = tonumber(s:match("v%.act=%x+ st=(%x+)"), 16)
      if prevHP and vhp < prevHP then
        hits[#hits + 1] = { t = tt, air = (vst & 0x80) == 0 }
        if #hits >= 2 and (vst & 0x80) == 0 then juggleHit = juggleHit or tt end
      end
      if (aact == 0x2B or aact == 0x2C) and prevA == 0x50 then gatling = gatling or tt end
      if aact == 0x50 and prevA and (prevA == 0x2B or prevA == 0x2C) then cancelHP = cancelHP or tt end
      prevHP, prevA = vhp, aact
    end
    log("== DEMO VERDICT ==")
    local airhits = 0
    for _, h in ipairs(hits) do if h.air then airhits = airhits + 1 end end
    log(string.format("   hits on the victim: %d (%d airborne)", #hits, airhits))
    for i, h in ipairs(hits) do log(string.format("     hit %d at t=%d airborne=%s", i, h.t, tostring(h.air))) end
    log(string.format("   JUGGLE (2nd+ hit on airborne victim): %s", juggleHit and ("t=" .. juggleHit) or "NO"))
    log(string.format("   GATLING (j.HP -> air dash):           %s", gatling and ("t=" .. gatling) or "NO"))
    log(string.format("   DASH-CANCEL (air dash -> j.HP):       %s", cancelHP and ("t=" .. cancelHP) or "NO"))
    LOG:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("demo_airrush loaded")
