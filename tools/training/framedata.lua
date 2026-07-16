-- framedata.lua — per-frame class tagging, move-instance tracking (startup/active/recovery),
-- connect detection, and frame-advantage settlement. The correctness core.
--
-- Conventions (validated against measured oracles — see tests):
--  * Counts are in NON-FROZEN frames (hitstop +0x4D ~= 0 excluded); frozen frames render
--    dimmed on the meter. This makes whiff and on-hit S/A/R identical.
--  * S(startup) = frames from the move's step-0 frame up to but NOT including the first
--    active frame (this game's Dustloop convention; UI can display SF6-style S+1).
--  * ACTIVE = a real hitbox (index != 0 AND box height > 0) present, step >= 1 for a brand
--    new attack; a box persisting into the recovery act's step-0 frame stays ACTIVE
--    (measured: it can still hit there).
--  * Advantage = defenderNeutralFrame - attackerNeutralFrame (+ = attacker acts first),
--    where "neutral" = act <= 0x04 / 0x0C / 0x0D / 0x21; settled only when neither player
--    has a live projectile. cancelAdv additionally treats cancellable recovery as free.
local M = {}

function M.init(ctx)
  local C = ctx.C
  local CLS = C.CLS
  local HITBOX_H = dofile(ctx.ROOT .. "training/hitbox_h.lua")

  M.on = { moveStart = {}, moveEnd = {}, connect = {}, settled = {} }
  local function emit(name, ev)
    for _, fn in ipairs(M.on[name]) do fn(ev, ctx) end
  end

  local function newMv()
    return { inMove = false }
  end
  local mv = { newMv(), newMv() }
  -- pending attack-start: an act >= 0x2B at step 0 whose +0x18 attack flag (which only
  -- rises at step 1 — measured) hasn't confirmed yet. Classified STARTUP optimistically,
  -- repainted MOVEMENT next frame if unconfirmed (e.g. dashes).
  local pend = { nil, nil }
  local inter = nil            -- open interaction: {atkI, kind, connectT}
  ctx.lastMove = { nil, nil }  -- per player: last completed move summary
  ctx.lastAdv = nil

  local function realActive(p)
    if p.hb == 0 then return false end
    local hh = HITBOX_H[p.char]
    if not hh then return p.hb ~= 0 end
    return (hh[p.hb] or 0) > 0
  end

  local function beginMove(i, s)
    local p = s.p[i]
    local startT, s0 = ctx.t, 0
    -- consume a confirmed pending start: backdate to the step-0 frame and count it
    local pd = pend[i]
    if pd and pd.act == p.act and pd.t == ctx.t - 1 then
      startT = pd.t
      if not pd.frz then s0 = 1 end
    end
    pend[i] = nil
    mv[i] = { inMove = true, startT = startT, act0 = p.act, S = s0, A = 0, R = 0,
              seenActive = false, lastActiveT = nil, phases = {}, curPhase = nil,
              actChain = { [p.act] = true } }
    emit("moveStart", { player = i, t = startT, act = p.act })
  end

  -- repaint a single history frame's class for player i
  local function repaintFrame(i, atT, cls)
    for k = 0, math.min(ctx.hist.n - 1, 4) do
      local e = ctx.mod.gamestate.ago(k)
      if e and e.f == atT then e.p[i].cls = cls; return end
    end
  end

  local function endMove(i, reason)
    local m = mv[i]
    if not m.inMove then return end
    m.inMove = false
    if m.curPhase then m.phases[#m.phases + 1] = m.curPhase; m.curPhase = nil end
    local summary = { player = i, t = ctx.t, act = m.act0, S = m.S, A = m.A, R = m.R,
                      total = m.S + m.A + m.R, phases = m.phases, reason = reason,
                      actChain = m.actChain }
    if m.seenActive or m.S > 0 then
      ctx.lastMove[i] = summary
      emit("moveEnd", summary)
    end
    mv[i] = newMv()
  end

  -- retro-repaint a multi-hit gap (frames between active phases) as STARTUP
  local function repaintGap(i, fromT, toT)
    local h = ctx.hist
    for k = 0, h.n - 1 do
      local e = ctx.mod.gamestate.ago(k)
      if not e then break end
      if e.f < fromT then break end
      if e.f >= fromT and e.f <= toT then
        local pe = e.p[i]
        if pe.cls == CLS.RECOVERY or pe.cls == CLS.RECOVERY_C then pe.cls = CLS.STARTUP end
      end
    end
  end

  local function classify(i, s)
    local p = s.p[i]
    local a = p.act
    local frz = p.stop ~= 0
    local inv = (p.hub == 0) or (p.hurt >= 0x80)
    local canc = C.CANCELLABLE[p.char] and C.CANCELLABLE[p.char][a] or false

    -- hard states terminate any move instance
    if a == 0x23 then endMove(i, "tech"); return CLS.TECH, inv, frz, false end
    if C.isThrowVictimAct(a) then endMove(i, "thrown"); return CLS.THROWN, inv, frz, false end
    if C.isHitstunAct(a) then endMove(i, "hit"); return CLS.HITSTUN, inv, frz, false end
    if C.isBlockstunAct(a) then endMove(i, "blockstun"); return CLS.BLOCKSTUN, inv, frz, false end
    if C.isKDAct(a) then endMove(i, "kd"); return CLS.KNOCKDOWN, inv, frz, false end

    local m = mv[i]
    local prev = ctx.prev and ctx.prev.p[i]

    -- pending start not confirmed by the attack flag → it was movement, repaint
    if pend[i] and p.aflag ~= 1 then
      repaintFrame(i, pend[i].t, CLS.MOVEMENT)
      pend[i] = nil
    end

    -- new attack begins: aflag confirmation while not in a move, OR a fresh non-cancellable
    -- act at step 0 (pending) — including one canceled out of another move's recovery
    if not m.inMove then
      if p.aflag == 1 then
        beginMove(i, s); m = mv[i]
      elseif a >= 0x2B and p.step == 0 and prev and a ~= prev.act
             and not realActive(p) and not canc then
        pend[i] = { t = ctx.t, act = a, frz = frz }
        return CLS.STARTUP, inv, frz, canc
      end
    else
      if prev and p.act ~= prev.act and p.step == 0 and m.seenActive
         and not realActive(p) and a >= 0x2B
         and not (C.CANCELLABLE[p.char] and C.CANCELLABLE[p.char][a]) then
        endMove(i, "cancel")
        if p.aflag == 1 then
          beginMove(i, s); m = mv[i]
        else
          pend[i] = { t = ctx.t, act = a, frz = frz }
          return CLS.STARTUP, inv, frz, canc
        end
      end
    end

    if m.inMove then
      m.actChain[a] = true
      local act = realActive(p) and (p.step >= 1 or m.seenActive)
      if act then
        if m.seenActive and m.lastActiveT and ctx.t > m.lastActiveT + 1 then
          -- gap between active phases: close phase, repaint gap as startup
          if m.curPhase then m.phases[#m.phases + 1] = m.curPhase end
          m.phases[#m.phases + 1] = { gap = ctx.t - m.lastActiveT - 1 }
          m.curPhase = { a = 0 }
          repaintGap(i, m.lastActiveT + 1, ctx.t - 1)
        elseif not m.curPhase then
          m.curPhase = { a = 0 }
        end
        m.seenActive = true
        m.lastActiveT = ctx.t
        if not frz then m.A = m.A + 1; m.curPhase.a = m.curPhase.a + 1 end
        return CLS.ACTIVE, inv, frz, canc
      end
      if not m.seenActive then
        if not frz then m.S = m.S + 1 end
        return CLS.STARTUP, inv, frz, canc
      end
      -- post-active
      if C.isNeutralAct(a) then
        endMove(i, "done")
        -- fall through to neutral below
      else
        if not frz then m.R = m.R + 1 end
        return canc and CLS.RECOVERY_C or CLS.RECOVERY, inv, frz, canc
      end
    end

    if C.isBlockHoldAct(a) then return CLS.BLOCKHOLD, inv, frz, false end
    if C.isNeutralAct(a) then return CLS.NEUTRAL, inv, frz, false end
    if C.isAirAct(a) or a == 0x09 or a == 0x26 or a >= 0x2B then
      return CLS.MOVEMENT, inv, frz, canc
    end
    return CLS.OTHER, inv, frz, false
  end

  local function isAdvNeutral(a) return C.isNeutralAct(a) end

  local function step()
    local s = ctx.snap
    if not s then return end
    -- discontinuity guard (position resets, HP refills)
    if ctx.prev then
      for i = 1, 2 do
        if s.p[i].hp > ctx.prev.p[i].hp then M.reset() break end
      end
    end
    for i = 1, 2 do
      local cls, inv, frz, canc = classify(i, s)
      local pe = s.p[i]
      pe.cls, pe.inv, pe.frz, pe.canc = cls, inv, frz, canc
      pe.projActive = s.proj[i].alive and s.proj[i].hb ~= 0
    end
    -- connect detection (either direction)
    if ctx.prev then
      for d = 1, 2 do
        local atk = 3 - d
        local pd, qd = s.p[d], ctx.prev.p[d]
        local kind = nil
        if pd.hp < qd.hp and not C.isThrowVictimAct(pd.act) then kind = "hit"
        elseif C.isBlockstunAct(pd.act) and not C.isBlockstunAct(qd.act) then kind = "block"
        elseif pd.act == 0x1C and qd.act ~= 0x1C then kind = "throw"
        elseif pd.hp < qd.hp then kind = "hit" end
        if kind then
          local viaProj = not (s.p[atk].cls == CLS.ACTIVE) and s.proj[atk].alive
          inter = { atkI = atk, kind = kind, connectT = ctx.t }
          local ev = { attacker = atk, defender = d, kind = kind, t = ctx.t,
                       viaProj = viaProj, defPrevCls = qd.cls, defCls = pd.cls,
                       atkMv = mv[atk].inMove and mv[atk] or nil }
          emit("connect", ev)
          ctx.events[#ctx.events + 1] = ev
        end
      end
    end
    -- advantage settlement
    if inter then
      local a, d = inter.atkI, 3 - inter.atkI
      if not inter.atkNeutralT and isAdvNeutral(s.p[a].act) then inter.atkNeutralT = ctx.t end
      if not inter.atkCancelT and (s.p[a].canc or isAdvNeutral(s.p[a].act)) then
        inter.atkCancelT = ctx.t
      end
      -- the defender's reaction starts the frame AFTER connect: only accept their neutral
      -- once they have actually been in a constrained class since the connect
      local dc = s.p[d].cls
      if dc == CLS.HITSTUN or dc == CLS.BLOCKSTUN or dc == CLS.THROWN
         or dc == CLS.KNOCKDOWN or dc == CLS.TECH then
        inter.defConstrained = true
        inter.defNeutralT = nil
      end
      if inter.defConstrained and not inter.defNeutralT and isAdvNeutral(s.p[d].act) then
        inter.defNeutralT = ctx.t
      end
      local projLive = s.proj[1].alive or s.proj[2].alive
      if inter.atkNeutralT and inter.defNeutralT and not projLive then
        local adv = inter.defNeutralT - inter.atkNeutralT
        local cAdv = inter.atkCancelT and (inter.defNeutralT - inter.atkCancelT) or adv
        ctx.lastAdv = { atk = a, adv = adv, cAdv = cAdv, kind = inter.kind, t = ctx.t }
        emit("settled", ctx.lastAdv)
        inter = nil
      end
    end
  end

  function M.reset()
    mv = { newMv(), newMv() }
    inter = nil
  end

  table.insert(ctx.hooks.frame, step)
  table.insert(ctx.hooks.reset, function() M.reset() end)
end

return M
