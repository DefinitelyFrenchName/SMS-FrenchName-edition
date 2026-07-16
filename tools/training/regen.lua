-- regen.lua — training conveniences: frozen timer, dummy HP auto-restore, KO auto-reset.
--
-- * Timer freeze (default on): rewrites the BCD round timer $7E:0802 every frame with the
--   value captured when the freeze (re)armed — the vendor tool's proven approach.
-- * HP regen (default on): restores P2 (the dummy) to its character's MAX HP (+0x4A) after
--   2 seconds (120 frames) without taking damage, gated on the dummy being actionable and
--   no combo being open, so a slow knockdown string can't trigger a mid-sequence refill.
--   The HUD life bar has its OWN latched value ($7E:0800 = P1 bar, $7E:0801 = P2 bar —
--   found by WRAM diff: it only updates through the damage routine), so the refill writes
--   both the struct HP and the bar value; otherwise the bar stays visually damaged.
--   (framedata treats HP increases as discontinuities and resets cleanly, so the refill
--   produces no ghost events. Restore-to-combo-start is a possible future variant.)
-- * KO reset (default on): if either player enters KO (act 0x1F), reload the position
--   savestate (Q) — a baseline is auto-captured shortly after the session starts if you
--   never pressed Q — so a kill never reaches the round-end / menu flow.
local M = {}

function M.init(ctx)
  local C = ctx.C
  local TIMER = 0x0802
  local REGEN_FRAMES = 120
  local FREE = {}
  do
    local CLS = C.CLS
    FREE[CLS.NEUTRAL] = true; FREE[CLS.MOVEMENT] = true; FREE[CLS.BLOCKHOLD] = true
  end

  M.timerFreeze = true
  M.hpRegen = true
  M.koReset = true

  local HPBAR = 0x0800          -- +0 = P1 displayed HP, +1 = P2 (latched by damage routine)
  local timerVal = nil          -- captured lazily; nil = re-capture next frame
  local lastDamageT = 0

  local function step()
    local s = ctx.snap
    if not s then return end

    if M.timerFreeze then
      if not timerVal then timerVal = emu.read(TIMER, C.WRAM) end
      emu.write(TIMER, timerVal, C.WRAM)
    else
      timerVal = nil
    end

    if M.hpRegen then
      local p = s.p[2]
      if ctx.prev and p.hp < ctx.prev.p[2].hp then lastDamageT = ctx.t end
      if p.hp < p.maxhp and ctx.t - lastDamageT >= REGEN_FRAMES
         and FREE[p.cls] and not (ctx.combo and ctx.combo[2].active) then
        emu.write(C.BASE[2] + C.OFF.hp, p.maxhp, C.WRAM)
        emu.write(HPBAR + 1, p.maxhp, C.WRAM)      -- keep the life bar in sync
        lastDamageT = ctx.t
      end
    end

    if M.koReset then
      -- auto-capture a baseline position state early on, so a KO always has a target
      if not ctx.anchor.posState and ctx.t == 30 then ctx.anchor.savereq = true end
      -- death = damage EXCEEDED remaining HP (a hit landing at exactly 0 leaves you alive
      -- in this engine — measured); the dead player falls through knockdown acts at hp 0.
      -- Trigger on that instead of the late KO act (0x1F arrives ~130f after the hit).
      for i = 1, 2 do
        local p = s.p[i]
        if p.hp == 0 and (C.isKDAct(p.act) or p.act == 0x1F) and ctx.anchor.posState then
          ctx.anchor.loadreq = ctx.anchor.posState
          break
        end
      end
    end
  end

  table.insert(ctx.hooks.frame, step)
  table.insert(ctx.hooks.reset, function()
    timerVal = nil               -- savestate loads bring their own timer; re-capture
    lastDamageT = 0
  end)
end

return M
