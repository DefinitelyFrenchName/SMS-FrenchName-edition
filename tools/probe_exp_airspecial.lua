-- probe_exp_airspecial.lua — what does a GROUND special do when started
-- AIRBORNE? (Phase 2 of the anime-fighter feasibility programme, gate G3.
-- Companion of tools/exp_airspecial.py.)
--
--   Run FOUR ways; the verdicts only mean anything together:
--     SMS_CHAR=venus SMS_TAG=build ROM=build/exp_airspecial.sfc tools/run.sh tools/probe_exp_airspecial.lua 120
--     SMS_CHAR=venus SMS_TAG=clean                              tools/run.sh tools/probe_exp_airspecial.lua 120
--     SMS_CHAR=moon  SMS_TAG=build ROM=build/exp_airspecial.sfc tools/run.sh tools/probe_exp_airspecial.lua 120
--     SMS_CHAR=moon  SMS_TAG=clean                              tools/run.sh tools/probe_exp_airspecial.lua 120
--   -> traces/exp_airspecial_<char>_<tag>.txt
--
--   * the GROUND section must be frame-identical between clean and build
--     (the flag edit must not change the grounded move) — diff the files.
--   * the AIR section on clean must show NO special act (negative control).
--   * the AIR section on the build is the measurement: does the act start,
--     does the projectile spawn, does the step pin at 0 (the re-fire trap),
--     what happens at landing, does she return to neutral?
--
-- Fixtures: venus_vs_jupiter_clean.mss / moon_vs_jupiter_clean.mss (P1 = the
-- subject). 236P scripted as down / down-fwd / fwd / punch, 3-4f per step,
-- inside the recognizer's 15-frame window.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")

