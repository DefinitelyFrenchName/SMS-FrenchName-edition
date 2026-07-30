-- training_test.lua — headless test harness for the training-mode modules.
--
-- USE:  TMTEST=<id> is read from tools/training_test_cfg.lua (TEST="T1" etc.), then:
--       ROM="<rom>" tools/run.sh tools/training_test.lua 120
-- Writes verdict lines to traces/training_test_<id>.txt and exits 0 (all PASS) / 1.
--
-- A test provides: STATE (savestate), PLAN1/PLAN2 (latched {[t]=padTable} like trace.lua),
-- POKES ({{t,addr,val}}), CHECKS (list of {t=frame, fn=function(ctx) return ok, msg end}),
-- DONE (end frame). The harness feeds plans through ctx.padSource so the full input
-- pipeline (swap/recorder/dummy) is exercised exactly as in the GUI.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local ROOT = ENV.TOOLS
local TRACE = ENV.TRACE
pcall(dofile, ROOT .. "training_test_cfg.lua")
TEST = TEST or "T1"

local C0 = dofile(ROOT .. "training/const.lua")
local FALSE = C0.FALSE_PAD

-- ---------- test definitions ----------
local tests = {}

-- T1: Venus 5LP point-blank oracle (measured by tools/probe_api.lua, 2026-07-16):
-- press t=60 → act 0x40 step0 same frame; first hitbox t=64 (hit, P2 hp 0x60→0x5E);
-- hitstop 8f t=65-72; recovery act 0x41 from t=76 with box persisting into its step-0
-- frame; P1 neutral t=81; P2 hitstun act 0x12 until t=86 → advantage +6.
tests.T1 = {
  STATE = "venus_vs_jupiter_clean.mss",
  POKES = { { t = 5, addr = 0x1021, val = 0xE8 } },
  PLAN1 = { [60] = { y = true }, [63] = {} },
  DONE = 110,
  CHECKS = {
    { t = 60, fn = function(ctx)
        local p = ctx.snap.p[1]
        return p.act == 0x40 and p.cls == ctx.C.CLS.STARTUP,
               string.format("t60 act=%02X cls=%s", p.act, ctx.C.CLS_NAME[p.cls]) end },
    { t = 64, fn = function(ctx)
        local p, q = ctx.snap.p[1], ctx.snap.p[2]
        return p.cls == ctx.C.CLS.ACTIVE and q.hp == 0x5E,
               string.format("t64 cls=%s p2hp=%02X", ctx.C.CLS_NAME[p.cls], q.hp) end },
    { t = 65, fn = function(ctx)
        local p, q = ctx.snap.p[1], ctx.snap.p[2]
        return p.frz and q.cls == ctx.C.CLS.HITSTUN,
               string.format("t65 frz=%s p2cls=%s", tostring(p.frz), ctx.C.CLS_NAME[q.cls]) end },
    { t = 76, fn = function(ctx)
        local p = ctx.snap.p[1]
        return p.act == 0x41 and p.cls == ctx.C.CLS.ACTIVE,
               string.format("t76 act=%02X cls=%s (persist frame)", p.act, ctx.C.CLS_NAME[p.cls]) end },
    { t = 77, fn = function(ctx)
        local p = ctx.snap.p[1]
        return p.cls == ctx.C.CLS.RECOVERY_C,
               string.format("t77 cls=%s", ctx.C.CLS_NAME[p.cls]) end },
    { t = 82, fn = function(ctx)
        local m = ctx.lastMove[1]
        if not m then return false, "t82 no lastMove" end
        return m.S == 4 and m.A == 5 and m.R == 4,
               string.format("t82 S%d A%d R%d (want 4/5/4)", m.S, m.A, m.R) end },
    { t = 100, fn = function(ctx)
        local a = ctx.lastAdv
        if not a then return false, "t100 no lastAdv" end
        return a.adv == 6 and a.kind == "hit" and a.atk == 1,
               string.format("t100 adv=%+d kind=%s atk=%d (want +6 hit 1)", a.adv, a.kind, a.atk) end },
  },
}

