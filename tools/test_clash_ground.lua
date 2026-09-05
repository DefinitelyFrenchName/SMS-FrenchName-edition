-- test_clash_ground.lua — the GROUND clash is a mash contest, and it resolves.
--
-- A test, not a probe: every claim below is asserted, the result is PASS/FAIL
-- per claim, and the run exits non-zero if any of them fails. The exploratory
-- instrument is tools/probe_exp_clash.lua; this one is the gate.
--
--   ROM=build/sms-anime.sfc tools/run.sh tools/test_clash_ground.lua 240
--   -> traces/test_clash_ground.txt, last line ALL PASS (n) or FAILURES (k/n)
--
-- Env: SMS_CFRAMES (contest length the build was made with; default 180, must
--      match --clash-frames), SMS_DIST (default 64 — see clashfixture.lua).
--
-- The three scenarios each need their own run of the fixture, so this script
-- runs ONE of them per invocation and the caller loops:
--   SMS_CASE=win  P1 mashes, P2 does not      -> P1 to neutral, P2 wall-flies
--   SMS_CASE=tie  neither mashes              -> P2 WINS (the 2026-09-05 rule)
--   SMS_CASE=hold P1 holds one button         -> a hold is ONE press, not a mash
-- Default runs `win`.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$")
  or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local FIX = ENV.dofile("clashfixture.lua")

local CASE = os.getenv("SMS_CASE") or "win"
local CFRAMES = tonumber(os.getenv("SMS_CFRAMES") or "") or 180
local LOG = assert(io.open(ENV.TRACE .. "test_clash_ground.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local P1, P2 = FIX.P1, FIX.P2
local results = {}
local function check(name, ok, msg)
  results[#results + 1] = { name = name, ok = ok, msg = msg }
  log(string.format("%s %-34s %s", ok and "PASS" or "FAIL", name, msg or ""))
end

-- observables
local seen1, seen2 = {}, {}      -- act -> first frame
local boxdirt, endc1, endc2 = 0, nil, nil
local strugEnd, steps = nil, {}

log("test_clash_ground  case=" .. CASE .. "  contest=" .. CFRAMES .. "f")

FIX.stage{
  window = CFRAMES + 80,
  -- P1 mashes two buttons on a 3-frame cadence once the contest is live; P2
  -- never touches one, so the counts must separate. `hold` leans on a single
  -- button instead, which must count ONCE.
  mash = function(k, ctx, b1, b2)
    if not ctx.strug or k < 6 then return end
    if CASE == "win" then
      local m = (ctx.t - ctx.strug) % 6
      if m == 0 then b1.x = true elseif m == 3 then b1.y = true end
    elseif CASE == "hold" then
      b1.x = true
    end
    -- CASE == "tie": nobody mashes
  end,
  onFrame = function(ctx)
    local a1, a2 = FIX.ram(P1, 0x04), FIX.ram(P2, 0x04)
    if not seen1[a1] then seen1[a1] = ctx.t end
    if not seen2[a2] then seen2[a2] = ctx.t end
    -- the contest must carry NO boxes on either fighter. The handler runs after
    -- the box writer's per-object batch, so a nonzero here is the frame-order
    -- claim failing, not a timing accident.
    if a1 == 0x31 and (FIX.ram(P1, 0x40) ~= 0 or FIX.ram(P1, 0x41) ~= 0) then boxdirt = boxdirt + 1 end
    if a2 == 0x31 and (FIX.ram(P2, 0x40) ~= 0 or FIX.ram(P2, 0x41) ~= 0) then boxdirt = boxdirt + 1 end
    if a1 == 0x31 or a2 == 0x31 then
      endc1, endc2 = FIX.ram(P1, 0x7C) & 0x7F, FIX.ram(P2, 0x7C) & 0x7F
      strugEnd = ctx.t
      steps[#steps + 1] = FIX.ram(P1, 0x02)
    end
  end,
  onDone = function(ctx, setupfail)
    if setupfail then
      check("staging", false, setupfail)
    else
      check("staging", true, "fixture reached the press")

      -- 1. the contest opened, on both fighters, on the same frame
      check("contest opens on both", seen1[0x31] ~= nil and seen2[0x31] ~= nil,
        string.format("P1 act $31 @%s, P2 @%s", tostring(seen1[0x31]), tostring(seen2[0x31])))
      if seen1[0x31] and seen2[0x31] then
        check("contest opens simultaneously", seen1[0x31] == seen2[0x31],
          string.format("%d vs %d", seen1[0x31], seen2[0x31]))
      end

      -- 2. no boxes for its whole length: an empty hurtbox IS this engine's
      --    invulnerability, and it is what keeps a stray projectile out
      check("no boxes during the contest", boxdirt == 0, boxdirt .. " dirty frames")

      -- 3. it lasts as long as the build says it does
      if seen1[0x31] and strugEnd then
        local ran = strugEnd - seen1[0x31] + 1
        check("contest length matches the build",
          math.abs(ran - CFRAMES) <= 3,
          string.format("%d frames, expected %d", ran, CFRAMES))
      end

      -- 4. the jab LOOPS rather than holding on its last pose
      local wraps, prev = 0, nil
      for _, st in ipairs(steps) do
        if prev and st < prev then wraps = wraps + 1 end
        prev = st
      end
      check("the animation loops", wraps >= 3, wraps .. " step wraps during the contest")

      -- 5. the outcome
      if CASE == "win" then
        check("P1 out-mashed P2", (endc1 or 0) > (endc2 or 0),
          string.format("counts %d vs %d", endc1 or -1, endc2 or -1))
        check("winner returns to neutral", seen1[0x00] ~= nil and seen1[0x2F] == nil,
          "P1 act $00 and never $2F")
        check("loser takes the wall-fly", seen2[0x2F] ~= nil and seen2[0x16] ~= nil,
          "P2 act $2F then $16 (air hitstun) -> juggle-soft")
      elseif CASE == "tie" then
        check("the counts really tied", (endc1 or 0) == (endc2 or 0),
          string.format("counts %d vs %d", endc1 or -1, endc2 or -1))
        -- ⚠ RULE, maintainer 2026-09-05: a tie is NOT a mutual backdash any
        -- more. P2 wins it, in the grand SMS tradition.
        check("a tie gives P2 the clash", seen2[0x00] ~= nil and seen2[0x2F] == nil,
          "P2 to neutral, never wall-flew")
        check("a tie sends P1 flying", seen1[0x2F] ~= nil, "P1 act $2F")
      elseif CASE == "hold" then
        -- a held button is ONE press. If this fails the contest rewards leaning
        -- on a button, which is not a mash contest.
        check("holding is not mashing", (endc1 or 0) <= 2,
          "P1 held one button all contest, count = " .. (endc1 or -1))
      end
    end

    local bad = 0
    for _, r in ipairs(results) do if not r.ok then bad = bad + 1 end end
    log("")
    log(bad == 0 and ("ALL PASS (" .. #results .. ")")
                 or ("FAILURES (" .. bad .. "/" .. #results .. ")"))
    LOG:close()
    emu.stop(bad == 0 and 0 or 1)
  end,
}
