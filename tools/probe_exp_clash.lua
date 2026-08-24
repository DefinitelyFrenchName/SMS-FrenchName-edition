-- probe_exp_clash.lua — do two hits meeting in their first active frames
-- CLASH (both pushed back, nobody damaged)? (Companion of the clash wiring
-- in tools/exp_animeroster.py.)
--
--   SMS_CMODE=sim     ROM=build/exp_animeroster.sfc tools/run.sh tools/probe_exp_clash.lua 90
--   SMS_CMODE=stagger ROM=build/exp_animeroster.sfc ...  (P2 presses 8f late: must HIT)
--   SMS_CMODE=sim     (clean ROM) SMS_TAG=clean          (must TRADE, vanilla)
--   -> traces/clash_<mode>[_tag].txt
--
-- Both fighters press HP on the same frame at a spacing where the two
-- hitboxes meet. Expected on the build: neither takes damage and both are
-- set to their backdash act (0x26 grounded / 0x2B airborne). SMS_DIST sweeps
-- the spacing; the clash window is a build knob (--clash N).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = os.getenv("SMS_CMODE") or "sim"
local TAG = os.getenv("SMS_TAG")
local DIST = tonumber(os.getenv("SMS_DIST") or "56")
local STAG = tonumber(os.getenv("SMS_STAGGER") or "8")
local LOG = assert(io.open(ENV.TRACE .. "clash_" .. MODE .. (TAG and ("_" .. TAG) or "") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local STATE = "venus_vs_jupiter_clean.mss"
local function r(b, o) return PL.ram(b + o) end
local function x16(b) return r(b, 0x21) + 256 * r(b, 0x22) end

local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local rows, hp1, hp2 = {}, nil, nil
local clash1, clash2, dmg1, dmg2 = nil, nil, nil, nil

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_exp_clash: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  local k, b1, b2 = t - phaseStart, {}, {}
  if phase == "approach" then
    b1[x16(P1) < x16(P2) and "right" or "left"] = true
  elseif phase == "press" then
    if k >= 0 and k < 4 then b1.x = true end
    local k2 = k - (MODE == "stagger" and STAG or 0)
    if k2 >= 0 and k2 < 4 then b2.x = true end
  end
  emu.setInput(PL.pad(b1), 0, 0)
  emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)

local function snap()
  return string.format("t=%4d P1 act=%02X 40=%02X 7D=%02X hp=%3d | P2 act=%02X 40=%02X 7D=%02X hp=%3d | gap=%d",
      t, r(P1, 0x01), r(P1, 0x40), r(P1, 0x7D), r(P1, 0x49),
      r(P2, 0x01), r(P2, 0x40), r(P2, 0x7D), r(P2, 0x49), math.abs(x16(P1) - x16(P2)))
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  if phase == "settle" then
    if k > 70 then phase, phaseStart = "approach", t end
  elseif phase == "approach" then
    if math.abs(x16(P1) - x16(P2)) <= DIST then
      hp1, hp2 = r(P1, 0x49), r(P2, 0x49)
      log(string.format("t=%4d engage at gap %d (hp %d / %d)", t, math.abs(x16(P1) - x16(P2)), hp1, hp2))
      phase, phaseStart = "press", t
    elseif k > 150 then log("SETUP-FAIL approach"); LOG:close(); emu.stop(1) end
  elseif phase == "press" then
    rows[#rows + 1] = snap()
    local a1, a2 = r(P1, 0x01), r(P2, 0x01)
    if (a1 == 0x26 or a1 == 0x2B) and not clash1 then clash1 = t end
    if (a2 == 0x26 or a2 == 0x2B) and not clash2 then clash2 = t end
    if r(P1, 0x49) < hp1 and not dmg1 then dmg1 = t end
    if r(P2, 0x49) < hp2 and not dmg2 then dmg2 = t end
    if k > 70 then
      log("")
      for _, s in ipairs(rows) do log("   " .. s) end
      log("")
      log(string.format("== CLASH %s%s (gap %d) ==", MODE, TAG and (" " .. TAG) or "", DIST))
      log(string.format("   P1 pushed back: %s   P2 pushed back: %s",
          clash1 and ("t=" .. clash1) or "no", clash2 and ("t=" .. clash2) or "no"))
      log(string.format("   damage: P1 %d->%d %s   P2 %d->%d %s",
          hp1, r(P1, 0x49), dmg1 and "(HIT)" or "(none)",
          hp2, r(P2, 0x49), dmg2 and "(HIT)" or "(none)"))
      local verdict = (clash1 and clash2 and not dmg1 and not dmg2) and "CLASH"
          or (dmg1 and dmg2) and "TRADE (both damaged)"
          or (dmg1 or dmg2) and "ONE-SIDED HIT" or "NOTHING HAPPENED"
      log("   VERDICT: " .. verdict)
      LOG:close(); emu.stop(0)
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_clash loaded: " .. MODE)
