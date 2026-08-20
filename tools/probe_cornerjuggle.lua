-- probe_cornerjuggle.lua — are CORNER JUGGLES effectively infinite on the
-- anime build? (Decides the maintainer's decay ruling: "juggles should decay
-- iff they don't naturally become impossible, including in corners.")
--
--   ROM=build/exp_animeroster.sfc tools/run.sh tools/probe_cornerjuggle.lua 120
--   -> traces/cornerjuggle.txt
--
-- Setup: P2 walks himself into the wall (holds away until his X saturates),
-- jumps; P1 anti-airs (the launcher) and then mashes jabs while walking in.
-- Mid-screen the launch drift carries the victim out of reach (measured in
-- Phase 0); in the corner the wall holds him in range — the count of re-hits
-- in ONE airborne period is the verdict. >= 8 = effectively infinite.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "cornerjuggle.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local STATE = "venus_vs_jupiter_clean.mss"
local function r(b, o) return PL.ram(b + o) end
local function x16(b) return r(b, 0x21) + 256 * r(b, 0x22) end
local function air(b) return (r(b, 0x16) & 0x80) == 0 end

local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local lastX, stableSince = nil, nil
local hp0, hits, landT, prevHP = nil, {}, nil, nil
local swingUntil, lastVY, cycStart = nil, nil, nil

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_cornerjuggle: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local function dirs()
  local fwd = x16(P1) < x16(P2) and "right" or "left"
  return fwd, fwd
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  local b1, b2 = {}, {}
  local fwd, p2away = dirs()
  if phase == "drive" then
    b2[p2away] = true
    if math.abs(x16(P1) - x16(P2)) > 40 then b1[fwd] = true end
  elseif phase == "vjump" then
    if k < 6 then b2.up = true end
  elseif phase == "antiair" then
    if k >= 16 and k < 20 then b1.x = true end
  elseif phase == "juggle" then
    -- the corner loop a player would do: jump + j.HP each rep (the demo's
    -- juggle route; the wall keeps the victim in reach). cyc = frames since
    -- this rep's jump began.
    if cycStart then
      local c = t - cycStart
      if c < 5 then b1.up = true; b1[fwd] = true
      elseif c >= 7 and c < 11 then b1.x = true
      elseif not air(P1) and c > 15 then cycStart = nil end
    elseif r(P1, 0x01) == 0x00 and air(P2) then
      cycStart = t
      b1.up = true; b1[fwd] = true
    end
  end
  emu.setInput(PL.pad(b1), 0, 0)
  emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  local va = r(P2, 0x01)

  if phase == "settle" then
    if k > 70 then phase, phaseStart = "drive", t end
  elseif phase == "drive" then
    local x = x16(P2)
    if x ~= lastX then lastX, stableSince = x, t end
    if t - (stableSince or t) > 40 then
      log(string.format("t=%4d corner reached: P2 x=%d (P1 x=%d)", t, x, x16(P1)))
      phase, phaseStart = "vjump", t
    elseif k > 400 then log("SETUP-FAIL: no wall found"); LOG:close(); emu.stop(1) end
  elseif phase == "vjump" then
    if k > 2 and air(P2) then hp0 = r(P2, 0x49); prevHP = hp0; phase, phaseStart = "antiair", t
    elseif k > 30 then log("SETUP-FAIL: P2 never jumped"); LOG:close(); emu.stop(1) end
  elseif phase == "antiair" then
    if va >= 0x0E and va <= 0x20 and air(P2) then
      hits[#hits + 1] = t; prevHP = r(P2, 0x49)
      log(string.format("t=%4d LAUNCHER hit (hp %d->%d, y=%d)", t, hp0, prevHP, r(P2, 0x25)))
      phase, phaseStart = "juggle", t
    elseif k > 60 then log("SETUP-FAIL: launcher whiffed"); LOG:close(); emu.stop(1) end
  elseif phase == "juggle" then
    local hp = r(P2, 0x49)
    if hp < prevHP then
      hits[#hits + 1] = t
      log(string.format("t=%4d juggle hit %d (hp %d, y=%d, act=%02X, airborne=%s)",
          t, #hits, hp, r(P2, 0x25), va, tostring(air(P2))))
    end
    prevHP = hp
    if not landT and not air(P2) then landT = t
    elseif landT and air(P2) then landT = nil end          -- re-launched before settling
    if (landT and t > landT + 40) or k > 500 or hp < 20 then
      log("")
      log(string.format("== CORNER JUGGLE VERDICT: %d hits in one sequence (%s) ==",
          #hits, landT and ("victim landed t=" .. landT) or "still airborne at cutoff"))
      log(#hits >= 8 and "   EFFECTIVELY INFINITE -> decay needed per the maintainer ruling"
          or "   naturally bounded -> no decay needed")
      LOG:close(); emu.stop(0)
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_cornerjuggle loaded")
