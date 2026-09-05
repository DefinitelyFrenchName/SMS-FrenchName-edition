-- test_clash_air.lua — an AIRBORNE participant never gets the mash contest.
--
-- The ruling (maintainer, 2026-08-24): a GROUND clash opens the mash contest;
-- if either fighter is airborne the clash stays the v9 answer, an instant
-- mutual backdash. This test asserts that, and asserts the negative too — that
-- the airborne path does NOT stage a contest.
--
--   ROM=build/sms-anime.sfc tools/run.sh tools/test_clash_air.lua 200
--   -> traces/test_clash_air.txt, last line ALL PASS (n) or FAILURES (k/n)
--
-- Two cases, one per invocation:
--   SMS_CASE=gate   the airborne bit is forced at the resolution site. THE
--                   DEFAULT, because it is the case that actually stages.
--   SMS_CASE=jump   P2 jumps IN and swings while P1 swings on the ground.
--                   ⚠ DOES NOT STAGE on this fixture -- see below. Kept so the
--                   attempt is repeatable, and it reports SETUP-FAIL rather
--                   than pretending the ruling broke.
--
-- ⚠⚠ READ THIS BEFORE BELIEVING THE `gate` CASE. A genuine BOTH-airborne clash
-- cannot be staged on this fixture at all. Swept gaps 44-104 against press
-- timings 6-18: the two air normals go active on the same frame and still only
-- TRADE, because a clash needs the two HITBOXES to overlap, not merely to reach
-- the opposite body. So `gate` forces +0x16 bit 7 from an exec hook on the
-- hooked site itself ($80:BFF5) -- an endFrame poke does not work, the engine
-- re-sets the bit before resolution. That case therefore proves the GATE READS
-- THE BIT; it does not prove two airborne fighters clash correctly, and it is
-- reported as such rather than dressed up as a pass.
--
-- ⚠ AND THE `jump` CASE DOES NOT STAGE EITHER. One airborne participant is all
-- the ruling needs, and jumping in is far easier to arrange than two air
-- normals meeting -- but on this fixture it still produces no clash at all.
-- Swept SMS_P1PRESS {4,8,12} x SMS_AIRPRESS {6,10,14} on 2026-09-05: nine
-- combinations, zero clashes, no damage either, which is the probe's own
-- `mashjump` verdict ("NO CLASH STAGED (says nothing on its own)") reached
-- independently. So `gate` is currently the ONLY case that exercises the rule,
-- and this test says so out loud instead of shipping a green tick.
--
-- A test that reports "the rule is broken" when it merely failed to stage is
-- the exact false verdict this project keeps paying for (trap 28). So the
-- outcome checks below run only once a clash is proven to have RESOLVED; with
-- no clash the run is SETUP-FAIL, which is a different thing from FAIL.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$")
  or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local FIX = ENV.dofile("clashfixture.lua")

