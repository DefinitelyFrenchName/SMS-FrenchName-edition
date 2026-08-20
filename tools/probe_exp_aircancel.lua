-- probe_exp_aircancel.lua — do the AIR-DASH CANCEL and the ON-HIT AIR CHAIN
-- fire? (Phase 4 of the anime-fighter feasibility programme. Companion of
-- tools/exp_aircancel.py; fixture uranus_vs_jupiter_clean.mss, Uranus = P1.)
--
--   SMS_TEST=dashcancel ROM=build/exp_aircancel.sfc tools/run.sh tools/probe_exp_aircancel.lua 90
--   SMS_TEST=hit        ROM=build/exp_aircancel.sfc tools/run.sh tools/probe_exp_aircancel.lua 90
--   SMS_TEST=whiff      ROM=build/exp_aircancel.sfc tools/run.sh tools/probe_exp_aircancel.lua 90
--   SMS_TEST=dashcancel ROM=build/exp_airdash2.sfc  SMS_TAG=base tools/run.sh ...   (negative)
--   -> traces/exp_aircancel_<test>[_base].txt
--
--   dashcancel : air front dash (act 2C), then HP mid-dash. Build: act 0x51
--                (directional j.HP) starts while airborne. airdash2 base:
--                the press does nothing (act 2C offers no routes there).
--   hit        : jump-in j.HP connects on Jupiter, then a fwd double-tap
--                while the connect latch (+0x43) is set. Build: act 0x2C
--                starts WHILE ACT 0x51 IS STILL RUNNING (the gatling).
--   whiff      : same input, jump away so j.HP whiffs — the cancel must NOT
--                fire during the act (+0x43=0). A dash starting AFTER the
--                normal has ended (back in a jump act, via the Phase-3 stub)
--                is legitimate and reported separately.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local TEST = os.getenv("SMS_TEST") or "dashcancel"
local TAG = os.getenv("SMS_TAG")
local LOG = assert(io.open(ENV.TRACE .. "exp_aircancel_" .. TEST .. (TAG and ("_" .. TAG) or "") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local STATE = "uranus_vs_jupiter_clean.mss"
local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local rows = {}
local dashSeen, jhpSeen = nil, nil

local function p1(o) return PL.ram(P1 + o) end
local function airborne() return (p1(0x16) & 0x80) == 0 end
local function x16(b) return PL.ram(b + 0x21) + 256 * PL.ram(b + 0x22) end
local function fwdDir() return x16(P1) < x16(P2) and "right" or "left" end
local function setPhase(p)
  log(string.format("t=%4d  %s -> %s  (act=%02X st=%02X y=%d 43=%02X)", t, phase, p, p1(0x01), p1(0x16), p1(0x25), p1(0x43)))
  phase, phaseStart = p, t
end

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_exp_aircancel: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  local k, b = t - phaseStart, {}
  local fwd = fwdDir()
  if phase == "approach" then
    b[fwd] = true
  elseif phase == "jump" then
    if k < 6 then
      b.up = true
      b[TEST == "whiff" and (fwd == "right" and "left" or "right") or fwd] = true
    end
  elseif phase == "dash66" then
    if (k >= 0 and k < 5) or (k >= 9 and k < 14) then b[fwd] = true end
  elseif phase == "press" then
    if k < 4 then b.x = true end
  elseif phase == "jhp" then
    if k < 4 then b.x = true end
  elseif phase == "tap66" then
    if (k >= 0 and k < 4) or (k >= 8 and k < 12) then b[fwd] = true end
  end
  emu.setInput(PL.pad(b), 0, 0)
  emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

local function snap()
  return string.format("t=%4d act=%02X stp=%02X st=%02X y=%3d x=%4d 43=%02X 51=%02X hstop=%02X",
      t, p1(0x01), p1(0x02), p1(0x16), p1(0x25), x16(P1), p1(0x43), p1(0x51), p1(0x4D))
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  local act = p1(0x01)

  if phase == "settle" then
    if k > 70 then
      if TEST == "dashcancel" then setPhase("jump")
      elseif TEST == "hit" then setPhase("approach")
      else setPhase("jump") end
    end
  elseif phase == "approach" then
    if math.abs(x16(P1) - x16(P2)) <= 70 then setPhase("jump")
    elseif k > 150 then log("SETUP-FAIL: approach"); LOG:close(); emu.stop(1) end
  elseif phase == "jump" then
    if k > 2 and airborne() then
      setPhase(TEST == "dashcancel" and "dash66" or "jhpdelay")
    elseif k > 30 then log("SETUP-FAIL: never airborne"); LOG:close(); emu.stop(1) end
  elseif phase == "jhpdelay" then
    rows[#rows + 1] = snap()
    if k >= tonumber(os.getenv("SMS_JD") or "8") then setPhase("jhp") end
  elseif phase == "dash66" then
    rows[#rows + 1] = snap()
    if act == 0x2C then dashSeen = t; setPhase("press") end
    if k > 40 then setPhase("report") end
  elseif phase == "press" or phase == "jhp" or phase == "tap66" or phase == "watch" then
    rows[#rows + 1] = snap()
    if (phase == "jhp") and act == 0x50 then jhpSeen = t; setPhase("tap66") end
    if phase == "tap66" and k > 16 then setPhase("watch") end
    if (phase == "press" or phase == "watch") and k > 50 then setPhase("report") end
    if phase == "jhp" and k > 30 then setPhase("report") end
  elseif phase == "report" then
    log("")
    for _, s in ipairs(rows) do log("   " .. s) end
    log("")
    -- verdicts from the recorded rows
    local firstJHP, firstDash, dashDuringJHP, jhpDuringDash, latch = nil, nil, nil, nil, false
    local prev = nil
    for _, s in ipairs(rows) do
      local a = tonumber(s:match("act=(%x+)"), 16)
      local c43 = tonumber(s:match("43=(%x+)"), 16)
      local tt = tonumber(s:match("t=%s*(%d+)"))
      if a == 0x50 and not firstJHP then firstJHP = tt end
      if (a == 0x2B or a == 0x2C) and not firstDash then firstDash = tt end
      if a == 0x50 and prev and (prev == 0x2B or prev == 0x2C) then jhpDuringDash = tt end
      if (a == 0x2B or a == 0x2C) and prev == 0x50 then dashDuringJHP = tt end
      if c43 and c43 ~= 0 then latch = true end
      prev = a
    end
    log(string.format("== VERDICT %s%s ==", TEST, TAG and (" (" .. TAG .. ")") or ""))
    if TEST == "dashcancel" then
      log(string.format("   air dash: %s   j.HP out of the dash: %s",
          firstDash and ("t=" .. firstDash) or "NO",
          jhpDuringDash and ("t=" .. jhpDuringDash .. "  (DASH-CANCEL FIRED)") or "NO"))
    else
      log(string.format("   j.HP: %s   connect latch seen: %s", firstJHP and ("t=" .. firstJHP) or "NO", tostring(latch)))
      log(string.format("   dash out of j.HP (act 50 -> 2B/2C): %s",
          dashDuringJHP and ("t=" .. dashDuringJHP .. "  (GATLING FIRED)") or "NO"))
      log(string.format("   any dash at all: %s", firstDash and ("t=" .. firstDash) or "NO"))
    end
    LOG:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_aircancel loaded: " .. TEST)
