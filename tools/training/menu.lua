-- menu.lua — keyboard settings overlay + pad conveniences.
--
-- Keyboard: M opens/closes; W/S select a row, A/D change the value. Settings persist to
-- traces/training_settings.lua on menu close (pcall'd; needs script io access in the GUI).
-- Pad (cfg.padControls, default on):
--   * hold R shoulder = momentary pad-swap (drive the dummy without recording)
--   * Select edge     = toggle record on the current slot (vendor-style flow)
local M = {}

function M.init(ctx)
  local C = ctx.C
  local SETTINGS = ctx.ROOT .. "../traces/training_settings.lua"
  local sel = 1

  local function dm() return ctx.mod.dummy end
  local function rec() return ctx.mod.recorder end

  local function cyc(list, cur, dir)
    for i, v in ipairs(list) do
      if v == cur then return list[((i - 1 + dir) % #list) + 1] end
    end
    return list[1]
  end

  local rows = {
    { "dummy",    function() return dm().enabled and "on" or "off" end,
                  function(d) dm().enabled = not dm().enabled end },
    { "pose",     function() return dm().pose end,
                  function(d) dm().pose = cyc({ "stand", "crouch", "jump" }, dm().pose, d) end },
    { "guard",    function() return dm().guard end,
                  function(d) dm().guard = cyc({ "off", "all", "afterhit" }, dm().guard, d) end },
    { "auto tech", function() return dm().tech and "on" or "off" end,
                  function(d) dm().tech = not dm().tech end },
    { "wakeup",   function() return dm().wakeup end,
                  function(d) dm().wakeup = cyc({ "off", "block", "jab", "backdash", "throw", "slot" }, dm().wakeup, d) end },
    { "rec slot", function() return tostring(rec().cur) .. " (" .. #rec().slots[rec().cur] .. "f)" end,
                  function(d) rec().cur = ((rec().cur - 1 + d) % 4) + 1 end },
    { "trigger",  function() return rec().trigger end,
                  function(d) rec().trigger = cyc({ "manual", "loop", "wakeup", "blockstun", "hitstun", "random" }, rec().trigger, d) end },
    { "hud mode", function() return tostring(ctx.ui.hudMode) end,
                  function(d) ctx.ui.hudMode = ((ctx.ui.hudMode - 1 + d) % 4) + 1 end },
    { "hud scale", function() return tostring(ctx.cfg.hudScale) end,
                  function(d) ctx.cfg.hudScale = math.max(1, math.min(4, ctx.cfg.hudScale + d)) end },
    { "hitboxes", function() return ctx.ui.hitboxes and "on" or "off" end,
                  function(d) ctx.ui.hitboxes = not ctx.ui.hitboxes end },
    { "S display", function() return ctx.ui.sConvSF6 and "SF6 (S incl. 1st active)" or "dustloop" end,
                  function(d) ctx.ui.sConvSF6 = not ctx.ui.sConvSF6 end },
    { "meter",    function() return ctx.ui.meterMode end,
                  function(d) ctx.ui.meterMode = (ctx.ui.meterMode == "auto") and "frozen" or "auto" end },
    { "timer",    function() return ctx.mod.regen.timerFreeze and "frozen" or "running" end,
                  function(d) ctx.mod.regen.timerFreeze = not ctx.mod.regen.timerFreeze end },
    { "hp regen", function() return ctx.mod.regen.hpRegen and "2s to max" or "off" end,
                  function(d) ctx.mod.regen.hpRegen = not ctx.mod.regen.hpRegen end },
    { "ko reset", function() return ctx.mod.regen.koReset and "on" or "off" end,
                  function(d) ctx.mod.regen.koReset = not ctx.mod.regen.koReset end },
    { "status",   function() return ctx.ui.labelMode end,
                  function(d) ctx.ui.labelMode = cyc({ "both", "combo", "meter", "off" }, ctx.ui.labelMode, d) end },
  }

  local function saveSettings()
    pcall(function()
      local f = assert(io.open(SETTINGS, "w"))
      f:write(string.format(
        "return { pose=%q, guard=%q, tech=%s, wakeup=%q, trigger=%q, hudMode=%d, " ..
        "hudScale=%d, hitboxes=%s, sConvSF6=%s, timerFreeze=%s, hpRegen=%s, koReset=%s, labelMode=%q }\n",
        dm().pose, dm().guard, tostring(dm().tech), dm().wakeup, rec().trigger,
        ctx.ui.hudMode, ctx.cfg.hudScale, tostring(ctx.ui.hitboxes), tostring(ctx.ui.sConvSF6),
        tostring(ctx.mod.regen.timerFreeze), tostring(ctx.mod.regen.hpRegen),
        tostring(ctx.mod.regen.koReset), ctx.ui.labelMode))
      f:close()
    end)
  end
  local function loadSettings()
    local ok, s = pcall(dofile, SETTINGS)
    if ok and type(s) == "table" then
      dm().pose = s.pose or dm().pose; dm().guard = s.guard or dm().guard
      if s.tech ~= nil then dm().tech = s.tech end
      dm().wakeup = s.wakeup or dm().wakeup
      rec().trigger = s.trigger or rec().trigger
      ctx.ui.hudMode = s.hudMode or ctx.ui.hudMode
      ctx.cfg.hudScale = s.hudScale or ctx.cfg.hudScale
      if s.hitboxes ~= nil then ctx.ui.hitboxes = s.hitboxes end
      if s.sConvSF6 ~= nil then ctx.ui.sConvSF6 = s.sConvSF6 end
      if s.timerFreeze ~= nil then ctx.mod.regen.timerFreeze = s.timerFreeze end
      if s.hpRegen ~= nil then ctx.mod.regen.hpRegen = s.hpRegen end
      if s.koReset ~= nil then ctx.mod.regen.koReset = s.koReset end
      ctx.ui.labelMode = s.labelMode or ctx.ui.labelMode
    end
  end
  loadSettings()

  ctx.actions.menu = function()
    ctx.ui.menuOpen = not ctx.ui.menuOpen
    if not ctx.ui.menuOpen then saveSettings() end
  end

  -- menu navigation keys (edge-detected, GUI only)
  local keyPrev = {}
  local function pressed(name)
    local ok, now = pcall(emu.isKeyPressed, name)
    if not ok then return false end
    local was = keyPrev[name]; keyPrev[name] = now
    return now and not was
  end
  local function nav()
    if not ctx.ui.menuOpen or ctx.headless then return end
    if pressed("W") then sel = ((sel - 2) % #rows) + 1 end
    if pressed("S") then sel = (sel % #rows) + 1 end
    if pressed("A") then rows[sel][3](-1) end
    if pressed("D") then rows[sel][3](1) end
  end

  -- pad conveniences (in the input pipeline, before recorder/dummy stages would matter —
  -- registered after them but only touches ui flags read next frame; edges via phys pads)
  local padPrev = { r = false, select = false }
  local function padStage()
    if ctx.headless or ctx.cfg.padControls == false then return end
    local p1 = ctx.pads.phys[1]
    -- hold R = momentary dummy control (only when not recording — recorder owns padSwap then)
    local recActive = ctx.mod.recorder.state == "armed" or ctx.mod.recorder.state == "recording"
    if not recActive then
      if p1.r and not padPrev.r then ctx.ui.padSwap = true end
      if not p1.r and padPrev.r then ctx.ui.padSwap = false end
    end
    padPrev.r = p1.r
    if p1.select and not padPrev.select then ctx.actions.record(ctx) end
    padPrev.select = p1.select
  end

  local function draw()
    if not ctx.ui.menuOpen then return end
    local hud = ctx.mod.hud
    local surf = hud.hudSurface()
    local x0, y0 = 20, 60
    if not surf then hud.console(); x0, y0 = 12, 40 end
    emu.drawRectangle(x0 - 6, y0 - 12, 210, #rows * 10 + 24, C.COL.bg, true)
    emu.drawString(x0, y0 - 10, "TRAINING MENU  (W/S row, A/D change, M close)", C.COL.warn, C.COL.black)
    for i, row in ipairs(rows) do
      local marker = (i == sel) and "> " or "  "
      local col = (i == sel) and C.COL.text or C.COL.dim
      emu.drawString(x0, y0 + i * 10, string.format("%s%-10s %s", marker, row[1], row[2]()), col, C.COL.black)
    end
  end

  table.insert(ctx.hooks.input, padStage)
  table.insert(ctx.hooks.frame, nav)
  table.insert(ctx.hooks.draw, draw)
end

return M
