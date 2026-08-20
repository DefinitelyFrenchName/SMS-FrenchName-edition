-- probe_exp_launcher.lua — does the UNIVERSAL LAUNCHER (fresh LK+HK
-- together, grounded) fire, and does it POP UP a grounded victim?
-- (Companion of exp_animeroster.py's launcher wiring.)
--
--   SMS_LMODE=launch ROM=build/exp_animeroster.sfc tools/run.sh tools/probe_exp_launcher.lua 90
--   SMS_LMODE=single ROM=build/exp_animeroster.sfc ...   (LK alone: must be a NORMAL, not 2E)
--   SMS_LMODE=launch (clean ROM) SMS_TAG=clean           (negative: no act 2E exists)
--   -> traces/launcher_<mode>[_tag].txt
--
-- Mechanism: ground-route stub commits act 0x2E (skipping the normals
-- route); the 0x2E wrapper runs the char's own standing-HK handler and
-- stamps attackID 12 -> on-hit idx 6 -> code 0x14 = the STAND sub-table's
-- pop-up row: victim act 0x1B, vy -1792, gravity 96, juggle-soft (+0x46=20
-- via the decay routine).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = os.getenv("SMS_LMODE") or "launch"
local TAG = os.getenv("SMS_TAG")
local LOG = assert(io.open(ENV.TRACE .. "launcher_" .. MODE .. (TAG and ("_" .. TAG) or "") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local STATE = os.getenv("SMS_LSTATE") or "venus_vs_jupiter_clean.mss"
local function r(b, o) return PL.ram(b + o) end
local function x16(b) return r(b, 0x21) + 256 * r(b, 0x22) end
local function air(b) return (r(b, 0x16) & 0x80) == 0 end
local function s16(b, o)
  local v = r(b, o) + 256 * r(b, o + 1)
  return v >= 0x8000 and v - 0x10000 or v
end

local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local rows, hp0 = {}, nil
local sawLauncherAct, victimLaunch, minY, launch46 = nil, nil, 255, nil
local wallflySeen, wallStop, bounceSeen, bounceVel, bounceMinY, settled, lastWX = nil, nil, nil, nil, nil, nil, nil

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_exp_launcher: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  local k, b1 = t - phaseStart, {}
  if phase == "approach" then
    b1[x16(P1) < x16(P2) and "right" or "left"] = true
  elseif phase == "press" and k < 4 then
    if MODE == "single" then b1.b = true else b1.b = true; b1.a = true end
  end
  emu.setInput(PL.pad(b1), 0, 0)
  emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

local function snap()
  return string.format("t=%4d a.act=%02X 44=%02X | v.act=%02X st=%02X 46=%02X hp=%3d y=%3d yv=%6d wx=%4d sx=%3d cam=%4d",
      t, r(P1, 0x01), r(P1, 0x44), r(P2, 0x01), r(P2, 0x16), r(P2, 0x46), r(P2, 0x49), r(P2, 0x25), s16(P2, 0x32),
      x16(P2), r(P2, 0x28), PL.ram(0x0A00) + 256 * PL.ram(0x0A01))
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  if phase == "settle" then
    if k > 70 then phase, phaseStart = "approach", t end
  elseif phase == "approach" then
    if math.abs(x16(P1) - x16(P2)) <= 48 then hp0 = r(P2, 0x49); phase, phaseStart = "press", t
    elseif k > 150 then log("SETUP-FAIL approach"); LOG:close(); emu.stop(1) end
  elseif phase == "press" then
    rows[#rows + 1] = snap()
    local aa, va = r(P2, 0x01), r(P2, 0x01)
    aa = r(P1, 0x01)
    if aa == 0x2E and not sawLauncherAct then sawLauncherAct = t end
    -- wall-bounce tracking
    if va == 0x2F then
      wallflySeen = wallflySeen or t
      local x = x16(P2)
      if lastWX and x == lastWX then wallStop = wallStop or t end
      lastWX = x
    end
    if wallflySeen and va == 0x16 then
      bounceSeen = bounceSeen or t
      if not bounceVel then bounceVel = { vx = s16(P2, 0x30), vy = s16(P2, 0x32) } end
      if r(P2, 0x25) < (bounceMinY or 255) then bounceMinY = r(P2, 0x25) end
    end
    if bounceSeen and va == 0x00 and not settled then settled = t end
    if (va == 0x1B or va == 0x1A) and not victimLaunch then victimLaunch = t end
    if victimLaunch and air(P2) and not launch46 then launch46 = r(P2, 0x46) end
    if victimLaunch and r(P2, 0x25) < minY then minY = r(P2, 0x25) end
    if k > 150 then
      log("")
      for _, s in ipairs(rows) do log("   " .. s) end
      log("")
      log(string.format("== LAUNCHER %s%s ==", MODE, TAG and (" " .. TAG) or ""))
      log(string.format("   launcher act 2E: %s", sawLauncherAct and ("t=" .. sawLauncherAct) or "NO"))
      log(string.format("   victim POP-UP: %s", victimLaunch and
          string.format("t=%d, +0x46=%02X (%s), apex y=%d, hp %d->%d", victimLaunch, launch46,
            launch46 == 0x20 and "JUGGLE-SOFT" or "protected", minY, hp0, r(P2, 0x49)) or "NO"))
      log(string.format("   WALLFLY (act 2F): %s   wall stop: %s", wallflySeen and ("t=" .. wallflySeen) or "NO",
          wallStop and ("t=" .. wallStop) or "no"))
      log(string.format("   BOUNCE (act 16): %s", bounceSeen and
          string.format("t=%d vx=%d vy=%d apex y=%d", bounceSeen, bounceVel.vx, bounceVel.vy, bounceMinY or 255) or "NO"))
      log(string.format("   settled to neutral: %s", settled and ("t=" .. settled) or "no"))
      LOG:close(); emu.stop(0)
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_launcher loaded: " .. MODE)
