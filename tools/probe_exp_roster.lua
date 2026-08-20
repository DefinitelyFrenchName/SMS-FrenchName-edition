-- probe_exp_roster.lua — per-character verification of the full-roster
-- anime-fighter PoC (companion of tools/exp_animeroster.py).
--
--   SMS_CID=<1-9> ROM=build/exp_animeroster.sfc tools/run.sh tools/probe_exp_roster.lua 90
--   SMS_CID=<1-9> SMS_TAG=clean tools/run.sh ...       (negative control)
--   -> traces/roster_c<cid>[_clean].txt
--
-- One run per character, P1 = the subject:
--   ground 44 control  -> act 0x26 (backdash untouched)
--   air 44             -> act 0x2B (build) / nothing (clean)
--   press LP mid-dash  -> a dir air normal (the dash-cancel; expected acts
--                         read from THIS ROM's dir stance table via the act
--                         dispatch, so the probe needs no per-char constants)
--   land, jump 2, air 66 -> act 0x2C (the front dash; for seven characters
--                         this exercises the appended motion + air-only entry)
-- P2 is inert throughout. Verdict lines are grep-stable.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CID = tonumber(os.getenv("SMS_CID") or "5")
local TAG = os.getenv("SMS_TAG")
local STATES = { [1] = "moon_vs_jupiter_clean.mss", [2] = "char2_vs_uranus_clean.mss",
  [3] = "char3_vs_uranus_clean.mss", [4] = "char4_vs_uranus_clean.mss",
  [5] = "venus_vs_jupiter_clean.mss", [6] = "uranus_vs_jupiter_clean.mss",
  [7] = "char7_vs_uranus_clean.mss", [8] = "char8_vs_uranus_clean.mss",
  [9] = "chibi_vs_venus_clean.mss" }
local STATE = STATES[CID] or error("bad SMS_CID")
local LOG = assert(io.open(ENV.TRACE .. "roster_c" .. CID .. (TAG and ("_" .. TAG) or "") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local function p1(o) return PL.ram(P1 + o) end
local function airborne() return (p1(0x16) & 0x80) == 0 end
local function x16(b) return PL.ram(b + 0x21) + 256 * PL.ram(b + 0x22) end
local function fwdDir() return x16(P1) < x16(P2) and "right" or "left" end

-- expected dir-air-normal acts, read from THIS ROM (PL.rom = file offsets):
-- proc dispatch $C1:00A6 -> act table (jmp (tbl,X) operand) -> act 7 handler
-- -> its ldy operand = dir stance table -> the 8 record acts.
local function dirActs()
  local proc = PL.rom(0x0100A6 + CID * 2) + 256 * PL.rom(0x0100A7 + CID * 2)
  local tbl
  for off = 0x010000 + proc, 0x010000 + proc + 0x20 do
    if PL.rom(off) == 0x7C then tbl = PL.rom(off + 1) + 256 * PL.rom(off + 2); break end
  end
  local h7 = PL.rom(0x010000 + tbl + 14) + 256 * PL.rom(0x010000 + tbl + 15)
  local st
  -- first ldy-fed jsr: on the BUILD the jsr $0459 is hooked to the shim, so
  -- match any `ldy #imm / jsr` pair (the first is the normals route)
  for off = 0x010000 + h7, 0x010000 + h7 + 0x60 do
    if PL.rom(off) == 0xA0 and PL.rom(off + 3) == 0x20 then
      st = PL.rom(off + 1) + 256 * PL.rom(off + 2); break
    end
  end
  local acts = {}
  if st then
    for i = 0, 3 do
      acts[PL.rom(0x010000 + st + i * 3 + 1)] = true
      acts[PL.rom(0x010000 + st + i * 3 + 2)] = true
    end
  end
  return acts
end
local DIR_ACTS = dirActs()

local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local seen = { g44 = false, air2B = false, cancel = nil, air2C = false }
local dashDir = nil

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_exp_roster: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local function backTap(k, b, d)
  if (k >= 4 and k < 9) or (k >= 13 and k < 18) or (k >= 22 and k < 27) then b[d] = true end
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k, b = t - phaseStart, {}
  if phase == "gback" then
    backTap(k, b, dashDir)
  elseif (phase == "jump1" or phase == "jump2") and k < 6 then
    b.up = true
  elseif phase == "air44" then
    backTap(k, b, dashDir)
  elseif phase == "press" then
    if k >= 1 and k < 5 then b.y = true end
  elseif phase == "air66" then
    backTap(k, b, dashDir)
  end
  emu.setInput(PL.pad(b), 0, 0)
  emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

local function setPhase(p)
  log(string.format("t=%4d %s -> %s (act=%02X y=%d ctr=%02X)", t, phase, p, p1(0x01), p1(0x25), p1(0x7F)))
  phase, phaseStart = p, t
end

local VERBOSE = os.getenv("SMS_VERBOSE") == "1"

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  local act = p1(0x01)
  if VERBOSE and (phase == "air44" or phase == "press" or phase == "air66") then
    log(string.format("   t=%4d %s act=%02X stp=%02X st=%02X y=%3d 51=%02X 50=%02X 5B+12=%02X/%02X ctr=%02X",
        t, phase, act, p1(0x02), p1(0x16), p1(0x25), p1(0x51), p1(0x50), p1(0x65), p1(0x66), p1(0x67), p1(0x68), p1(0x7F)))
  end

  if phase == "settle" then
    if k > 70 then
      dashDir = fwdDir() == "right" and "left" or "right"   -- positional back
      setPhase("gback")
    end
  elseif phase == "gback" then
    if act == 0x26 then seen.g44 = true end
    if k > 45 then setPhase("rest1") end
  elseif phase == "rest1" then
    if k > 25 and act == 0 then setPhase("jump1") elseif k > 80 then setPhase("jump1") end
  elseif phase == "jump1" then
    if k > 2 and airborne() then setPhase("air44")
    elseif k > 30 then log("SETUP-FAIL jump1"); LOG:close(); emu.stop(1) end
  elseif phase == "air44" then
    if act == 0x2B then seen.air2B = true; setPhase("press") end
    if k > 45 then setPhase("landwait") end
  elseif phase == "press" then
    if DIR_ACTS[act] and airborne() then seen.cancel = act end
    if k > 25 then setPhase("landwait") end
  elseif phase == "landwait" then
    if not airborne() and act == 0 then setPhase("gap") elseif k > 90 then setPhase("gap") end
  elseif phase == "gap" then
    if k > 15 then
      dashDir = fwdDir()                                   -- positional fwd for the 66
      setPhase("jump2")
    end
  elseif phase == "jump2" then
    if k > 2 and airborne() then setPhase("air66")
    elseif k > 30 then setPhase("report") end
  elseif phase == "air66" then
    if act == 0x2C then seen.air2C = true end
    if k > 45 then setPhase("report") end
  elseif phase == "report" then
    log("")
    log(string.format("== ROSTER c%d%s ==", CID, TAG and (" " .. TAG) or ""))
    log(string.format("   ground 44 -> act 26:   %s", seen.g44 and "OK" or "MISSING"))
    log(string.format("   air 44   -> act 2B:    %s", seen.air2B and "OK" or "no"))
    log(string.format("   dash-cancel LP:        %s", seen.cancel and string.format("act %02X", seen.cancel) or "no"))
    log(string.format("   air 66   -> act 2C:    %s", seen.air2C and "OK" or "no"))
    LOG:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_roster loaded: c" .. CID)
