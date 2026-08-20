-- probe_juggle.lua — CAN AN AIRBORNE VICTIM BE RE-HIT? (Phase 0 of the
-- anime-fighter feasibility programme; the juggle kill-shot.)
--
--   SMS_MODE=clean  SMS_HITDELAY=12 tools/run.sh tools/probe_juggle.lua 90
--   SMS_MODE=poke20 SMS_HITDELAY=12 tools/run.sh tools/probe_juggle.lua 90
--   SMS_MODE=poke00 SMS_HITDELAY=12 tools/run.sh tools/probe_juggle.lua 90
--   -> traces/juggle_<mode>_d<delay>.txt
--
-- Setup: Venus (P1) anti-airs a neutral-jumping Jupiter (P2), which launches
-- him (the AIR posture reaction path sets +0x46=0xA0 = untargetable). Then P1
-- mashes jabs at the airborne victim. SPACING IS HELD BY THE HARNESS: during
-- the launch the victim's X is pinned at jab range from the attacker in EVERY
-- mode, so range is identical across runs and the only variable between the
-- control and the poke runs is +0x46 (first attempt whiffed by drift — the
-- launch carries the victim away at ~2 px/f, faster than Venus walks).
--   clean  : NEGATIVE CONTROL — the model says no re-hit resolves. If one
--            does, the +0x46 gate model is WRONG; stop and re-derive.
--   poke20 : after launch is confirmed, victim +0x46 is held at 0x20
--            (the grounded-hit flag value) — does a re-hit resolve now?
--   poke00 : same, held at 0x00.
-- A re-hit is only believed on VICTIM-side evidence: a fresh hitstop edge or
-- an HP drop (the attacker's +0x43 latch persists for the whole launcher act
-- and misfired the first draft's detector).
-- The probe also logs the +0x46 lifecycle at frame granularity in every mode
-- (M0.1) and the reaction act + altitude at first contact (feeds M0.4 via
-- SMS_HITDELAY sweeps).
--
-- Preconditions asserted, not assumed (HANDOFF trap 9): mode byte $8D must be
-- 1 (2P VS — P2's pad must be live to jump), the approach must actually close
-- to SMS_DIST, and the first contact must land on an AIRBORNE victim (+0x16
-- bit7 clear) or the run reports SETUP-FAIL rather than a verdict.
-- Harness shape per probe_exp_airdash.lua: state loaded from the $80:8353
-- exec anchor, inputs written in inputPolled, port is setInput's THIRD arg.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")

local MODE = os.getenv("SMS_MODE") or "clean"        -- clean | poke20 | poke00
local HITDELAY = tonumber(os.getenv("SMS_HITDELAY") or "12")
local DIST = tonumber(os.getenv("SMS_DIST") or "40") -- approach: |x1-x2| <= DIST
local BTN = os.getenv("SMS_LAUNCHER") or "x"         -- x = HP (Y=LP X=HP B=LK A=HK)
local REHIT = os.getenv("SMS_REHIT") or "y"          -- jab mash button
local STATE = os.getenv("SMS_STATE") or "venus_vs_jupiter_clean.mss"
local POKEVAL = MODE == "poke20" and 0x20 or MODE == "poke00" and 0x00 or nil
local PIN = (os.getenv("SMS_PIN") or "1") ~= "0"   -- 0 = natural arc (altitude census / free juggle)

local LOG = assert(io.open(ENV.TRACE .. string.format("juggle_%s_d%d%s.txt", MODE, HITDELAY, PIN and "" or "_free"), "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local ACT, STEP, STATUS, X, XH, Y, HP, F46, F43, HSTOP = 0x01, 0x02, 0x16, 0x21, 0x22, 0x25, 0x49, 0x46, 0x43, 0x4D
local function r(base, o) return PL.ram(base + o) end
local function x16(base) return r(base, X) + 256 * r(base, XH) end
local function airborne(base) return (r(base, STATUS) & 0x80) == 0 end
local function isReact(a) return a >= 0x0E and a <= 0x20 end

local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local rows = {}                -- per-frame victim log from the jump onward
local contact = nil            -- first-hit record
local jabs = {}                -- re-hit attempt records
local rehits = {}              -- resolved re-hits
local hp0 = nil                -- victim HP before the launcher
local hpAfterLaunch = nil
local poking = false
local jabFrame = -999
local landFrame = nil
local fwdSign = 1                -- +1: victim held to the attacker's right
local prevHstop, prevHP = 0, nil

local function setPhase(p)
  log(string.format("t=%4d  %s -> %s  (p1 act=%02X p2 act=%02X p2 y=%d dist=%d)",
      t, phase, p, r(P1, ACT), r(P2, ACT), r(P2, Y), math.abs(x16(P1) - x16(P2))))
  phase, phaseStart = p, t
end

-- ---------------------------------------------------------------- load --
emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_juggle: cannot open " .. ENV.TRACE .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

-- --------------------------------------------------------------- input --
local function fwdDir()  -- toward the opponent, by position
  return x16(P1) < x16(P2) and "right" or "left"
end
emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  local b1, b2 = {}, {}
  if phase == "approach" then
    b1[fwdDir()] = true
  elseif phase == "jump" and k < 6 then
    b2.up = true
  elseif phase == "arm" then
    if k >= HITDELAY and k < HITDELAY + 4 then b1[BTN] = true end
  elseif phase == "watch" then
    -- walk in and mash jabs at the launched victim
    if contact then
      b1[fwdDir()] = true
      if (k % 10) < 4 then b1[REHIT] = true end
    end
  end
  emu.setInput(PL.pad(b1), 0, 0)
  emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)

-- ------------------------------------------------------------ per-frame --
local function snap()
  return { t = t, act = r(P2, ACT), step = r(P2, STEP), st = r(P2, STATUS),
           y = r(P2, Y), x = x16(P2), f46 = r(P2, F46), hp = r(P2, HP),
           a_act = r(P1, ACT), a_43 = r(P1, F43), a_x = x16(P1),
           hst = r(P2, HSTOP) }
end
local function fmt(s)
  return string.format("t=%4d v.act=%02X stp=%02X st=%02X 46=%02X hp=%3d y=%3d x=%4d hstop=%02X | a.act=%02X 43=%02X x=%4d",
      s.t, s.act, s.step, s.st, s.f46, s.hp, s.y, s.x, s.hst, s.a_act, s.a_43, s.a_x)
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart

  if phase == "settle" then
    if k == 5 then
      local md = PL.ram(0x008D)
      log(string.format("mode byte $8D=%02X  (need 01 = 2P VS)", md))
      if md ~= 1 then log("SETUP-FAIL: not 2P VS — P2 pad would be inert"); LOG:close(); emu.stop(1); return end
    end
    if k > 70 then setPhase("approach") end
  elseif phase == "approach" then
    if math.abs(x16(P1) - x16(P2)) <= DIST then setPhase("gap")
    elseif k > 150 then log("SETUP-FAIL: approach never closed to " .. DIST); LOG:close(); emu.stop(1) end
  elseif phase == "gap" then
    if k > 12 then hp0 = r(P2, HP); setPhase("jump") end
  elseif phase == "jump" then
    if k > 2 and airborne(P2) then setPhase("arm")
    elseif k > 30 then log("SETUP-FAIL: P2 never left the ground (pad dead?)"); LOG:close(); emu.stop(1) end
  elseif phase == "arm" then
    rows[#rows + 1] = snap()
    local s = rows[#rows]
    if isReact(s.act) then
      contact = { t = t, y = s.y, act = s.act, air = airborne(P2), f46 = s.f46 }
      hpAfterLaunch = s.hp
      fwdSign = (x16(P1) < x16(P2)) and 1 or -1
      log(string.format("CONTACT t=%4d  reaction act=%02X  victim y=%3d  airborne=%s  46=%02X  hp %d->%d",
          t, s.act, s.y, tostring(contact.air), s.f46, hp0 or -1, s.hp))
      setPhase("watch")
    elseif k > HITDELAY + 45 then
      log("SETUP-FAIL: launcher never connected (delay " .. HITDELAY .. ")"); LOG:close(); emu.stop(1)
    end
  elseif phase == "watch" then
    local pre46 = r(P2, F46)
    if POKEVAL and not poking and airborne(P2) and isReact(r(P2, ACT)) then
      poking = true
      log(string.format("t=%4d  POKE armed: holding victim +0x46 at %02X (game had %02X)", t, POKEVAL, pre46))
    end
    if poking and airborne(P2) then PL.wr(P2 + F46, POKEVAL) end
    -- SPACING CONTROL (all modes): while the victim is airborne in a reaction
    -- act, pin their X at jab range AND their Y at torso height so the gate —
    -- not horizontal drift or the launch arc — decides. Feet held at 176
    -- (< 192 ground) keeps the airborne bit clear and the victim's body in a
    -- standing jab's reach.
    if PIN and airborne(P2) and isReact(r(P2, ACT)) and t > contact.t + 2 then
      local vx = x16(P1) + fwdSign * 24
      PL.wr(P2 + X, vx % 256); PL.wr(P2 + XH, math.floor(vx / 256))
      PL.wr(P2 + 0x24, 0); PL.wr(P2 + Y, 176)
    end
    rows[#rows + 1] = snap()
    rows[#rows].pre46 = pre46
    local s = rows[#rows]
    -- believe a re-hit only on VICTIM evidence: fresh hitstop edge or HP drop
    local newHstop = s.hst > 0 and prevHstop == 0 and t > contact.t + 10
    local hpDrop = prevHP and s.hp < prevHP and t > contact.t + 10
    if (newHstop or hpDrop) and (t - jabFrame) > 6 then
      jabFrame = t
      rehits[#rehits + 1] = { t = t, v_act = s.act, v_y = s.y, v_hp = s.hp, air = airborne(P2),
                              why = newHstop and "hitstop" or "hp" }
      log(string.format("RE-HIT RESOLVED t=%4d  (%s)  victim act=%02X y=%3d hp=%3d airborne=%s",
          t, rehits[#rehits].why, s.act, s.y, s.hp, tostring(airborne(P2))))
    end
    prevHstop, prevHP = s.hst, s.hp
    if not landFrame and not airborne(P2) then landFrame = t end
    if k > 140 then setPhase("done") end
  elseif phase == "done" then
    log(""); log(string.format("== probe_juggle  mode=%s hitdelay=%d ==", MODE, HITDELAY))
    for _, s in ipairs(rows) do
      log("   " .. fmt(s) .. (s.pre46 and poking and string.format(" pre46=%02X", s.pre46) or ""))
    end
    log("")
    if not contact then log("SETUP-FAIL: no contact")
    elseif not contact.air then
      log(string.format("SETUP-FAIL: contact was GROUNDED (y=%d) — resweep SMS_HITDELAY", contact.y))
    else
      log(string.format("launcher: reaction act %02X at y=%d, +0x46 then %02X", contact.act, contact.y, contact.f46))
      log(string.format("landing: %s", landFrame and ("t=" .. landFrame) or "not within window"))
      -- +0x46 lifecycle summary (frame granularity)
      local last, runs = nil, {}
      for _, s in ipairs(rows) do
        local v = s.pre46 or s.f46
        if v ~= last then runs[#runs + 1] = string.format("t=%d:%02X", s.t, v); last = v end
      end
      log("+0x46 lifecycle: " .. table.concat(runs, " -> "))
      local hpEnd = rows[#rows].hp
      log(string.format("victim HP: %d -> %d (launcher) -> %d (end)", hp0 or -1, hpAfterLaunch or -1, hpEnd))
      if #rehits == 0 then
        log("VERDICT: NO airborne re-hit resolved" .. (MODE == "clean" and "  (negative control: EXPECTED)" or "  (poke did NOT open the gate)"))
      else
        local airN = 0
        for _, h in ipairs(rehits) do if h.air then airN = airN + 1 end end
        log(string.format("VERDICT: %d re-hit(s) resolved, %d on an AIRBORNE victim%s",
            #rehits, airN, MODE == "clean" and "  (NEGATIVE CONTROL FAILED — the +0x46 model is wrong)" or ""))
      end
    end
    LOG:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_juggle loaded: mode=" .. MODE .. " hitdelay=" .. HITDELAY)
