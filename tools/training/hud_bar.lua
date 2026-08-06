-- hud_bar.lua — the SF6-style frame meter (ScriptHud only).
--
-- Two tracks (P1 top / P2 bottom) of per-frame cells colored by class. SF6 freeze model:
-- cells append only while there is activity (either player non-neutral or a projectile
-- alive) plus a K-frame grace, so the last exchange stays on screen while both idle.
-- Cells hold REFS into the gamestate ring buffer, so retroactive repaints (multi-hit gaps)
-- appear automatically. Segment counts (non-frozen frames) print at run starts; the
-- advantage badge lands between the tracks at the settlement column. 'G' toggles a hard
-- freeze; ctx.ui.meterMode: "auto" | "frozen".
local M = {}

function M.init(ctx)
  local C, CLS = ctx.C, ctx.C.CLS
  local hud = ctx.mod.hud
  local K_GRACE = 20
  local cells = {}          -- oldest..newest snap refs
  local quiet = 9999
  local badges = {}         -- [snapRef] = { text=, color= }

  ctx.actions.meterFreeze = function()
    ctx.ui.meterMode = (ctx.ui.meterMode == "frozen") and "auto" or "frozen"
  end

  local IDLE = { [CLS.NEUTRAL] = true, [CLS.MOVEMENT] = true, [CLS.BLOCKHOLD] = true }
  local COUNTED = { [CLS.STARTUP] = true, [CLS.ACTIVE] = true, [CLS.RECOVERY] = true,
                    [CLS.RECOVERY_C] = true, [CLS.HITSTUN] = true, [CLS.BLOCKSTUN] = true,
                    [CLS.THROWN] = true, [CLS.KNOCKDOWN] = true }

  local function activity(s)
    for i = 1, 2 do
      if not IDLE[s.p[i].cls or CLS.OTHER] then return true end
      if s.proj[i].alive then return true end
    end
    return false
  end

  local function step()
    local s = ctx.snap
    if not s or ctx.ui.meterMode == "frozen" then return end
    if activity(s) then quiet = 0 else quiet = quiet + 1 end
    if quiet <= K_GRACE then
      cells[#cells + 1] = s
      local max = ctx.cfg.meterCells
      while #cells > max do
        badges[cells[1]] = nil
        table.remove(cells, 1)
      end
    end
  end

  if ctx.mod.framedata then
    table.insert(ctx.mod.framedata.on.settled, function(adv)
      local ref = cells[#cells]
      if ref then
        badges[ref] = { text = string.format("%+d", adv.adv),
                        color = adv.adv >= 0 and C.COL.good or C.COL.bad }
      end
    end)
  end

  local function draw()
    if not hud.show("bar") then return end
    local surf = hud.hudSurface()
    if not surf or #cells == 0 then return end
    local w = surf.visibleWidth or surf.width
    local h = surf.visibleHeight or surf.height
    local pitch, cw = 6, 5
    local n = #cells
    local x0 = math.floor((w - n * pitch) / 2)
    -- 12px inter-track gap (issue #50: at h-46 the advantage badge at y1+12 overlapped
    -- the P2 track's top ~7px; the badge now genuinely lands between the tracks)
    local y1, y2 = h - 60, h - 38        -- P1 track, P2 track tops (10px tall)
    emu.drawRectangle(x0 - 2, y1 - 12, n * pitch + 4, 56, C.COL.bg, true)

    for k = 1, n do
      local ref = cells[k]
      local x = x0 + (k - 1) * pitch
      for i = 1, 2 do
        local pe = ref.p[i]
        local y = (i == 1) and y1 or y2
        emu.drawRectangle(x, y, cw, 10, C.CLS_COLOR[pe.cls or CLS.OTHER], true)
        if pe.frz then emu.drawRectangle(x, y, cw, 10, 0xA0101010, true) end
        if pe.inv then emu.drawRectangle(x, y, cw, 2, C.COL.invuln, true) end
        if pe.canc then emu.drawRectangle(x, y + 8, cw, 2, C.COL.cancel, true) end
        if pe.projActive then
          emu.drawRectangle(x, (i == 1) and (y1 - 4) or (y2 + 12), cw, 2,
            C.CLS_COLOR[CLS.ACTIVE], true)
        end
      end
      local b = badges[ref]
      if b then emu.drawString(x - 4, y1 + 12, b.text, b.color, C.COL.black) end
    end

    -- segment counts (non-frozen frames), printed at run starts
    for i = 1, 2 do
      local runCls, runStart, runCount = nil, nil, 0
      local function flush()
        if runCls and COUNTED[runCls] and runCount > 0 then
          local x = x0 + (runStart - 1) * pitch
          local y = (i == 1) and (y1 - 11) or (y2 + 12)
          emu.drawString(x, y, tostring(runCount), C.CLS_COLOR[runCls], C.COL.black)
        end
      end
      for k = 1, n do
        local pe = cells[k].p[i]
        local cls = pe.cls or CLS.OTHER
        local merged = (cls == CLS.RECOVERY_C) and CLS.RECOVERY or cls
        if merged ~= runCls then
          flush()
          runCls, runStart, runCount = merged, k, 0
        end
        if not pe.frz then runCount = runCount + 1 end
      end
      flush()
    end
  end

  table.insert(ctx.hooks.frame, step)
  table.insert(ctx.hooks.draw, draw)
  table.insert(ctx.hooks.reset, function() cells = {}; badges = {}; quiet = 9999 end)
end

return M
