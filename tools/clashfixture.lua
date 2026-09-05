-- clashfixture.lua — the shared staging for every clash instrument.
--
-- Getting two fighters to clash is the hard part, and it is subtle enough that
-- three private copies of it would be how the next false verdict gets written.
-- This module owns the fixture and nothing else: it loads the savestate, walks
-- the two fighters together, presses the buttons, and hands each frame back to
-- the caller. The caller decides what is true.
--
--   local FIX = ENV.dofile("clashfixture.lua")
--   FIX.stage{
--     dist  = 64,                  -- gap at which the two HITBOXES overlap
--     mash  = function(k, st) ... end,   -- optional: buttons during the contest
--     gate  = true,                -- optional: force the airborne bit (see below)
--     hpset = 192,                 -- optional: poke both fighters' HP and max HP
--     onFrame = function(ctx) ... end,   -- every frame once staging has begun
--     onDone  = function(ctx) ... end,   -- once, when the observation window ends
--     window  = 260,               -- frames of observation after the press
--   }
--
-- ⚠ SMS_DIST=64 IS LOAD-BEARING, and its old default of 56 is trap 28 in this
-- project's ledger: 56 clashes on NOTHING, so every mode reported dead on a
-- build that was fine. 64 is where the two hitboxes actually overlap for this
-- fixture, established by sweeping (62 one-sided, 64/66/68/72 clash).
--
-- ⚠ `gate` exists because a genuine both-airborne clash CANNOT be staged on
-- this fixture. Swept gaps 44-104 against press timings 6-18: those air normals
-- go active on the same frame and still only TRADE, because a clash needs the
-- two HITBOXES to overlap, not merely to reach the opposite body. So the
-- airborne branch is exercised by forcing +0x16 bit 7 from an exec hook on the
-- hooked site itself ($80:BFF5). An endFrame poke does NOT work: the engine
-- re-sets the bit before resolution. Any instrument using `gate` is testing THE
-- GATE, not a real air clash, and must say so in its own output.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$")
  or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")

local M = {}
M.P1, M.P2 = 0x1000, 0x1080
M.STATE = "venus_vs_jupiter_clean.mss"

function M.ram(b, o) return PL.ram(b + o) end
function M.x16(b) return M.ram(b, 0x21) + 256 * M.ram(b, 0x22) end

function M.stage(cfg)
  local P1, P2 = M.P1, M.P2
  local dist = cfg.dist or tonumber(os.getenv("SMS_DIST") or "64")
  local window = cfg.window or 260
  local t, loaded, phase, phaseStart = -1, false, "settle", 0
  local done, gatepokes = false, 0
  -- ctx is what the caller sees. `strug` is the frame the contest opened, which
  -- the mash callback needs in order to press only once the struggle is live.
  local ctx = { t = 0, phase = "settle", strug = nil, gatepokes = 0 }

  if cfg.gate then
    emu.addMemoryCallback(function()
      local f = M.ram(P2, 0x16)
      if f & 0x80 ~= 0 then
        PL.wr(P2 + 0x16, f & 0x7F)
        gatepokes = gatepokes + 1
        ctx.gatepokes = gatepokes
      end
    end, emu.callbackType.exec, 0x80BFF5, 0x80BFF5, emu.cpuType.snes, emu.memType.snesMemory)
  end

  -- load on the input-poll site: a savestate must be restored from a valid
  -- CPU-exec context, which is what $80:8353 gives (probe_acs_select's lesson).
  emu.addMemoryCallback(function()
    if loaded then return end
    local f = io.open(ENV.TRACE .. M.STATE, "rb")
    if not f then print("clashfixture: cannot open " .. M.STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    -- ⚠ The fixture was captured on the CLEAN ROM, so the character loader --
    -- where the A.C.S. max-HP formula runs -- never executes here and HP is
    -- always the vanilla 96. Without this poke no instrument built on this
    -- fixture can say anything about a max-HP change.
    if cfg.hpset then
      for _, b in ipairs({ P1, P2 }) do
        PL.wr(b + 0x49, cfg.hpset); PL.wr(b + 0x4A, cfg.hpset)
      end
    end
    loaded = true; t = 0
  end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

  emu.addEventCallback(function()
    if t < 0 then return end
    local k, b1, b2 = t - phaseStart, {}, {}
    if phase == "approach" then
      b1[M.x16(P1) < M.x16(P2) and "right" or "left"] = true
    elseif phase == "press" then
      if cfg.press then
        cfg.press(k, ctx, b1, b2)
      else
        if k >= 0 and k < 4 then b1.x = true end
        if k >= 0 and k < 4 then b2.x = true end
      end
      if cfg.mash then cfg.mash(k, ctx, b1, b2) end
    end
    emu.setInput(PL.pad(b1), 0, 0)
    emu.setInput(PL.pad(b2), 0, 1)
  end, emu.eventType.inputPolled)

  emu.addEventCallback(function()
    if t < 0 or done then return end
    local k = t - phaseStart
    local a1, a2 = M.ram(P1, 0x04), M.ram(P2, 0x04)
    if not ctx.strug and (a1 == 0x31 or a2 == 0x31) then ctx.strug = t end
    ctx.t, ctx.phase = t, phase
    if cfg.onFrame then cfg.onFrame(ctx) end

    if phase == "settle" then
      if k > 8 then phase, phaseStart = "approach", t end
    elseif phase == "approach" then
      local gap = math.abs(M.x16(P1) - M.x16(P2))
      if gap <= dist then phase, phaseStart = "press", t
      elseif k > 150 then
        print("clashfixture: SETUP-FAIL approach (gap never closed to " .. dist .. ")")
        if cfg.onDone then cfg.onDone(ctx, "SETUP-FAIL approach") end
        done = true; emu.stop(1); return
      end
    elseif phase == "press" then
      -- ⚠ The window must OUTLAST whatever it observes. The contest length is a
      -- build knob (--clash-frames, 180 by default and 90 before 2026-09-05), so
      -- a hard-coded window is one ruling away from reporting a correct build as
      -- broken. Callers pass their own.
      if k > window then
        done = true
        if cfg.onDone then cfg.onDone(ctx, nil) end
        return
      end
    end
    t = t + 1
  end, emu.eventType.endFrame)

  return ctx
end

return M