local CASE = os.getenv("SMS_CASE") or "gate"
local AIRPRESS = tonumber(os.getenv("SMS_AIRPRESS") or "10")
local P1PRESS = tonumber(os.getenv("SMS_P1PRESS") or "8")
local LOG = assert(io.open(ENV.TRACE .. "test_clash_air.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local P1, P2 = FIX.P1, FIX.P2
local results = {}
local function check(name, ok, msg)
  results[#results + 1] = { name = name, ok = ok, msg = msg }
  log(string.format("%s %-34s %s", ok and "PASS" or "FAIL", name, msg or ""))
end

local seen1, seen2 = {}, {}
local airAtClash = nil            -- was P2 airborne when the clash resolved?
local hp1, hp2 = nil, nil

log("test_clash_air  case=" .. CASE)
if CASE == "gate" then
  log("  ⚠ this case FORCES the airborne bit at $80:BFF5. It proves the gate")
  log("    reads the bit; it does NOT prove two airborne fighters clash.")
end

FIX.stage{
  window = 150,
  gate = (CASE == "gate"),
  press = function(k, ctx, b1, b2)
    if CASE == "jump" then
      -- P1 stands and swings; P2 jumps IN and swings. ONE airborne participant
      -- is all the ruling needs, and unlike a both-airborne clash it stages.
      if k < 3 then
        b2.up = true
        b2[FIX.x16(P2) < FIX.x16(P1) and "right" or "left"] = true
      end
      if k >= P1PRESS and k < P1PRESS + 4 then b1.x = true end
      if k >= AIRPRESS and k < AIRPRESS + 4 then b2.x = true end
    else
      if k >= 0 and k < 4 then b1.x = true; b2.x = true end
    end
  end,
  onFrame = function(ctx)
    local a1, a2 = FIX.ram(P1, 0x04), FIX.ram(P2, 0x04)
    if not seen1[a1] then seen1[a1] = ctx.t end
    if not seen2[a2] then seen2[a2] = ctx.t end
    if hp1 == nil then hp1, hp2 = FIX.ram(P1, 0x49), FIX.ram(P2, 0x49) end
    -- the backdash acts are the clash's v9 answer: $26 grounded, $2B airborne
    if airAtClash == nil and (a1 == 0x26 or a1 == 0x2B or a2 == 0x26 or a2 == 0x2B) then
      airAtClash = (FIX.ram(P2, 0x16) & 0x80) ~= 0
    end
  end,
  onDone = function(ctx, setupfail)
    if setupfail then
      check("staging", false, setupfail)
    else
      check("staging", true, "fixture reached the press")

      local backdashed = (seen1[0x26] or seen1[0x2B]) and (seen2[0x26] or seen2[0x2B])
      local contested = seen1[0x31] ~= nil or seen2[0x31] ~= nil
      local damaged = FIX.ram(P1, 0x49) ~= hp1 or FIX.ram(P2, 0x49) ~= hp2
      -- Did anything resolve AT ALL? A clash leaves one of three marks: the
      -- backdash acts, the contest act, or (if the two attacks merely met
      -- without clashing) damage. None of the three means the fixture never got
      -- the two hitboxes to overlap -- a STAGING failure. Reporting that as
      -- "the ruling broke" would be a lie, so it stops here instead.
      local resolved = backdashed or contested or damaged
      if not resolved then
        log("")
        log("SETUP-FAIL: no clash staged — no backdash, no contest, no damage.")
        log("  This says NOTHING about the airborne ruling. The `jump` case is")
        log("  known not to stage on this fixture (see the header); use")
        log("  SMS_CASE=gate, which does.")
        LOG:close(); emu.stop(2); return
      end

      if CASE == "gate" then
        check("the gate fired at all", (ctx.gatepokes or 0) > 0,
          (ctx.gatepokes or 0) .. " pokes at $80:BFF5")
      end

      -- THE RULING, both halves. The negative is the one that matters: it is
      -- not enough that a backdash happened, the contest must NOT have opened.
      check("no mash contest with an airborne participant", not contested,
        contested and ("act $31 appeared: P1 @" .. tostring(seen1[0x31])
                       .. ", P2 @" .. tostring(seen2[0x31]))
                   or "neither fighter entered act $31")
      check("both fighters backdash", backdashed and true or false,
        string.format("P1 $26@%s $2B@%s   P2 $26@%s $2B@%s",
          tostring(seen1[0x26]), tostring(seen1[0x2B]),
          tostring(seen2[0x26]), tostring(seen2[0x2B])))

      -- a clash damages nobody: if either lost HP this was a trade, and a trade
      -- is exactly what an unstaged "air clash" degenerates into
      local d1 = (FIX.ram(P1, 0x49) ~= hp1)
      local d2 = (FIX.ram(P2, 0x49) ~= hp2)
      check("nobody was damaged", not d1 and not d2,
        string.format("P1 hp %s->%s, P2 hp %s->%s", tostring(hp1),
          FIX.ram(P1, 0x49), tostring(hp2), FIX.ram(P2, 0x49)))

      if CASE == "jump" and airAtClash ~= nil then
        check("the airborne one really was airborne", airAtClash,
          "+0x16 bit 7 set on P2 at the clash")
      end
    end

    local bad = 0
    for _, r in ipairs(results) do if not r.ok then bad = bad + 1 end end
    log("")
    if CASE == "gate" then
      log("  NOTE: `gate` forces the bit. A real both-airborne clash is not")
      log("        stageable on this fixture; see the header.")
    end
    log(bad == 0 and ("ALL PASS (" .. #results .. ")")
                 or ("FAILURES (" .. bad .. "/" .. #results .. ")"))
    LOG:close()
    emu.stop(bad == 0 and 0 or 1)
  end,
}
