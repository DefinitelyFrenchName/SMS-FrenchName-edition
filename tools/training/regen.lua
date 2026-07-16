-- regen.lua — training conveniences: frozen round timer + dummy HP auto-restore.
--
-- * Timer freeze (default on): rewrites the BCD round timer $7E:0802 every frame with the
--   value captured when the freeze (re)armed — the vendor tool's proven approach.
-- * HP regen (default on): restores P2 (the dummy) to its character's MAX HP (+0x4A) after
--   2 seconds (120 frames) without taking damage, gated on the dummy being actionable and
--   no combo being open, so a slow knockdown string can't trigger a mid-sequence refill.
--   (framedata treats HP increases as discontinuities and resets cleanly, so the refill
--   produces no ghost events. Restore-to-combo-start is a possible future variant.)
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
        lastDamageT = ctx.t
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