local CHAR = os.getenv("SMS_CHAR") or "venus"
local TAG = os.getenv("SMS_TAG") or "clean"
local D = tonumber(os.getenv("SMS_D") or "8")
local MOVE = os.getenv("SMS_MOVE") or "qcf"   -- qcf = 236P; dp = 623P (Venus strike test)
local CFG = {
  venus = { state = "venus_vs_jupiter_clean.mss",
            acts = MOVE == "dp" and { [0x67] = true, [0x68] = true }
                                 or { [0x5B] = true, [0x5C] = true } },
  moon  = { state = "moon_vs_jupiter_clean.mss",  acts = { [0x61] = true, [0x62] = true } },
}
local cfg = CFG[CHAR] or error("SMS_CHAR must be venus|moon")
local LOG = assert(io.open(ENV.TRACE .. string.format("exp_airspecial_%s_%s%s.txt", CHAR, TAG,
    MOVE == "dp" and "_dp" or ""), "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2, PROJ = 0x1000, 0x1080, 0x1100
local function r(o) return PL.ram(P1 + o) end
local function airborne() return (r(0x16) & 0x80) == 0 end

local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local air = {}                        -- air-section rows for the verdict

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. cfg.state, "rb")
    if not f then print("probe_exp_airspecial: cannot open " .. cfg.state); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local function fwdDir()
  local x1 = r(0x21) + 256 * r(0x22)
  local x2 = PL.ram(P2 + 0x21) + 256 * PL.ram(P2 + 0x22)
  return x1 < x2 and "right" or "left"
end

local function qcf(b, j)              -- the scripted motion, starting at local frame j
  local fwd = fwdDir()
  if MOVE == "dp" then                -- 623: fwd, down, down-fwd + P
    if j >= 0 and j < 3 then b[fwd] = true
    elseif j >= 3 and j < 6 then b.down = true
    elseif j >= 6 and j < 9 then b.down = true; b[fwd] = true
    elseif j >= 9 and j < 13 then b.down = true; b[fwd] = true; b.y = true end
  else                                -- 236: down, down-fwd, fwd + P
    if j >= 0 and j < 3 then b.down = true
    elseif j >= 3 and j < 6 then b.down = true; b[fwd] = true
    elseif j >= 6 and j < 9 then b[fwd] = true
    elseif j >= 9 and j < 13 then b[fwd] = true; b.y = true end
  end
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k, b = t - phaseStart, {}
  if phase == "gspec" then
    qcf(b, k)
  elseif phase == "jump" then
    if k < 6 then b.up = true; b[fwdDir()] = true end
  elseif phase == "aspec" then
    qcf(b, k - D)
  end
  emu.setInput(PL.pad(b), 0, 0)
  emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

local function snap()
  local function s16(o)
    local v = r(o) + 256 * r(o + 1)
    return v >= 0x8000 and v - 0x10000 or v
  end
  return string.format("t=%4d act=%02X stp=%02X st=%02X y=%3d x=%4d yv=%6d 51=%02X | proj id=%02X y=%3d x=%4d",
      t, r(0x01), r(0x02), r(0x16), r(0x25), r(0x21) + 256 * r(0x22), s16(0x32), r(0x51),
      PL.ram(PROJ), PL.ram(PROJ + 0x25), PL.ram(PROJ + 0x21) + 256 * PL.ram(PROJ + 0x22))
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart

  if phase == "settle" then
    if k > 70 then log("== GROUND 236P (A/B section: clean vs build must be identical) ==")
      phase, phaseStart = "gspec", t end
  elseif phase == "gspec" then
    log("   " .. snap())
    if k > 20 and r(0x01) == 0 and PL.ram(PROJ) == 0 then
      log(""); log("== JUMP + AIR 236P (delay " .. D .. ") ==")
      phase, phaseStart = "jump", t
    elseif k > 200 then log("SETUP-FAIL: ground section never settled"); LOG:close(); emu.stop(1) end
  elseif phase == "jump" then
    if k > 2 and airborne() then phase, phaseStart = "aspec", t
    elseif k > 30 then log("SETUP-FAIL: never left the ground"); LOG:close(); emu.stop(1) end
  elseif phase == "aspec" then
    local row = snap()
    log("   " .. row)
    air[#air + 1] = { t = t, act = r(0x01), step = r(0x02), air = airborne(),
                      proj = PL.ram(PROJ), y = r(0x25) }
    if (k > 40 and not airborne() and r(0x01) == 0) or k > 160 then
      -- verdict over the air section
      local started, startT, startAir, pin, projSeen, landAct, neutralT = nil, nil, nil, 0, false, nil, nil
      local prevAct = nil
      for i, s in ipairs(air) do
        if not started and cfg.acts[s.act] then started, startT, startAir = s.act, s.t, s.air end
        if started and cfg.acts[s.act] and s.step == 0 then pin = pin + 1 end
        if s.proj ~= 0 then projSeen = true end
        if not landAct and not s.air and i > 3 then landAct = s.act end
        if not neutralT and s.act == 0 and i > 5 then neutralT = s.t end
        prevAct = s.act
      end
      log("")
      log(string.format("== VERDICT %s/%s ==", CHAR, TAG))
      if not started then
        log("   AIR START: NO special act entered" .. (TAG == "clean" and "  (negative control: EXPECTED)" or "  (G3: the flag edit did not arm the air start)"))
      else
        log(string.format("   AIR START: act %02X at t=%d, airborne=%s", started, startT, tostring(startAir)))
        log(string.format("   step-0 frames while in the act: %d %s", pin, pin > 2 and "(RE-FIRE PINNING)" or "(no pinning)"))
        log(string.format("   projectile spawned: %s", tostring(projSeen)))
        log(string.format("   act on landing: %s", landAct and string.format("%02X", landAct) or "n/a"))
        log(string.format("   back to neutral: %s", neutralT and ("t=" .. neutralT) or "NOT within window (possible wedge)"))
      end
      LOG:close(); emu.stop(0)
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_airspecial loaded: " .. CHAR .. " " .. TAG)