-- T2: Uranus 2LP on hit (clean-ROM state; oracle: docs/annotations.md + Dustloop).
-- S/A/R are press-parity independent; expect S4 A5 R4, adv +6, defender hitstun.
tests.T2 = {
  STATE = "uranus_vs_jupiter_tm.mss",
  POKES = { { t = 5, addr = 0x1021, val = 0xE8 } },
  PLAN1 = { [10] = { down = true }, [60] = { down = true, y = true }, [63] = { down = true } },
  DONE = 130,
  CHECKS = {
    { t = 110, fn = function(ctx)
        local m = ctx.lastMove[1]
        if not m then return false, "t110 no lastMove" end
        return m.S == 4 and m.A == 5 and m.R == 4 and m.act == 0x53,
               string.format("t110 2LP act=%02X S%d A%d R%d (want 53 4/5/4)", m.act, m.S, m.A, m.R) end },
    { t = 125, fn = function(ctx)
        local a = ctx.lastAdv
        if not a then return false, "t125 no lastAdv" end
        return a.adv == 6 and a.kind == "hit",
               string.format("t125 adv=%+d kind=%s (want +6 hit)", a.adv, a.kind) end },
  },
}

-- T2H: Uranus 2HP on hit. Oracle: S8 A12 (Dustloop / annotations); R and adv logged.
-- Recovery act 0x56 is NOT in the cancellable set (the 2HP>66 cancel is a separate
-- mechanism), so it must classify RECOVERY, not RECOVERY_C.
tests.T2H = {
  STATE = "uranus_vs_jupiter_tm.mss",
  POKES = { { t = 5, addr = 0x1021, val = 0xE8 } },
  PLAN1 = { [10] = { down = true }, [60] = { down = true, x = true }, [63] = { down = true } },
  DONE = 160,
  CHECKS = {
    { t = 140, fn = function(ctx)
        local m = ctx.lastMove[1]
        if not m then return false, "t140 no lastMove" end
        -- R==7 is the HANDOFF oracle (2HP S8 A12 R7); asserted since issue #28
        return m.S == 8 and m.A == 12 and m.R == 7 and m.act == 0x55,
               string.format("t140 2HP act=%02X S%d A%d R%d (want 55 8/12/7)", m.act, m.S, m.A, m.R) end },
    { t = 155, fn = function(ctx)
        local a = ctx.lastAdv
        if not a then return false, "t155 no lastAdv (2HP)" end
        return a.kind == "hit", string.format("t155 2HP adv=%+d c%+d kind=%s", a.adv, a.cAdv, a.kind) end },
  },
}

