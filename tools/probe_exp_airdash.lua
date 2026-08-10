-- probe_exp_airdash.lua — does Venus get an AIR BACKDASH, and is it vulnerable?
--
--   ROM=build/exp_venus_airdash.sfc tools/run.sh tools/probe_exp_airdash.lua 60
--   -> traces/exp_airdash.txt
--
-- Run it on THREE ROMs; the verdicts only mean anything together:
--   clean                          -> AIR phase must find NO act 0x26  (negative control)
--   exp_venus_airdash_invuln.sfc   -> air backdash happens, hurt idx 0 throughout
--   exp_venus_airdash.sfc          -> air backdash happens, hurt idx NONZERO
-- and in all three the GROUND phase must read act 0x26 with hurt idx 0 for its
-- whole duration. That control is the one that matters: the animation swap must
-- not touch the grounded backdash, which is the tool you survive the game with.
--
-- Fixture: traces/venus_vs_jupiter_clean.mss (Venus = P1). The headless
-- testrunner loads a state whose embedded ROM differs from the open one; the
-- GUI would refuse it (HANDOFF §5).
--
-- HARNESS SHAPE, and it is not optional (cost: two dead runs):
--   * the savestate is loaded from an EXEC callback on $80:8353, the joy-read
--     anchor — not from endFrame. `emu.loadSavestate` takes the state DATA, and
--     calling it from the wrong context or with a path THROWS, and a throw
--     inside a callback dies with no message (HANDOFF trap 12). Both failures
--     look identical from outside: an empty log and a run to the wall-clock
--     timeout, i.e. exactly like "the game never did the thing" (trap 9).
--   * inputs are written in inputPolled, which precedes that exec site.
--
-- "Back" is DERIVED from the two x positions, never assumed: it is a direction
-- only relative to where the opponent stands, and a probe that guesses it
-- reports "she never backdashed" for reasons that have nothing to do with the
-- game (the lesson probe_guardcancel.lua paid for).
--
-- The double-tap needs two fresh back EDGES inside the recognizer's 15-frame
-- window ($C1:1618 `cmp #$0F`), so the pattern is tap / release / tap with real
-- gaps — holding back does not arm it (HANDOFF: "release and re-tap fresh").
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "exp_airdash.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local ACT, ANIM, STATUS, XPIX, YPIX, HURT = 0x01, 0x04, 0x16, 0x21, 0x25, 0x41
local STATE = "venus_vs_jupiter_clean.mss"

local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local ground, air = {}, {}

local function p1(o) return PL.ram(P1 + o) end
local function backDir()                 -- derived every time it is needed
  return PL.ram(P1 + XPIX) > PL.ram(P2 + XPIX) and "left" or "right"
end
local function airborne() return (PL.ram(P1 + STATUS) & 0x80) == 0 end
local function setPhase(p)
  log(string.format("t=%4d  %s -> %s   (act=%02X st=%02X y=%d)",
                    t, phase, p, p1(ACT), p1(STATUS), p1(YPIX)))
  phase, phaseStart = p, t
end

-- ---------------------------------------------------------------- load --
emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_exp_airdash: cannot open " .. ENV.TRACE .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

-- --------------------------------------------------------------- input --
emu.addEventCallback(function()
  if t < 0 then return end
  local k, b = t - phaseStart, {}
  if phase == "ground" or phase == "air" then
    local d = backDir()
    if (k >= 0 and k < 5) or (k >= 9 and k < 14) then b[d] = true end
  elseif phase == "jump" and k < 6 then
    b.up = true
  end
  emu.setInput(PL.pad(b), 0, 0)          -- port is the 3rd arg (HANDOFF §5)
  emu.setInput(PL.pad(), 0, 1)           -- P2 inert all run
end, emu.eventType.inputPolled)

-- ------------------------------------------------------- sample + plan --
local function snap()
  return { t = t, act = p1(ACT), anim = p1(ANIM), hurt = p1(HURT),
           st = p1(STATUS), x = p1(XPIX), y = p1(YPIX),
           step = p1(0x02), cmd = p1(0x51), held = p1(0x50) }
end
local function fmt(r)
  return string.format("t=%4d act=%02X stp=%02X anim=%02X hurt=%02X st=%02X x=%3d y=%3d cmd=%02X held=%02X",
                       r.t, r.act, r.step, r.anim, r.hurt, r.st, r.x, r.y, r.cmd, r.held)
end

local function report(name, rs)
  log(""); log("== " .. name .. " ==")
  local hurts, frames, ks = {}, 0, {}
  local acts = {}
  for _, r in ipairs(rs) do
    log("   " .. fmt(r))
    if r.act == 0x26 or r.act == 0x2B then      -- 0x2B = the experiment's air act
      frames = frames + 1
      acts[r.act] = (acts[r.act] or 0) + 1
      hurts[r.hurt] = (hurts[r.hurt] or 0) + 1
    end
  end
  local an = {}
  for a in pairs(acts) do an[#an + 1] = string.format("%02X x%d", a, acts[a]) end
  table.sort(an)
  if frames == 0 then
    log("   NO backdash act (26/2B) in this phase")
    for i = 1, math.min(#rs, 10) do log("   ctx " .. fmt(rs[i])) end
    return
  end
  for h in pairs(hurts) do ks[#ks + 1] = h end
  table.sort(ks)
  local parts = {}
  for _, h in ipairs(ks) do parts[#parts + 1] = string.format("%02X x%d", h, hurts[h]) end
  log(string.format("   VERDICT: %d frames of act %s; hurt idx %s  -> %s",
        frames, table.concat(an, ","), table.concat(parts, ", "),
        (#ks == 1 and ks[1] == 0) and "FULLY INVULNERABLE"
        or (hurts[0] and "PARTIALLY invulnerable") or "VULNERABLE throughout"))
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart

  if phase == "settle" then
    if k > 70 then setPhase("ground") end
  elseif phase == "ground" then
    if k >= 6 then ground[#ground + 1] = snap() end
    if k > 60 then setPhase("rest") end
  elseif phase == "rest" then
    if k > 30 then setPhase("jump") end
  elseif phase == "jump" then
    if k > 6 and airborne() then setPhase("air") end
    if k > 90 then setPhase("done") end          -- never left the ground
  elseif phase == "air" then
    air[#air + 1] = snap()
    if k > 70 then setPhase("done") end
  elseif phase == "done" then
    log(""); log("probe_exp_airdash — Venus air backdash")
    report("GROUND phase (control: must be act 26 / hurt 00)", ground)
    report("AIR phase (the experiment)", air)
    LOG:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_airdash loaded")
