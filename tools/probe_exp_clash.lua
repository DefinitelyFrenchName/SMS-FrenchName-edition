-- probe_exp_clash.lua — do two hits meeting in their first active frames
-- CLASH (both pushed back, nobody damaged)? (Companion of the clash wiring
-- in tools/exp_animeroster.py.)
--
--   SMS_CMODE=sim     ROM=build/exp_animeroster.sfc tools/run.sh tools/probe_exp_clash.lua 90
--   SMS_CMODE=stagger ROM=build/exp_animeroster.sfc ...  (P2 presses 8f late: must HIT)
--   SMS_CMODE=sim     (clean ROM) SMS_TAG=clean          (must TRADE, vanilla)
--   SMS_CMODE=mash    ROM=<mash build> ... 240           (P1 mashes, P2 does not)
--   SMS_CMODE=mashtie ROM=<mash build> ... 240           (neither mashes -> both backdash)
--   SMS_CMODE=mashair  ROM=<mash build> ... 240          (both airborne — see the note)
--   SMS_CMODE=mashjump ROM=<mash build> ... 240          (P2 jumps in — see the note)
--   SMS_CMODE=mashgate ROM=<mash build> ... 240          (P2 airborne AT the test -> v9)
--   -> traces/clash_<mode>[_tag].txt
--
-- Both fighters press HP on the same frame at a spacing where the two
-- hitboxes meet. Expected on the v9 build: neither takes damage and both are
-- set to their backdash act (0x26 grounded / 0x2B airborne). SMS_DIST sweeps
-- the spacing; the clash window is a build knob (--clash N).
--
-- On a `--clash-mode mash` build a GROUND clash instead opens the contest:
-- both fighters go to act 0x31 with NO boxes (+0x40/+0x41 are logged every
-- frame, which is also the check that the handler runs after the box writer),
-- each mashed press is counted in +0x7C, and at expiry the higher count wins:
-- winner to neutral, loser to the wall-fly act 0x2F (juggle-soft), a tie to
-- the v9 mutual backdash. An AIR clash keeps the backdash on every build.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = os.getenv("SMS_CMODE") or "sim"
local MASH = MODE == "mash" or MODE == "mashtie" or MODE == "mashair"
    or MODE == "mashjump" or MODE == "mashgate" or MODE == "mashhold"
