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
local ROOT = "/Users/koneko/Developer/SailorMoonS/tools/"
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
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
        return m.S == 8 and m.A == 12 and m.act == 0x55,
               string.format("t140 2HP act=%02X S%d A%d R%d (want 55 8/12/-)", m.act, m.S, m.A, m.R) end },
    { t = 155, fn = function(ctx)
        local a = ctx.lastAdv
        if not a then return false, "t155 no lastAdv (2HP)" end
        return a.kind == "hit", string.format("t155 2HP adv=%+d c%+d kind=%s", a.adv, a.cAdv, a.kind) end },
  },
}

-- ---------- harness ----------
local T = tests[TEST]
if not T then error("unknown TEST " .. tostring(TEST)) end
local log = io.open(TRACE .. "training_test_" .. TEST .. ".txt", "w")
local fails, ran = 0, 0

local applied = { nil, nil }
local cur = { {}, {} }
local function planPad(plan, which, t)
  if not plan then return FALSE end
  for k, v in pairs(plan) do
    if k <= t and k > (applied[which] or -1) then cur[which] = v; applied[which] = k end
  end
  local out = {}
  for kk, vv in pairs(FALSE) do out[kk] = vv end
  for kk, vv in pairs(cur[which]) do out[kk] = vv end
  return out
end

local ctxRef = nil
local main = dofile(ROOT .. "training/main.lua")
ctxRef = main.run(ROOT, {
  headless = true,
  padSource = function(port)
    local t = ctxRef and ctxRef.t or -1
    if t < 0 then return FALSE end
    return planPad(port == 0 and T.PLAN1 or T.PLAN2, port + 1, t)
  end,
})

ctxRef.onFirstExec = function(ctx)
  local f = io.open(TRACE .. T.STATE, "rb")
  if not f then log:write("FAIL: no state " .. T.STATE .. "\n"); log:close(); emu.stop(1); return end
  ctx.anchor.loadreq = f:read("*a"); f:close()
end

-- checks run as a frame hook AFTER all module hooks (appended last)
table.insert(ctxRef.hooks.frame, function(ctx)
  if T.POKES then
    for _, p in ipairs(T.POKES) do
      if p.t == ctx.t then emu.write(p.addr, p.val, ctx.C.WRAM) end
    end
  end
  for _, chk in ipairs(T.CHECKS) do
    if chk.t == ctx.t then
      ran = ran + 1
      local ok, msg = chk.fn(ctx)
      log:write((ok and "PASS: " or "FAIL: ") .. (msg or "") .. "\n")
      log:flush()
      if not ok then fails = fails + 1 end
    end
  end
  if ctx.t == T.DONE then
    log:write(string.format("%s: %d checks, %d failed\n", TEST, ran, fails))
    log:close()
    emu.stop(fails == 0 and 0 or 1)
  end
end)

print("training_test loaded: " .. TEST)
