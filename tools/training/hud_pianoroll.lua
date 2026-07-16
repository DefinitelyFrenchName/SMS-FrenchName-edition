-- hud_pianoroll.lua — TAStudio-style per-frame input history strip (ScriptHud, right edge).
--
-- One row per frame scrolling upward (newest at the bottom), showing the tracked player's
-- inputs: direction as numpad notation (fighting-game standard: 1=down-back .. 9=up-fwd,
-- 5 omitted) + one colored letter column per button (P K H K = LP LK HP HK). Consecutive
-- identical rows compress into one row with a xN count. Shows P1 by default; auto-switches
-- to the dummy side while recording/playing back.
local M = {}

function M.init(ctx)
  local C = ctx.C
  local hud = ctx.mod.hud
  local input = ctx.mod.input
  local gs = ctx.mod.gamestate

  local rows = {}       -- newest last: {mask=, n=count}
  local MAXROWS = 200   -- raw storage; display trims to cfg.rollRows

  local BTN_COLS = {
    { bit = C.M_LP, ch = "P", col = 0x60C0FF },
    { bit = C.M_LK, ch = "K", col = 0x60FF90 },
    { bit = C.M_HP, ch = "P", col = 0x3080FF },
    { bit = C.M_HK, ch = "K", col = 0x30C060 },
  }

  local function trackedPlayer()
    local rec = ctx.mod.recorder
    if ctx.ui.padSwap or (rec and rec.state == "playing") then return 2 end
    return 1
  end

  local function dirDigit(mask)
    local band = function(b) return mask % (b + b) >= b end
    local x = band(C.M_FWD) and 1 or band(C.M_BACK) and -1 or 0
    local y = band(C.M_UP) and 1 or band(C.M_DOWN) and -1 or 0
    local grid = { [-1] = { [-1] = 1, [0] = 4, [1] = 7 },
                   [0]  = { [-1] = 2, [0] = 5, [1] = 8 },
                   [1]  = { [-1] = 3, [0] = 6, [1] = 9 } }
    return grid[x][y]
  end

  local function step()
    local s = ctx.snap
    if not s then return end
    local i = trackedPlayer()
    -- what the player's character actually received this frame (post-swap/override)
    local pad = ctx.out and ctx.out[i] or (ctx.pads and ctx.pads.eff[i])
    if not pad then return end
    local mask = input.maskOf(pad, gs.onLeft(i))
    local last = rows[#rows]
    if last and last.mask == mask then
      last.n = last.n + 1
    else
      rows[#rows + 1] = { mask = mask, n = 1 }
      if #rows > MAXROWS then table.remove(rows, 1) end
    end
  end

  local function draw()
    if not hud.show("roll") then return end
    local surf = hud.hudSurface()
    if not surf or #rows == 0 then return end
    local w = surf.visibleWidth or surf.width
    local x0 = w - 58
    local rowH = 9
    local nShow = math.min(#rows, ctx.cfg.rollRows)
    local yTop = 40
    emu.drawRectangle(x0 - 3, yTop - 12, 58, nShow * rowH + 16, C.COL.bg, true)
    emu.drawString(x0, yTop - 11, "P" .. trackedPlayer() .. " inputs", C.COL.dim, C.COL.black)
    for k = 1, nShow do
      local rw = rows[#rows - nShow + k]
      local y = yTop + (k - 1) * rowH
      local d = dirDigit(rw.mask)
      if d ~= 5 then
        emu.drawString(x0, y, tostring(d), C.COL.text, C.COL.black)
      end
      local x = x0 + 8
      for _, bc in ipairs(BTN_COLS) do
        if rw.mask % (bc.bit + bc.bit) >= bc.bit then
          emu.drawString(x, y, bc.ch, bc.col, C.COL.black)
        end
        x = x + 7
      end
      if rw.n > 1 then
        emu.drawString(x0 + 38, y, "x" .. (rw.n > 99 and "99+" or rw.n), C.COL.dim, C.COL.black)
      end
    end
  end

  table.insert(ctx.hooks.frame, step)
  table.insert(ctx.hooks.draw, draw)
  table.insert(ctx.hooks.reset, function() rows = {} end)
end

return M