-- how long the build under test runs its contest (tools/exp_animeroster.py
-- --clash-frames). Default tracks the generator's own default.
local CFRAMES = tonumber(os.getenv("SMS_CFRAMES") or "") or 180
local HPSET = tonumber(os.getenv("SMS_HPSET") or "") or nil
local TAG = os.getenv("SMS_TAG")
-- 64 is where the two HITBOXES overlap for this fixture: measured by
-- sweeping (62 -> one-sided hit, 64/66/68/72 -> CLASH on the v9 build).
-- The old default of 56 clashed on NOTHING and made every mode look dead.
local DIST = tonumber(os.getenv("SMS_DIST") or "64")
local STAG = tonumber(os.getenv("SMS_STAGGER") or "8")
-- P2's press offset in frames, signed: negative = P2 presses EARLIER. The two
-- fixture characters have different startups (Venus 5HP is faster than
-- Jupiter's), so "both press on the same frame" is NOT "both active on the same
-- frame" — which is what a clash actually needs. Measured on the v9 build by
-- sweeping this; see the header table.
local P2OFF = tonumber(os.getenv("SMS_P2OFF") or "0")
local AIRPRESS = tonumber(os.getenv("SMS_AIRPRESS") or "10")   -- air modes: press, frames after the jump
local P1PRESS = tonumber(os.getenv("SMS_P1PRESS") or "8")      -- mashjump: P1's ground press
local LOG = assert(io.open(ENV.TRACE .. "clash_" .. MODE .. (TAG and ("_" .. TAG) or "") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local STATE = "venus_vs_jupiter_clean.mss"
local function r(b, o) return PL.ram(b + o) end
local function x16(b) return r(b, 0x21) + 256 * r(b, 0x22) end

-- mashgate: clear P2's grounded bit (+0x16 bit7) at the instant the clash test
-- reads it — an exec hook on the hooked site itself ($80:BFF5, the resolution's
-- target-selection block, which runs from the $80 mirror). An endFrame poke
-- does NOT work and was tried first: the engine re-sets the bit before
-- resolution, so the gate saw a grounded fighter and the contest opened.
local gatepokes = 0
if MODE == "mashgate" then
  emu.addMemoryCallback(function()
    local f = PL.ram(0x1080 + 0x16)
    if f & 0x80 ~= 0 then
      PL.wr(0x1080 + 0x16, f & 0x7F)
      gatepokes = gatepokes + 1
    end
  end, emu.callbackType.exec, 0x80BFF5, 0x80BFF5, emu.cpuType.snes, emu.memType.snesMemory)
end

local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local rows, hp1, hp2 = {}, nil, nil
local clash1, clash2, dmg1, dmg2 = nil, nil, nil, nil
-- mash-contest observables
local strug1, strug2, boxdirt = nil, nil, 0
local seen1, seen2 = {}, {}          -- act -> first frame, per fighter
local anim = {}                      -- the struggle's +0x05/+0x06/+0x07, P1
local endc1, endc2 = nil, nil        -- the two counts at resolution
-- SFXWATCH=1: every write to the GLOBAL one-shot sound slot, with the frame.
-- ⚠ This block MUST stay below `local t`. Declared above it, the callback's
-- closure captures a nil GLOBAL t instead of the frame counter, every entry
-- records t=nil, and the report dies inside string.format -- which looks
-- exactly like "the sound never fired": the header prints and not one row
-- follows. Cost an hour on 2026-09-05.
-- The contest re-requests its sound on each animation cycle, and "it should
-- fire every 7 frames" is a claim about a byte, so watch the byte.
-- ⚠ Watch BOTH mirrors: procs run with DB such that $78 is direct-page
-- $00:0078, while a bus watch on $7E:0078 sees the WRAM address. The repo's
-- sound probes (saturn/probe_hitsfx.lua) watch both for exactly this reason;
-- a single-address watch is how you conclude "no sound is ever played".
local sfx = {}
if os.getenv("SFXWATCH") == "1" then
  -- ⚠ Cap the list. $78 is a busy slot -- every whiff, hit, jump and land goes
  -- through it -- and an uncapped table over a 500-frame run makes the probe
  -- slower than its own timeout (measured: it never finished at 400 s).
  for _, a in ipairs({ 0x7E0078, 0x000078 }) do
    emu.addMemoryCallback(function(_, v)
      -- only while the contest is actually running: $78 carries every whiff,
      -- hit, jump and land in the approach too, and recording all of it is
      -- both noise and slow enough to eat the run's time budget.
      if (v or 0) ~= 0 and sfxlive and #sfx < 120 then sfx[#sfx + 1] = { t = t, id = v } end
    end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
  end
end

local reported = false               -- the verdict block must run exactly once
sfxlive = false                      -- SFXWATCH records only during the contest

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_exp_clash: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    -- SMS_HPSET=n: force both fighters' current AND max HP to n right after the
    -- state loads. The fixture was captured on the clean ROM, so the character
    -- loader (where the ACS health formula runs) never executes here and HP is
    -- always the vanilla 96 -- which means this probe can say nothing about a
    -- max-HP change unless the value is poked in. Used to find the ceiling the
    -- KO test imposes: death in this engine is UNDERFLOW, tested as
    -- `cmp #$90 / bcs` at 11 sites, so any HP that survives must stay under
    -- $90 = 143 after the subtract.
    if HPSET then
      for _, base in ipairs({ P1, P2 }) do
        PL.wr(base + 0x49, HPSET); PL.wr(base + 0x4A, HPSET)
      end
    end
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  local k, b1, b2 = t - phaseStart, {}, {}
  if phase == "approach" then
    b1[x16(P1) < x16(P2) and "right" or "left"] = true
  elseif phase == "press" then
    if MODE == "mashair" then
      -- both neutral-jump, then both press HP in the air
      if k < 3 then b1.up = true; b2.up = true
      elseif k >= AIRPRESS and k < AIRPRESS + 4 then b1.x = true; b2.x = true end
    elseif MODE == "mashjump" then
      -- P1 stands and swings, P2 jumps IN and swings: ONE airborne participant
      -- is all the ruling needs, and it is far easier to stage than two
      if k < 3 then
        b2.up = true
        b2[x16(P2) < x16(P1) and "right" or "left"] = true
      end
      if k >= P1PRESS and k < P1PRESS + 4 then b1.x = true end
      if k >= AIRPRESS and k < AIRPRESS + 4 then b2.x = true end
    else
      if k >= 0 and k < 4 then b1.x = true end
      local k2 = k - (MODE == "stagger" and STAG or P2OFF)
      if k2 >= 0 and k2 < 4 then b2.x = true end
      -- MASH: P1 alternates two attack buttons on a 3-frame cadence from the
      -- moment the contest starts; P2 never touches a button, so the counts
      -- must separate. (mashtie: nobody mashes.)
      if MODE == "mash" and strug1 and k >= 6 then
        local m = (t - strug1) % 6
        if m == 0 then b1.x = true elseif m == 3 then b1.y = true end
      end
      -- mashhold: P1 HOLDS the button for the whole contest. A held button is
      -- one press, and the count must say so — otherwise the contest rewards
      -- leaning on a button, which is not a mash contest.
      if MODE == "mashhold" and strug1 and k >= 6 then b1.x = true end
    end
  end
  emu.setInput(PL.pad(b1), 0, 0)
  emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)

local function snap()
  return string.format("t=%4d P1 act=%02X 40=%02X 41=%02X 7C=%02X 7B=%02X hp=%3d | "
      .. "P2 act=%02X 40=%02X 41=%02X 7C=%02X 7B=%02X hp=%3d | gap=%d",
      t, r(P1, 0x01), r(P1, 0x40), r(P1, 0x41), r(P1, 0x7C), r(P1, 0x7B), r(P1, 0x49),
      r(P2, 0x01), r(P2, 0x40), r(P2, 0x41), r(P2, 0x7C), r(P2, 0x7B), r(P2, 0x49),
      math.abs(x16(P1) - x16(P2)))
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  if phase == "settle" then
    if k > 70 then phase, phaseStart = "approach", t end
  elseif phase == "approach" then
    if math.abs(x16(P1) - x16(P2)) <= DIST then
      hp1, hp2 = r(P1, 0x49), r(P2, 0x49)
      log(string.format("t=%4d engage at gap %d (hp %d / %d)", t, math.abs(x16(P1) - x16(P2)), hp1, hp2))
      phase, phaseStart = "press", t
    elseif k > 150 then log("SETUP-FAIL approach"); LOG:close(); emu.stop(1) end
  elseif phase == "press" then
    rows[#rows + 1] = snap()
    local a1, a2 = r(P1, 0x01), r(P2, 0x01)
    if (a1 == 0x26 or a1 == 0x2B) and not clash1 then clash1 = t end
    if (a2 == 0x26 or a2 == 0x2B) and not clash2 then clash2 = t end
    if r(P1, 0x49) < hp1 and not dmg1 then dmg1 = t end
    if r(P2, 0x49) < hp2 and not dmg2 then dmg2 = t end
    if not seen1[a1] then seen1[a1] = t end
    if not seen2[a2] then seen2[a2] = t end
    if a1 == 0x31 and not strug1 then strug1 = t end
    if a2 == 0x31 and not strug2 then strug2 = t end
    sfxlive = (a1 == 0x31 or a2 == 0x31)
    -- the contest must carry NO boxes on either fighter, and the handler runs
    -- after the box writer, so a nonzero here is the frame-order claim failing
    if a1 == 0x31 and (r(P1, 0x40) ~= 0 or r(P1, 0x41) ~= 0) then boxdirt = boxdirt + 1 end
    if a2 == 0x31 and (r(P2, 0x40) ~= 0 or r(P2, 0x41) ~= 0) then boxdirt = boxdirt + 1 end
    if a1 == 0x31 then
      anim[#anim + 1] = string.format("t=%4d anim act=%02X pose=%02X tick=%02X frame=%02X step=%02X",
        t, r(P1, 0x04), r(P1, 0x05), r(P1, 0x06), r(P1, 0x07), r(P1, 0x02))
    end
    -- the counts as they stood on the last struggle frame
    if a1 == 0x31 or a2 == 0x31 then
      endc1, endc2 = r(P1, 0x7C) & 0x7F, r(P2, 0x7C) & 0x7F
    end
    -- ⚠ The observation window must OUTLAST the contest, or the probe stops
    -- mid-struggle and reports NO CONTEST / WRONG on a build that is fine.
    -- The contest ran 90 frames until 2026-09-05 and now runs 180 by default,
    -- so a fixed 200 was one maintainer ruling away from lying. SMS_CFRAMES
    -- tracks the generator's --clash-frames; the window is that plus the
    -- approach and resolution slack.
    -- ⚠ ONCE. emu.stop() does not necessarily halt before the next endFrame
    -- callback, and this block logs the whole `rows` table every time it runs.
    -- Re-entering it is quadratic: a 2026-09-05 run with a long Mesen timeout
    -- wrote a 20 GB trace before the wall clock killed it. The flag is the fix;
    -- the frame budget is not, because the budget is the thing that used to hide
    -- this.
    if reported then return end
    if k > (MASH and (CFRAMES + 80) or 70) then
      reported = true
      log("")
      for _, s in ipairs(rows) do log("   " .. s) end
      if #sfx > 0 then
        log("")
        log("   -- writes to the global sound slot $78 --")
        local prev, gaps = nil, {}
        for _, e in ipairs(sfx) do
          log(string.format("   t=%4d  $78 <= %02X%s", e.t, e.id,
              prev and string.format("   (+%d)", e.t - prev) or ""))
          if prev then gaps[#gaps + 1] = e.t - prev end
          prev = e.t
        end
        local uniq = {}
        for _, g in ipairs(gaps) do uniq[g] = (uniq[g] or 0) + 1 end
        local parts = {}
        for g, n in pairs(uniq) do parts[#parts + 1] = string.format("%df x%d", g, n) end
        table.sort(parts)
        log("   intervals: " .. table.concat(parts, ", ") .. "   (writes: " .. #sfx .. ")")
      end
      if #anim > 0 then
        log("")
        log("   -- P1's struggle animation (the jab must LOOP, not hold) --")
        for _, s in ipairs(anim) do log("   " .. s) end
      end
      log("")
      log(string.format("== CLASH %s%s (gap %d) ==", MODE, TAG and (" " .. TAG) or "", DIST))
      log(string.format("   P1 pushed back: %s   P2 pushed back: %s",
          clash1 and ("t=" .. clash1) or "no", clash2 and ("t=" .. clash2) or "no"))
      log(string.format("   damage: P1 %d->%d %s   P2 %d->%d %s",
          hp1, r(P1, 0x49), dmg1 and "(HIT)" or "(none)",
          hp2, r(P2, 0x49), dmg2 and "(HIT)" or "(none)"))
      local function acts(seen)
        local ks = {}
        for a in pairs(seen) do ks[#ks + 1] = a end
        table.sort(ks, function(x, y) return seen[x] < seen[y] end)
        local out = {}
        for _, a in ipairs(ks) do out[#out + 1] = string.format("%02X@%d", a, seen[a]) end
        return table.concat(out, " ")
      end
      log("   P1 acts: " .. acts(seen1))
      log("   P2 acts: " .. acts(seen2))
      local verdict
      if MASH then
        log(string.format("   struggle: P1 %s  P2 %s   counts P1=%s P2=%s   boxes-during-struggle=%d",
            strug1 and ("t=" .. strug1) or "no", strug2 and ("t=" .. strug2) or "no",
            endc1 or "-", endc2 or "-", boxdirt))
        if MODE == "mashgate" then
          log(string.format("   gate pokes (P2 made airborne at the clash test): %d", gatepokes))
        end
        if MODE == "mashair" or MODE == "mashjump" or MODE == "mashgate" then
          verdict = (clash1 and clash2 and not strug1 and not strug2)
              and "AIRBORNE PARTICIPANT -> BACKDASH (the ruling holds)"
              or (strug1 or strug2) and "WRONG: an airborne clash entered the contest"
              or "NO CLASH STAGED (says nothing on its own)"
        elseif not (strug1 and strug2) then
          verdict = "NO CONTEST (the clash never opened one)"
        elseif boxdirt > 0 then
          verdict = "CONTEST but BOXES LIVE (" .. boxdirt .. " frames)"
        elseif MODE == "mashhold" then
          verdict = ((endc1 or 0) <= 2)
              and ("HOLDING IS NOT MASHING: P1 held X all contest, count = " .. (endc1 or 0))
              or ("WRONG: a held button counted " .. (endc1 or 0) .. " times")
        elseif MODE == "mashtie" then
          verdict = (seen1[0x26] and seen2[0x26]) and "TIE -> both backdash"
              or "WRONG: a tie did not backdash both"
        else
          local win1 = seen1[0x00] and not seen1[0x2F]
          local lose2 = seen2[0x2F] and seen2[0x16]
          verdict = (win1 and lose2 and (endc1 or 0) > (endc2 or 0))
              and "MASH CONTEST: P1 won, P2 wall-flew and landed in air hitstun"
              or "WRONG: " .. (win1 and "" or "P1 did not return to neutral; ")
                 .. (lose2 and "" or "P2 did not wall-fly into 0x16")
        end
      else
        verdict = (clash1 and clash2 and not dmg1 and not dmg2) and "CLASH"
          or (dmg1 and dmg2) and "TRADE (both damaged)"
          or (dmg1 or dmg2) and "ONE-SIDED HIT" or "NOTHING HAPPENED"
      end
      log("   VERDICT: " .. verdict)
      LOG:close(); emu.stop(0)
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_clash loaded: " .. MODE)
