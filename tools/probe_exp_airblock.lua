-- probe_exp_airblock.lua — does AIR BLOCK work, and does the AIR GUARD
-- CANCEL ride on it? (Companion of exp_animeroster.py's air-block wiring.)
--
--   SMS_ABMODE=block   ROM=build/exp_animeroster.sfc tools/run.sh tools/probe_exp_airblock.lua 90
--   SMS_ABMODE=noguard ROM=build/exp_animeroster.sfc ...   (air, no back: must still be HIT)
--   SMS_ABMODE=ground  ROM=build/exp_animeroster.sfc ...   (ground block unchanged)
--   SMS_ABMODE=gc      ROM=build/exp_animeroster.sfc ...   (66 during air blockstun -> act 2C)
--   SMS_ABMODE=block   (clean ROM)                         (negative: air hit as vanilla)
--   -> traces/airblock_<mode>[_clean].txt
--
-- Fixture venus_vs_jupiter_clean.mss: Venus (P1) 5HPs a neutral-jumping
-- Jupiter (P2) who holds back once airborne. On the build the contact must
-- put the victim in act 0x2D (air blockstun) with +0x46=0x20 and BLOCKED
-- damage (ground block rules: normals chip 0); without back held the same
-- contact is a hit (act 0x16, full damage). Mechanism: the resolution fork
-- stub at $C0:C06A/$C13D + air sub-table rows 1/2 -> the reaction shim.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = os.getenv("SMS_ABMODE") or "block"
local TAG = os.getenv("SMS_TAG")
local LOG = assert(io.open(ENV.TRACE .. "airblock_" .. MODE .. (TAG and ("_" .. TAG) or "") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local STATE = "venus_vs_jupiter_clean.mss"
local function r(b, o) return PL.ram(b + o) end
local function x16(b) return r(b, 0x21) + 256 * r(b, 0x22) end
local function air(b) return (r(b, 0x16) & 0x80) == 0 end

local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local rows, hp0, contact, gcSeen = {}, nil, nil, nil

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_exp_airblock: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local function dirs()
  local fwd = x16(P1) < x16(P2) and "right" or "left"
  return fwd, fwd    -- P2's away-direction = P1's forward (screen direction)
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  local b1, b2 = {}, {}
  local fwd, p2away = dirs()
  local p2toward = p2away == "right" and "left" or "right"
  if phase == "approach" then
    b1[fwd] = true
  elseif phase == "jump" then
    if MODE ~= "ground" and k < 6 then b2.up = true end
    if MODE ~= "noguard" and k >= 6 then b2[p2away] = true end
  elseif phase == "arm" or phase == "watch" then
    if MODE == "gc" and contact then
      -- fwd double-taps toward the attacker for the GC dash
      local c = (t - contact) % 14
      if (c >= 2 and c < 6) or (c >= 9 and c < 13) then b2[p2toward] = true end
    elseif MODE ~= "noguard" then
      b2[p2away] = true
    end
    local pk = MODE == "ground" and 4 or 12
    if phase == "arm" and k >= pk and k < pk + 4 then b1.x = true end
  end
  emu.setInput(PL.pad(b1), 0, 0)
  emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)

local function snap()
  return string.format("t=%4d v.act=%02X stp=%02X st=%02X 46=%02X 7E=%02X 50=%02X hp=%3d y=%3d hst=%02X | a.act=%02X",
      t, r(P2, 0x01), r(P2, 0x02), r(P2, 0x16), r(P2, 0x46), r(P2, 0x7E), r(P2, 0x50), r(P2, 0x49), r(P2, 0x25), r(P2, 0x4D), r(P1, 0x01))
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  local va = r(P2, 0x01)

  if phase == "settle" then
    if k > 70 then phase, phaseStart = "approach", t end
  elseif phase == "approach" then
    if math.abs(x16(P1) - x16(P2)) <= 40 then hp0 = r(P2, 0x49); phase, phaseStart = "jump", t
    elseif k > 150 then log("SETUP-FAIL approach"); LOG:close(); emu.stop(1) end
  elseif phase == "jump" then
    local ready = MODE == "ground" and k > 4 or (air(P2) and k > 2)
    if ready then phase, phaseStart = "arm", t
    elseif k > 30 then log("SETUP-FAIL jump"); LOG:close(); emu.stop(1) end
  elseif phase == "arm" or phase == "watch" then
    rows[#rows + 1] = snap()
    if not contact and ((va >= 0x0E and va <= 0x20) or va == 0x2D) then
      contact = t
      log(string.format("CONTACT t=%4d victim -> act %02X airborne=%s 46=%02X hp %d->%d",
          t, va, tostring(air(P2)), r(P2, 0x46), hp0, r(P2, 0x49)))
      phase, phaseStart = "watch", t
    end
    if contact and va == 0x2C then gcSeen = gcSeen or t end
    if (phase == "arm" and k > 60) or (phase == "watch" and k > 70) then
      log("")
      for _, s in ipairs(rows) do log("   " .. s) end
      log("")
      log(string.format("== AIRBLOCK %s%s ==", MODE, TAG and (" " .. TAG) or ""))
      if not contact then log("   SETUP-FAIL: no contact")
      else
        local hpEnd = r(P2, 0x49)
        local firstAct = nil
        for _, s in ipairs(rows) do
          local a = tonumber(s:match("v%.act=(%x+)"), 16)
          local tt = tonumber(s:match("t=%s*(%d+)"))
          if tt >= contact and not firstAct then firstAct = a end
        end
        log(string.format("   contact act: %02X (%s)", firstAct,
            firstAct == 0x2D and "AIR BLOCKSTUN" or (firstAct == 0x0E or firstAct == 0x0F) and "ground blockstun" or "hit reaction"))
        log(string.format("   damage: %d -> %d (%s)", hp0, hpEnd,
            hpEnd == hp0 and "BLOCKED clean" or (hp0 - hpEnd <= 2 and "chip" or "FULL")))
        if MODE == "gc" then
          log(string.format("   air guard cancel -> act 2C: %s", gcSeen and ("t=" .. gcSeen) or "NO"))
        end
      end
      LOG:close(); emu.stop(0)
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_airblock loaded: " .. MODE)