-- T3: recorder round-trip. Phase A: drive the dummy (P2) directly with a scripted 2LK and
-- record its act sequence as baseline. Phase B: reload, feed the SAME script through the
-- user pad with pad-swap + recording armed. Phase C: reload, play the slot back and assert
-- the dummy's act sequence is IDENTICAL to baseline. Also unit-checks direction mirroring.
tests.T3 = (function()
  local plan = { [60] = { down = true, b = true }, [64] = {}, [70] = { b = true }, [72] = {} }
  local phase = "A"
  local baseline, replay = {}, {}
  -- stateless latched lookup (a stateful cursor would be corrupted by the one stray frame
  -- that runs between requesting a savestate reload and the reload actually happening)
  local function planPad(t)
    local bestK, best = -1, {}
    for k, v in pairs(plan) do
      if k <= t and k > bestK then bestK, best = k, v end
    end
    local out = {}
    for kk, vv in pairs(C0.FALSE_PAD) do out[kk] = vv end
    for kk, vv in pairs(best) do out[kk] = vv end
    return out
  end
  local T
  T = {
    STATE = "venus_vs_jupiter_clean.mss",
    DONE = 1e9,   -- custom end
    CHECKS = {},
    padSource = function(ctx, port)
      local t = ctx.t
      if t < 0 then return C0.FALSE_PAD end
      if phase == "A" and port == 1 then return planPad(t) end
      if phase == "B" and port == 0 then return planPad(t) end
      return C0.FALSE_PAD
    end,
    ONFRAME = function(ctx, log, finish)
      local rec = ctx.mod.recorder
      local t = ctx.t
      if phase == "A" then
        if t >= 55 and t <= 100 then baseline[#baseline + 1] = ctx.snap.p[2].act end
        if t == 101 then
          -- unit: direction normalization round-trip
          local inp = ctx.mod.input
          local m = inp.maskOf({ left = true, y = true }, false)  -- P on right side: left = fwd
          local ok1 = m == (ctx.C.M_FWD + ctx.C.M_LP)
          local pad = inp.padOf(ctx.C.M_FWD, true)                -- on left side: fwd = right
          local ok2 = pad.right and not pad.left
          log((ok1 and ok2) and "PASS: direction mirror round-trip"
              or string.format("FAIL: mirror m=%X right=%s", m, tostring(pad.right)))
          phase = "B"; applied = nil; cur = {}
          ctx.anchor.loadreq = T._state
        end
      elseif phase == "B" then
        if t == 5 then ctx.actions.record(ctx) end       -- arm + pad-swap
        if t == 101 then
          ctx.actions.record(ctx)                        -- end recording
          local n = #rec.slots[rec.cur]
          log(n > 10 and ("PASS: recorded " .. n .. " frames")
              or ("FAIL: recorded only " .. n .. " frames"))
          phase = "C"; applied = nil; cur = {}
          ctx.anchor.loadreq = T._state
        end
      elseif phase == "C" then
        if t == 59 then ctx.actions.play(ctx) end        -- playback begins at t=60's poll
        if t >= 55 and t <= 100 then replay[#replay + 1] = ctx.snap.p[2].act end
        if t == 101 then
          local same, diffAt = true, nil
          for k = 1, #baseline do
            if baseline[k] ~= replay[k] then same = false; diffAt = k; break end
          end
          log(same and "PASS: playback act sequence identical to baseline"
              or string.format("FAIL: diverges at idx %d (base %02X vs %02X)",
                  diffAt, baseline[diffAt] or 255, replay[diffAt] or 255))
          finish()
        end
      end
    end,
  }
  return T
end)()

-- T4: dummy guard + combo counter vs the v0.7 infinite rep (RUN ON THE v0.7-family ROM,
-- e.g. build/SailorMoonS_FrenchName_v0.7_all5_venustech.sfc — patch 8 doesn't touch this).
-- Sequence = demo_link's rep: 2LP > 2HP > 66 > follow-up 2LP at FV. Dummy: crouch, then
-- guard-all from t=100 (down-back). Oracle (HANDOFF reversal matrix / demo_link):
--   FV=115 frame-perfect: the meaty HITS through same-frame block; combo restarts at 1.
--   FV=116 one late:      the dummy BLOCKS (blockstun 0x0E/0F, no damage).
tests.T4 = (function()
  local phase = "meaty"          -- then "late"
  local FV = 115
  local hpAt110, sawHit, sawBlock = nil, false, false
  local function plan(t)
    local kf = { {10,{down=true}}, {60,{down=true,y=true}}, {62,{down=true}},
                 {77,{down=true,x=true}}, {80,{down=true}},
                 {95,{}}, {97,{right=true}}, {98,{}}, {99,{right=true}}, {101,{}},
                 {FV,{down=true,y=true}}, {FV+2,{down=true}} }
    local best = {}
    for _, e in ipairs(kf) do if e[1] <= t then best = e[2] end end
    local out = {}
    for kk, vv in pairs(C0.FALSE_PAD) do out[kk] = vv end
    for kk, vv in pairs(best) do out[kk] = vv end
    return out
  end
  local T
  T = {
    STATE = "uranus_vs_jupiter_v07.mss",
    DONE = 1e9,
    CHECKS = {},
    POKES = { { t = 5, addr = 0x1021, val = 0xE8 } },
    padSource = function(ctx, port)
      if port == 0 and ctx.t >= 0 then return plan(ctx.t) end
      return C0.FALSE_PAD
    end,
    ONFRAME = function(ctx, log, finish)
      local t = ctx.t
      local dm = ctx.mod.dummy
      if t == 2 then dm.pose = "crouch"; dm.guard = "off"; dm.wakeup = "off" end
      if t == 100 then dm.guard = "all" end
      if t == 95 and phase == "meaty" then
        local c = ctx.combo[2]
        log((c.hits == 2 and not c.reset)
            and "PASS: 2LP>2HP combo = 2 hits TRUE"
            or string.format("FAIL: combo hits=%s reset=%s",
                tostring(c.hits), tostring(c.reset)))
        log((c.tight == false)
            and "PASS: 2LP>2HP chain not tight (all hits in stun)"
            or "FAIL: 2LP>2HP wrongly flagged tight")
      end
      if t == 110 then hpAt110 = ctx.snap.p[2].hp; sawHit = false; sawBlock = false end
      if t > 110 and t <= 135 then
        if ctx.snap.p[2].hp < (hpAt110 or 0) then sawHit = true end
        if C0.isBlockstunAct(ctx.snap.p[2].act) then sawBlock = true end
      end
      if t == 136 then
        if phase == "meaty" then
          log(sawHit and "PASS: FV=115 meaty hits through same-frame block"
              or "FAIL: FV=115 meaty did not hit")
          -- the frame-perfect N=6 meaty gives the defender ZERO actionable frames (it lands
          -- on their first out-of-hitstun frame and hit beats same-frame block — reversal
          -- matrix: nothing escapes), so the combo counter correctly CONTINUES: 3 hits.
          local c = ctx.combo[2]
          log((c.hits == 3 and not c.reset)
              and "PASS: seamless meaty continues combo (3 hits, no reset)"
              or string.format("FAIL: combo hits=%s reset=%s after meaty",
                  tostring(c.hits), tostring(c.reset)))
          log((c.tight == true and c.tightHits == 1)
              and "PASS: meaty flagged the chain tight (1 non-bufferable link)"
              or string.format("FAIL: tight=%s tightHits=%s after meaty",
                  tostring(c.tight), tostring(c.tightHits)))
          -- (MEATY label removed 2026-07-20 — verify no stale label fires on the meaty)
          local sawMeaty = false
          for _, fentry in ipairs(ctx.mod.labels.fired) do
            if fentry.text:find("MEATY") then sawMeaty = true end
          end
          log((not sawMeaty) and "PASS: no MEATY label (removed) on the 1-frame meaty"
              or "FAIL: MEATY label fired but was removed")
          phase = "late"; FV = 116
          ctx.anchor.loadreq = T._state
        else
          log((sawBlock and not sawHit) and "PASS: FV=116 is blocked (guard-all works)"
              or string.format("FAIL: late meaty sawHit=%s sawBlock=%s",
                  tostring(sawHit), tostring(sawBlock)))
          finish()
        end
      end
    end,
  }
  return T
end)()

-- T5: event labels on deterministic scenarios (clean ROM, Venus vs Jupiter):
--   A: Venus 6HP throw + P2 mash        -> "P2 THROW TECH"
--   B: same, no mash                    -> "P2 THROWN"
--   D: Venus sweep + dummy wakeup jab   -> "P2 REVERSAL"
--   (COUNTER was removed — no counter-hit bonus in this game; GC has its own test T8)
tests.T5 = (function()
  local phase = "A"
  local function fired(ctx, want)
    for _, f in ipairs(ctx.mod.labels.fired) do
      if f.text == want then return true end
    end
    return false
  end
  local plans = {
    A = { p1 = { [60] = { right = true, x = true }, [63] = {} }, mash = true },
    B = { p1 = { [60] = { right = true, x = true }, [63] = {} } },
    D = { p1 = { [60] = { down = true, a = true }, [63] = {} } },
  }
  local function pad(plan, t)
    if not plan then return C0.FALSE_PAD end
    local bestK, best = -1, {}
    for k, v in pairs(plan) do
      if k <= t and k > bestK then bestK, best = k, v end
    end
    local out = {}
    for kk, vv in pairs(C0.FALSE_PAD) do out[kk] = vv end
    for kk, vv in pairs(best) do out[kk] = vv end
    return out
  end
  local T
  T = {
    STATE = "venus_vs_jupiter_clean.mss",
    DONE = 1e9,
    CHECKS = {},
    POKES = { { t = 5, addr = 0x1021, val = 0xE8 } },
    padSource = function(ctx, port)
      local t = ctx.t
      if t < 0 then return C0.FALSE_PAD end
      local pl = plans[phase]
      if port == 0 then return pad(pl.p1, t) end
      if pl.mash then
        -- HK press every other frame from t=61 (throw-tech mash)
        local out = {}
        for kk, vv in pairs(C0.FALSE_PAD) do out[kk] = vv end
        if t >= 61 and t <= 85 and t % 2 == 1 then out.a = true end
        return out
      end
      return pad(pl.p2, t)
    end,
    ONFRAME = function(ctx, log, finish)
      local t = ctx.t
      local dm = ctx.mod.dummy
      if t == 2 then
        dm.enabled = (phase == "D")
        dm.guard = "off"; dm.pose = "stand"; dm.tech = false
        dm.wakeup = (phase == "D") and "jab" or "off"
      end
      if phase == "D" and t >= 150 and t <= 226 and t % 8 == 0 then
        log(string.format("DBG t=%d p2act=%02X cls=%s out2=%s", t, ctx.snap.p[2].act,
          ctx.C.CLS_NAME[ctx.snap.p[2].cls or 13], tostring(ctx.out and ctx.out[2] ~= nil)))
      end
      if phase == "A" and t == 120 then
        local st = ctx.mod.labels.side[2]
        log((st and st.text == "THROW TECH")
            and "PASS: side status slot holds THROW TECH (under-counter display)"
            or string.format("FAIL: side[2]=%s", st and st.text or "nil"))
      end
      if t == ((phase == "D") and 230 or 150) then
        local want = ({ A = "P2 THROW TECH", B = "P2 THROWN",
                        D = "P2 REVERSAL" })[phase]
        log(fired(ctx, want) and ("PASS: " .. phase .. " fired " .. want)
            or ("FAIL: " .. phase .. " missing " .. want .. " (got: " ..
                (function()
                  local out = {}
                  for _, f in ipairs(ctx.mod.labels.fired) do out[#out + 1] = f.text end
                  return table.concat(out, ", ")
                end)() .. ")"))
        ctx.mod.labels.fired = {}
        if phase == "A" then phase = "B"
        elseif phase == "B" then phase = "D"
        else finish(); return end
        ctx.anchor.loadreq = T._state
      end
    end,
  }
  return T
end)()

-- T6: regen module — P1 5LP hits P2 at t=64 (hp 0x60->0x5E); HP must stay down through
-- the 2s window, restore to max (+0x4A) after, and the frozen round timer must not tick.
tests.T6 = {
  STATE = "venus_vs_jupiter_clean.mss",
  POKES = { { t = 5, addr = 0x1021, val = 0xE8 } },
  PLAN1 = { [60] = { y = true }, [63] = {} },
  DONE = 230,
  CHECKS = {
    { t = 20, fn = function(ctx)
        ctx._timer0 = emu.read(0x0802, ctx.C.WRAM)
        return true, string.format("timer captured %02X", ctx._timer0) end },
    { t = 100, fn = function(ctx)
        local hp = ctx.snap.p[2].hp
        return hp == 0x5E, string.format("t100 hp=%02X (want 5E, still damaged)", hp) end },
    { t = 200, fn = function(ctx)
        local p = ctx.snap.p[2]
        return p.hp == p.maxhp,
               string.format("t200 hp=%02X max=%02X (want restored)", p.hp, p.maxhp) end },
    { t = 201, fn = function(ctx)
        local bar = emu.read(0x0801, ctx.C.WRAM)
        return bar == ctx.snap.p[2].maxhp,
               string.format("t201 hpbar=%02X (want %02X, bar visually refilled)",
                 bar, ctx.snap.p[2].maxhp) end },
    { t = 220, fn = function(ctx)
        local tv = emu.read(0x0802, ctx.C.WRAM)
        return tv == ctx._timer0,
               string.format("t220 timer=%02X (want frozen at %02X)", tv, ctx._timer0) end },
  },
}

-- T7: KO auto-reset — poke P2 to 2 HP, kill with a jab; regen must reload the baseline
-- position state (auto-captured at t=30) before the round-end flow, restoring full HP.
tests.T7 = (function()
  local koSeen, done = false, false
  return {
    STATE = "venus_vs_jupiter_clean.mss",
    DONE = 1e9,
    CHECKS = {},
    POKES = { { t = 5, addr = 0x1021, val = 0xE8 },
              { t = 50, addr = 0x10C9, val = 1 }, { t = 50, addr = 0x0801, val = 1 } },
    PLAN1 = { [60] = { y = true }, [63] = {} },
    ONFRAME = function(ctx, log, finish)
      if done then return end
      if ctx.t == 35 then
        log(ctx.anchor.posState and "PASS: baseline position state auto-captured"
            or "FAIL: no baseline state at t=35")
      end
      if ctx.snap.p[2].hp == 0 and ctx.C.isKDAct(ctx.snap.p[2].act) then koSeen = true end
      if koSeen and ctx.t <= 10 then
        local hp = ctx.snap.p[2].hp
        log(hp == 0x60 and "PASS: KO triggered reload of baseline (P2 back at full)"
            or string.format("FAIL: after KO reload hp=%02X", hp))
        done = true
        finish()
      end
      if ctx.frame > 900 then
        log(koSeen and "FAIL: KO seen but no reload happened"
            or "FAIL: KO never happened (setup broken)")
        done = true
        finish()
      end
    end,
  }
end)()

-- T8: GUARD CANCEL label (RUN ON A v0.7-FAMILY ROM — uses the v07 Mars state). P2 Mars
-- blocks Uranus 2HP, then rolls HCF+LK during blockstun: the fireball act starts DIRECTLY
-- from blockstun (measured act 0x0E -> 0x68) => "P2 GC" fires (and not REVERSAL).
tests.T8 = {
  STATE = "uranus_vs_mars_v07.mss",
  POKES = { { t = 5, addr = 0x1021, val = 0xE8 } },
  PLAN1 = { [10] = { down = true }, [60] = { down = true, x = true }, [63] = { down = true } },
  PLAN2 = { [10] = { right = true, down = true },
            [74] = { right = true }, [76] = { right = true, down = true },
            [78] = { down = true }, [80] = { down = true, left = true },
            [82] = { left = true, b = true }, [85] = { left = true }, [87] = {} },
  DONE = 140,
  CHECKS = {
    { t = 2, fn = function(ctx) ctx.mod.dummy.enabled = false; return true, "dummy off" end },
    { t = 130, fn = function(ctx)
        local gc, rev = false, false
        for _, f in ipairs(ctx.mod.labels.fired) do
          if f.text == "P2 GC" then gc = true end
          if f.text == "P2 REVERSAL" then rev = true end
        end
        return gc and not rev,
               string.format("t130 GC=%s REVERSAL=%s (want GC only)", tostring(gc), tostring(rev)) end },
  },
}

-- T9: GC TRAINER end-to-end (v0.7-family ROM). Dummy Mars guards all; slot 1 holds the
-- fireball motion (facing-relative masks); trigger=gc, 100%. P1's blocked 2HP must be
-- guard-canceled AUTONOMOUSLY: playback fires on blockstun entry, fireball act comes out
-- of blockstun, "P2 GC" label fires.
tests.T9 = {
  STATE = "uranus_vs_mars_v07.mss",
  POKES = { { t = 5, addr = 0x1021, val = 0xE8 } },
  PLAN1 = { [10] = { down = true }, [60] = { down = true, x = true }, [63] = { down = true } },
  DONE = 150,
  CHECKS = {
    { t = 2, fn = function(ctx)
        local dm, rec = ctx.mod.dummy, ctx.mod.recorder
        dm.enabled = true; dm.guard = "all"; dm.pose = "stand"; dm.wakeup = "off"; dm.tech = false
        -- Mars fireball HCF+LK as facing-relative masks (back=1 fwd=2 down=4 LK=0x20),
        -- 2 frames per motion step, matching the measured GC trace
        rec.slots[1] = { 1, 1, 5, 5, 4, 4, 6, 6, 0x22, 0x22, 0x22, 2, 2 }
        rec.cur = 1; rec.trigger = "gc"; rec.gcChance = 100
        return true, "gc trainer armed" end },
    { t = 130, fn = function(ctx)
        local gc = false
        for _, f in ipairs(ctx.mod.labels.fired) do
          if f.text == "P2 GC" then gc = true end
        end
        local fireball = false
        for k = 0, 60 do
          local e = ctx.mod.gamestate.ago(k)
          if e and (e.p[2].act == 0x68 or e.p[2].act == 0x69 or e.p[2].act == 0x6A) then
            fireball = true
          end
        end
        return gc and fireball,
               string.format("t130 GC=%s fireball=%s (want both)", tostring(gc), tostring(fireball)) end },
  },
}

-- T10: regen after a PROJECTILE special (field report 2026-07-21: "life refill only after
-- a normal hit"). Neptune 214LP Deep Submerge hits standing Jupiter ~t=46; the attacker's
-- BODY never goes active (hitbox lives on the projectile slot), which used to leave the
-- framedata move instance open (P1 stuck STARTUP) -> combo[2] never closed -> regen gated
-- off forever. Asserts: hit lands, P1 reclassifies NEUTRAL, combo closes, HP refills at
-- ~120f after the hit. Works on clean and patched families (state loads permissively).
tests.T10 = {
  STATE = "neptune_vs_jupiter.mss",
  PLAN1 = { [8] = { down = true }, [11] = { down = true, left = true },
            [14] = { left = true, y = true }, [17] = {} },
  DONE = 185,
  CHECKS = {
    { t = 50, fn = function(ctx)
        local q = ctx.snap.p[2]
        return q.hp < q.maxhp and ctx.combo[2].active,
               string.format("t50 p2hp=%02X/%02X comboActive=%s (want hit + open combo)",
                             q.hp, q.maxhp, tostring(ctx.combo[2].active)) end },
    { t = 120, fn = function(ctx)
        local p = ctx.snap.p[1]
        return p.cls == ctx.C.CLS.NEUTRAL and not ctx.combo[2].active,
               string.format("t120 p1cls=%s comboActive=%s (want NEUTRAL + closed combo)",
                             ctx.C.CLS_NAME[p.cls], tostring(ctx.combo[2].active)) end },
    { t = 175, fn = function(ctx)
        local q = ctx.snap.p[2]
        return q.hp == q.maxhp,
               string.format("t175 p2hp=%02X/%02X (want refilled)", q.hp, q.maxhp) end },
  },
}

-- ---------- harness ----------
local T = tests[TEST]
if not T then error("unknown TEST " .. tostring(TEST)) end
local log = io.open(TRACE .. "training_test_" .. TEST .. ".txt", "w")
local fails, ran = 0, 0

local function planPad(plan, which, t)
  if not plan then return FALSE end
  local bestK, best = -1, {}
  for k, v in pairs(plan) do
    if k <= t and k > bestK then bestK, best = k, v end
  end
  local out = {}
  for kk, vv in pairs(FALSE) do out[kk] = vv end
  for kk, vv in pairs(best) do out[kk] = vv end
  return out
end

local ctxRef = nil
local main = dofile(ROOT .. "training/main.lua")
ctxRef = main.run(ROOT, {
  headless = true,
  padSource = function(port)
    if not ctxRef then return FALSE end
    if T.padSource then return T.padSource(ctxRef, port) end
    local t = ctxRef.t
    if t < 0 then return FALSE end
    return planPad(port == 0 and T.PLAN1 or T.PLAN2, port + 1, t)
  end,
})

ctxRef.onFirstExec = function(ctx)
  local f = io.open(TRACE .. T.STATE, "rb")
  if not f then log:write("FAIL: no state " .. T.STATE .. "\n"); log:close(); emu.stop(1); return end
  T._state = f:read("*a"); f:close()
  ctx.anchor.loadreq = T._state
end

-- Only PASS/FAIL lines count as checks; DBG/trace lines are written uncounted
-- (issue #7: `ran` used to count every line, and a check that never fired was
-- indistinguishable from a passing one).
local function logLine(s)
  local p4 = s:sub(1, 4)
  if p4 == "PASS" or p4 == "FAIL" then
    ran = ran + 1
    if p4 == "FAIL" then fails = fails + 1 end
  end
  log:write(s .. "\n"); log:flush()
end
local function finish()
  -- a scheduled check that never fired is a FAILURE, not a silent pass
  local unfired = {}
  for _, chk in ipairs(T.CHECKS) do
    if not chk._fired then unfired[#unfired + 1] = tostring(chk.t) end
  end
  if #unfired > 0 then
    fails = fails + 1
    log:write(string.format("FAIL: %d scheduled check(s) never fired (t=%s) — DONE too early or frame drift\n",
      #unfired, table.concat(unfired, ",")))
  end
  if T.EXPECT and ran ~= T.EXPECT then
    fails = fails + 1
    log:write(string.format("FAIL: check count %d != EXPECT %d\n", ran, T.EXPECT))
  end
  log:write(string.format("%s: %d checks, %d failed\n", TEST, ran, fails))
  log:close()
  emu.stop(fails == 0 and 0 or 1)
end

-- checks run as a frame hook AFTER all module hooks (appended last)
table.insert(ctxRef.hooks.frame, function(ctx)
  if T.POKES then
    for _, p in ipairs(T.POKES) do
      if p.t == ctx.t then emu.write(p.addr, p.val, ctx.C.WRAM) end
    end
  end
  for _, chk in ipairs(T.CHECKS) do
    if chk.t == ctx.t and not chk._fired then
      chk._fired = true
      local ok, msg = chk.fn(ctx)
      logLine((ok and "PASS: " or "FAIL: ") .. (msg or ""))
    end
  end
  if T.ONFRAME then T.ONFRAME(ctx, logLine, finish) end
  if ctx.t == T.DONE then finish() end
end)

print("training_test loaded: " .. TEST)
