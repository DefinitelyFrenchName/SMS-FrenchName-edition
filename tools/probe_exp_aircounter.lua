-- probe_exp_aircounter.lua — is the air-action BUDGET honored and reset?
-- (Phase 5 of the anime-fighter feasibility programme. Companion of
-- tools/exp_aircounter.py; fixture uranus_vs_jupiter_clean.mss.)
--
--   ROM=<budget1 build> tools/run.sh tools/probe_exp_aircounter.lua 90   (SMS_TAG=n1)
--   ROM=<budget2 build> SMS_TAG=n2 tools/run.sh ...
--
-- One scripted airborne period tries to spend TWO dashes: jump fwd -> air
-- dash -> j.HP (dash-cancel) -> whiff -> double-tap again. Then a second
-- jump tries one dash. Expectations: n1 = 1 dash in jump 1 (second attempt
-- REFUSED), dash works in jump 2 (landing reset); n2 = 2 dashes in jump 1.
-- The counter byte +0x7F is sampled throughout; it must read 0 at settle
-- (the round init's value — unverified until here), N after spends, 0 after
-- landing.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local TAG = os.getenv("SMS_TAG") or "n1"
local LOG = assert(io.open(ENV.TRACE .. "exp_aircounter_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local STATE = "uranus_vs_jupiter_clean.mss"
local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local rows = {}
local dashDirB = nil

local function p1(o) return PL.ram(P1 + o) end
local function airborne() return (p1(0x16) & 0x80) == 0 end
local function x16(b) return PL.ram(b + 0x21) + 256 * PL.ram(b + 0x22) end
local function fwdDir() return x16(P1) < x16(P2) and "right" or "left" end
local function setPhase(p)
  log(string.format("t=%4d  %s -> %s  (act=%02X ctr=%02X)", t, phase, p, p1(0x01), p1(0x7F)))
  phase, phaseStart = p, t
end

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_exp_aircounter: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  local k, b = t - phaseStart, {}
  local fwd = fwdDir()
  if phase == "jump1" and k < 6 then
    b.up = true; b[fwd] = true
  elseif phase == "jump2" and k < 6 then
    b.up = true                                   -- neutral: spacing-independent
  elseif phase == "dash66" or phase == "tap2" then
    if (k >= 0 and k < 5) or (k >= 9 and k < 14) then b[fwd] = true end
  elseif phase == "dash66b" then
    -- positional BACK, sampled once: the 44 pair is spacing-stable. Leading
    -- neutral frames + three windows: the recognizer needs a registered
    -- neutral before tap 1, and an extra tap is harmless.
    dashDirB = dashDirB or (fwd == "right" and "left" or "right")
    if (k >= 4 and k < 9) or (k >= 13 and k < 18) or (k >= 22 and k < 27) then b[dashDirB] = true end
  elseif phase == "press" and k < 4 then
    b.x = true
  end
  emu.setInput(PL.pad(b), 0, 0)
  emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

local function snap()
  return string.format("t=%4d act=%02X stp=%02X st=%02X y=%3d ctr=%02X 51=%02X 50=%02X 5B=%02X 5C=%02X x=%4d",
      t, p1(0x01), p1(0x02), p1(0x16), p1(0x25), p1(0x7F), p1(0x51), p1(0x50), p1(0x5B), p1(0x5C), x16(P1))
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  local act = p1(0x01)
  if phase ~= "settle" and phase ~= "report" then rows[#rows + 1] = snap() end

  if phase == "settle" then
    if k == 10 then
      log(string.format("settle: counter +0x7F = %02X (must be 00)", p1(0x7F)))
      if p1(0x7F) ~= 0 then log("SETUP-FAIL: counter not zero at round start"); LOG:close(); emu.stop(1); return end
    end
    if k > 70 then setPhase("jump1") end
  elseif phase == "jump1" then
    if k > 2 and airborne() then setPhase("dash66")
    elseif k > 30 then log("SETUP-FAIL: never airborne"); LOG:close(); emu.stop(1) end
  elseif phase == "dash66" then
    if act == 0x2C or act == 0x2B then setPhase("press") end
    if k > 40 then setPhase("landwait") end
  elseif phase == "press" then
    if act >= 0x4B and act <= 0x52 then setPhase("tap2") end
    if k > 30 then setPhase("landwait") end
  elseif phase == "tap2" then
    if k > 20 then setPhase("landwait") end
  elseif phase == "landwait" then
    if not airborne() and act == 0x00 then setPhase("gap") end
    if k > 90 then setPhase("gap") end
  elseif phase == "gap" then
    if k > 15 then setPhase("jump2") end
  elseif phase == "jump2" then
    if k > 2 and airborne() then setPhase("dash66b")
    elseif k > 30 then setPhase("report") end
  elseif phase == "dash66b" then
    if k > 40 then setPhase("report") end
  elseif phase == "report" then
    log("")
    for _, s in ipairs(rows) do log("   " .. s) end
    log("")
    -- count dash EPISODES (entries into 2B/2C) per airborne period
    local ep1, ep2, prev, secondJump = 0, 0, nil, false
    local maxCtr, ctrAfterLand = 0, nil
    for i, s in ipairs(rows) do
      local a = tonumber(s:match("act=(%x+)"), 16)
      local c = tonumber(s:match("ctr=(%x+)"), 16)
      local st = tonumber(s:match("st=(%x+)"), 16)
      if not secondJump and prev and (st & 0x80) == 0x80 and c == 0 and i > 30 then secondJump = true end
      if (a == 0x2B or a == 0x2C) and prev ~= 0x2B and prev ~= 0x2C then
        if secondJump then ep2 = ep2 + 1 else ep1 = ep1 + 1 end
      end
      if c > maxCtr then maxCtr = c end
      if (st & 0x80) == 0x80 and not ctrAfterLand and i > 30 then ctrAfterLand = c end
      prev = a
    end
    log(string.format("== VERDICT %s ==", TAG))
    log(string.format("   dash episodes: jump1=%d  jump2=%d", ep1, ep2))
    log(string.format("   counter: max=%d, first grounded sample after jump1=%s", maxCtr, tostring(ctrAfterLand)))
    LOG:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_aircounter loaded: " .. TAG)
