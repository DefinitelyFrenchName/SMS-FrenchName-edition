-- probe_airphys.lua — air physics, landing, and the air-special start,
-- observed per frame. (Phase 1 of the anime-fighter feasibility programme.)
--
--   SMS_APROBE=jumps   tools/run.sh tools/probe_airphys.lua 90
--       -> traces/airphys_jumps.txt   (fixture: venus_vs_jupiter_clean.mss)
--     P1 performs neutral, forward and back jumps; +0x30/+0x32/+0x34 logged
--     signed per frame. M1.1: which field sweeps under gravity (Yvel) and
--     which stays constant (gravity) ON THE PLAYER PATH — the reaction-
--     template doc says "+0x32/+0x34 launch velocities", the struct doc says
--     +0x32 Yvel / +0x34 gravity; the sweep decides. M1.2: the frame order of
--     y reaching ground, +0x16 bit7 setting, and act 0x09 staging.
--
--   SMS_APROBE=airspec SMS_D=8 tools/run.sh tools/probe_airphys.lua 90
--       -> traces/airphys_airspec_d8.txt (fixture: chibi_vs_venus_clean.mss)
--     P1 ChibiMoon jumps forward and does j.2K (Swinging Marshmallow, the
--     roster's simplest air-special input: motion m2 masks 04,A0 = down then
--     both kicks; acts 0x65/0x66, flag 0x02 air-only). M1.3: does the act
--     truncate on landing, or does its recovery continue grounded? M1.4: the
--     +0x51 latch's lifecycle around a LEGITIMATE air-special start — does
--     the starter re-fire the act's step 0 while the nibble stays latched?
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")

local WHAT = os.getenv("SMS_APROBE") or "jumps"
local D = tonumber(os.getenv("SMS_D") or "8")       -- airspec: frames airborne before the input
local STATE = WHAT == "jumps" and "venus_vs_jupiter_clean.mss" or "chibi_vs_venus_clean.mss"
local OUT = WHAT == "jumps" and "airphys_jumps.txt"
    or string.format("airphys_airspec_d%d%s.txt", D, os.getenv("SMS_JDIR") == "back" and "_back" or "")
local LOG = assert(io.open(ENV.TRACE .. OUT, "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local function r(o) return PL.ram(P1 + o) end
local function s16(o)
  local v = r(o) + 256 * r(o + 1)
  return v >= 0x8000 and v - 0x10000 or v
end
local function airborne() return (r(0x16) & 0x80) == 0 end

local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local rows, section = {}, nil

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_airphys: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local function fwdDir()
  local x1 = r(0x21) + 256 * r(0x22)
  local x2 = PL.ram(P2 + 0x21) + 256 * PL.ram(P2 + 0x22)
  return x1 < x2 and "right" or "left", x1 > x2 and "right" or "left"
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k, b = t - phaseStart, {}
  if WHAT == "jumps" then
    if (phase == "nj" or phase == "fj" or phase == "bj") and k < 6 then
      b.up = true
      local fwd, back = fwdDir()
      if phase == "fj" then b[fwd] = true elseif phase == "bj" then b[back] = true end
    end
  else -- airspec
    if phase == "fj" then
      if k < 6 then
        b.up = true
        local fwd, back = fwdDir()
        b[(os.getenv("SMS_JDIR") == "back") and back or fwd] = true
      elseif k >= 6 + D and k < 6 + D + 4 then
        b.down = true
      elseif k >= 6 + D + 4 and k < 6 + D + 9 then
        b.down = true; b.b = true; b.a = true
      end
    end
  end
  emu.setInput(PL.pad(b), 0, 0)
  emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

local function snap()
  return string.format("t=%4d act=%02X stp=%02X st=%02X y=%3d xv=%6d yv=%6d gv=%6d 51=%02X 50=%02X",
      t, r(0x01), r(0x02), r(0x16), r(0x25), s16(0x30), s16(0x32), s16(0x34), r(0x51), r(0x50))
end

local SEQ = WHAT == "jumps" and { "nj", "fj", "bj" } or { "fj" }
local seqi = 0

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart

  if phase == "settle" then
    if k > 70 then
      seqi = seqi + 1
      log(""); log("== " .. SEQ[seqi] .. " ==")
      phase, phaseStart = SEQ[seqi], t
    end
  elseif phase ~= "done" then
    log("   " .. snap())
    -- run each section until landed-and-neutral again, with a hard cap
    if (k > 15 and not airborne() and r(0x01) == 0x00) or k > 160 then
      if seqi < #SEQ then
        seqi = seqi + 1
        log(""); log("== " .. SEQ[seqi] .. " ==")
        phase, phaseStart = SEQ[seqi], t
      else
        phase = "done"
        log(""); log("probe_airphys " .. WHAT .. " done")
        LOG:close(); emu.stop(0)
      end
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_airphys loaded: " .. WHAT)
