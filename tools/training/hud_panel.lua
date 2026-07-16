-- hud_panel.lua — status panels: per-player char/action/class/HP, distance, last-move
-- summary + advantage line. Draws on ScriptHud when available; falls back to the console
-- surface (headless screenshots / ScriptHud problems) with a terser layout.
local M = {}

function M.init(ctx)
  local C = ctx.C
  local hud = ctx.mod.hud

  local function actName(p)
    return C.ACT_NAMES[p.act] or string.format("act %02X", p.act)
  end

  local function moveLine(i)
    local m = ctx.lastMove[i]
    if not m then return nil end
    local S = m.S + (ctx.ui.sConvSF6 and 1 or 0)
    local line = string.format("P%d %s  S%d A%d R%d T%d", i,
      C.ACT_NAMES[m.act] or string.format("%02X", m.act), S, m.A, m.R, m.total)
    local adv = ctx.lastAdv
    if adv and adv.atk == i then
      line = line .. string.format("  %s %+d", adv.kind, adv.adv)
      if adv.cAdv ~= adv.adv then line = line .. string.format(" (c%+d)", adv.cAdv) end
    end
    return line
  end

  local function draw()
    if not hud.show("panel") then return end
    local s = ctx.snap
    if not s then return end
    local surf = hud.hudSurface()
    if surf then
      local w = surf.visibleWidth or surf.width
      for i = 1, 2 do
        local p = s.p[i]
        local x = (i == 1) and 8 or (w - 150)
        emu.drawString(x, 4, string.format("%s  %s", C.CHAR_NAMES[p.char] or "?", actName(p)),
          C.COL.text, C.COL.black)
        emu.drawString(x, 14, string.format("%s%s%s  hp %d/%d",
          C.CLS_NAME[p.cls or 13] or "?", p.inv and " INV" or "", p.frz and " FRZ" or "",
          p.hp, p.maxhp), p.inv and C.COL.warn or C.COL.dim, C.COL.black)
      end
      emu.drawString(8, 24, string.format("dist %d", math.abs(s.p[1].x - s.p[2].x)),
        C.COL.dim, C.COL.black)
      local y = 34
      for i = 1, 2 do
        local line = moveLine(i)
        if line then emu.drawString(8, y, line, C.COL.text, C.COL.black); y = y + 10 end
      end
      if ctx.ui.padSwap then
        emu.drawString(8, y, ">> PAD SWAP: you are P2 <<", C.COL.accent, C.COL.black)
      end
    else
      -- console fallback (small)
      hud.console()
      local p1, p2 = s.p[1], s.p[2]
      emu.drawString(8, 8, string.format("P1 %s %s | P2 %s %s",
        actName(p1), C.CLS_NAME[p1.cls or 13] or "?",
        actName(p2), C.CLS_NAME[p2.cls or 13] or "?"), C.COL.text, C.COL.black)
      local line = moveLine(1) or moveLine(2)
      if line then emu.drawString(8, 17, line, C.COL.warn, C.COL.black) end
    end
  end

  table.insert(ctx.hooks.draw, draw)
end

return M
