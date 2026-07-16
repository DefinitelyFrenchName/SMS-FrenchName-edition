-- hud.lua — draw dispatcher + surface helpers. Other hud_* modules call M.hudSurface()
-- to get the ScriptHud canvas (nil when degenerate, e.g. headless) and M.console() to
-- target the 256x224 game-aligned surface. hudMode: 1=full 2=bar-only 3=panel-only 4=off.
local M = {}

function M.init(ctx)
  local cache = { f = -1, s = nil }

  function M.hudSurface()
    if cache.f == ctx.frame then
      if cache.s then pcall(emu.selectDrawSurface, emu.drawSurface.scriptHud, ctx.cfg.hudScale) end
      return cache.s
    end
    cache.f = ctx.frame
    local ok = pcall(emu.selectDrawSurface, emu.drawSurface.scriptHud, ctx.cfg.hudScale)
    if not ok then cache.s = nil; return nil end
    local ok2, s = pcall(emu.getDrawSurfaceSize)
    if not ok2 or type(s) ~= "table" or (s.width or 0) < 300 then cache.s = nil; return nil end
    cache.s = s
    return s
  end

  function M.console()
    pcall(emu.selectDrawSurface, emu.drawSurface.consoleScreen)
  end

  function M.show(part)   -- part: "bar" | "panel" | "roll" | "boxes"
    local m = ctx.ui.hudMode
    if m == 4 then return false end
    if m == 2 then return part == "bar" end
    if m == 3 then return part == "panel" end
    return true
  end
end

return M
