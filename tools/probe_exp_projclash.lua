-- probe_exp_projclash.lua — can a PROJECTILE take part in a clash?
--
--   SMS_PCMODE=vsattack ROM=build/exp_animeroster.sfc tools/run.sh tools/probe_exp_projclash.lua 200
--   SMS_PCMODE=vsattack ROM=<clean>  SMS_TAG=clean ...     (the control)
--   SMS_PCMODE=vsball   ROM=build/exp_animeroster.sfc ...  (two fireballs meet)
--   SMS_PCMODE=vsball   ROM=<clean>  SMS_TAG=clean ...
--   -> traces/projclash_<mode>[_tag].txt
--
-- The maintainer's rule (2026-08-25): a clash must never involve a projectile
-- hitbox. Reading the code says it cannot — the test is entered with the
-- ATTACKER's struct base in X and bails to vanilla target selection unless
-- that base is $1000 or $1080, and the opposing side is derived as
-- `base XOR $80`, which is always the other PLAYER slot, never $1100/$1180.
-- Reading is not measuring, so this stages both ways a projectile hitbox can
-- meet another hitbox and asks the ROM:
--
--   vsattack  Neptune (P1) fires 214LP; Jupiter (P2) swings HP so his hitbox
--             is live when the ball arrives. Ball hitbox vs body hitbox.
--   vsball    Neptune mirror: both fire, the two balls meet mid-screen.
--             Ball hitbox vs ball hitbox.
--
-- PASS = neither fighter enters a clash act (0x26/0x2B) or the mash contest
-- (0x31) while the ball is live, AND the run matches the clean ROM's outcome.
-- The clean run is the control that says the projectile path is untouched; the
-- positive control that this harness can see a clash at all is
-- probe_exp_clash.lua, which reports one on the same build.
--
-- P2's swing is triggered by the BALL'S POSITION, not by a frame number, so
-- the contact does not depend on this probe guessing a travel time.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = os.getenv("SMS_PCMODE") or "vsattack"
local TAG = os.getenv("SMS_TAG")
-- 90 is measured: swept 30-110, and only a lead of >= 75 puts his active
-- frames under the ball (below that the ball arrives during his startup and
-- the run is VOID, not a pass).
local NEAR = tonumber(os.getenv("SMS_NEAR") or "90")   -- swing lead, in pixels of ball travel
local LOG = assert(io.open(ENV.TRACE .. "projclash_" .. MODE .. (TAG and ("_" .. TAG) or "") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local B1, B2 = 0x1100, 0x1180          -- the two projectile slots
local STATE = MODE == "vsball" and "neptune_vs_neptune.mss" or "neptune_vs_jupiter.mss"
local function r(b, o) return PL.ram(b + o) end
local function x16(b) return r(b, 0x21) + 256 * r(b, 0x22) end
local function alive(b) local id = r(b, 0x00); return id ~= 0 and id < 0x80 end

local t, loaded = -1, false
local rows = {}
local hp1, hp2 = nil, nil
local clashacts, ballseen, contact = {}, 0, nil
local swung = nil

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_exp_projclash: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

-- 214 = down / down-back / back, attack on the last input. P1 faces right, so
-- back is left; P2 faces left, so back is right (the mirror run needs both).
-- Each state is HELD until the next one, exactly as ds_trace.lua's plan does:
-- a gap in the middle of the motion resets the recognizer, which is why the
-- first version of this probe never produced a fireball at all.
local function motion(k, btn, back)
  if k >= 8 and k <= 10 then return { down = true } end
  if k >= 11 and k <= 13 then return { down = true, [back] = true } end
  if k >= 14 and k <= 16 then return { [back] = true, [btn] = true } end
  return {}
end

emu.addEventCallback(function()
  if t < 0 then return end
  local b1, b2 = {}, {}
  if t >= 40 then
    b1 = motion(t - 40, "y", "left")
    if MODE == "vsball" then b2 = motion(t - 40, "y", "right") end
  end
  if MODE == "vsattack" then
    -- ONE swing, triggered by the ball's DISTANCE, because his HP carries ~10
    -- frames of startup: a swing begun at contact range is always late
    -- (measured — the ball hit him for 10 with his box still reading 00).
    -- SMS_NEAR is the lead, swept to find the distance whose active frames
    -- cover the ball's arrival.
    if not swung and alive(B1) and math.abs(x16(B1) - x16(P2)) <= NEAR then
      swung = t
    end
    if swung and t - swung < 4 then b2.x = true end
  end
  emu.setInput(PL.pad(b1), 0, 0)
  emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  if not hp1 then hp1, hp2 = r(P1, 0x49), r(P2, 0x49) end
  local live1, live2 = alive(B1), alive(B2)
  if live1 or live2 then
    ballseen = ballseen + 1
    rows[#rows + 1] = string.format(
      "t=%4d P1 act=%02X 40=%02X 7D=%02X hp=%3d | P2 act=%02X 40=%02X 7D=%02X hp=%3d | "
      .. "ball1 id=%02X 40=%02X 7D=%02X x=%4d | ball2 id=%02X 40=%02X 7D=%02X x=%4d",
      t, r(P1, 0x01), r(P1, 0x40), r(P1, 0x7D), r(P1, 0x49),
      r(P2, 0x01), r(P2, 0x40), r(P2, 0x7D), r(P2, 0x49),
      r(B1, 0x00), r(B1, 0x40), r(B1, 0x7D), x16(B1),
      r(B2, 0x00), r(B2, 0x40), r(B2, 0x7D), x16(B2))
    -- the moment of interest: a ball's hitbox and another live hitbox share space
    if not contact then
      if MODE == "vsball" and live1 and live2 and math.abs(x16(B1) - x16(B2)) <= 24 then
        contact = t
      elseif MODE == "vsattack" and live1 and r(P2, 0x40) ~= 0
          and math.abs(x16(B1) - x16(P2)) <= 48 then
        contact = t
      end
    end
    for _, side in ipairs({ { "P1", P1 }, { "P2", P2 } }) do
      local a = r(side[2], 0x01)
      if a == 0x26 or a == 0x2B or a == 0x31 then
        clashacts[#clashacts + 1] = string.format("%s act %02X at t=%d", side[1], a, t)
      end
    end
  end
  if t > 190 then
    for _, s in ipairs(rows) do log("   " .. s) end
    log("")
    log(string.format("== PROJECTILE CLASH %s%s ==", MODE, TAG and (" " .. TAG) or ""))
    log(string.format("   frames with a live ball: %d   ball-vs-hitbox contact: %s",
        ballseen, contact and ("t=" .. contact) or "NONE"))
    log(string.format("   damage: P1 %d->%d   P2 %d->%d", hp1, r(P1, 0x49), hp2, r(P2, 0x49)))
    if #clashacts == 0 then
      log("   clash/contest acts while a ball was live: none")
    else
      for _, s in ipairs(clashacts) do log("   CLASH ACT: " .. s) end
    end
    local verdict
    if ballseen == 0 then
      verdict = "VOID — no projectile ever spawned, this run says nothing"
    elseif not contact then
      verdict = "VOID — the ball never met another hitbox, this run says nothing"
    elseif #clashacts > 0 then
      verdict = "PROJECTILE CLASHED — the rule is violated"
    else
      verdict = "no clash with a projectile (compare the clean run for the outcome)"
    end
    log("   VERDICT: " .. verdict)
    LOG:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_projclash loaded: " .. MODE)
