-- main.lua — orchestrator: builds the shared ctx, loads modules, owns the three callbacks.
--
-- FRAME-ORDERING CONTRACT (probe-verified):
--   inputPolled (input pipeline, sees ctx.t = N)  →  exec@$80:8353 (joy_read; savestate ops)
--   →  game logic for frame N  →  endFrame (frame hooks see post-frame state at ctx.t = N,
--   then ctx.t increments). A trigger detected at endFrame N can first act at inputPolled
--   N+1 — hence the recorder's tunable reversal_lead (default 1).
local M = {}

function M.run(ROOT, opts)
  opts = opts or {}
  local ctx = {
    ROOT = ROOT,
    frame = 0,           -- monotonically increasing since script start
    t = -1,              -- local frame counter, 0 at (first) savestate load / first exec
    hooks = { input = {}, frame = {}, draw = {}, reset = {} },
    ui = { menuOpen = false, hudMode = 1, padSwap = false, hitboxes = true,
           sConvSF6 = false, meterMode = "auto" },
    anchor = { loadreq = nil, savereq = false, posState = nil },
    events = {},
    actions = {},        -- name -> fn(ctx); hotkeys + menu dispatch through this
    headless = opts.headless or false,
    padSource = opts.padSource,
    mod = {},
  }
  ctx.C = dofile(ROOT .. "training/const.lua")

  -- defaults, overridable via tools/training_cfg.lua (plain globals)
  ctx.cfg = {
    hudScale = 2,
    keys = { menu = "M", hud = "9", boxes = "8", record = "R", play = "T",
             slot = "Y", trigger = "U", posSave = "Q", posLoad = "E",
             meterFreeze = "G", padSwap = "P", sConv = "F", reset = "0" },
    reversal_lead = 1,
    meterCells = 80,
    rollRows = 40,
  }
  pcall(dofile, ROOT .. "training_cfg.lua")
  if TM_CFG then for k, v in pairs(TM_CFG) do ctx.cfg[k] = v end end

  local MODULES = opts.modules or
    { "gamestate", "input", "recorder", "dummy", "framedata", "combo",
      "hud", "hud_panel", "hud_bar" }
  for _, name in ipairs(MODULES) do
    local m = dofile(ROOT .. "training/" .. name .. ".lua")
    if m and m.init then m.init(ctx) end
    ctx.mod[name] = m
  end

  -- exec anchor: the ONLY legal place for savestate ops
  emu.addMemoryCallback(function()
    if ctx.t < 0 then
      ctx.t = 0
      if ctx.onFirstExec then ctx.onFirstExec(ctx) end
    end
    if ctx.anchor.loadreq then
      emu.loadSavestate(ctx.anchor.loadreq)
      ctx.anchor.loadreq = nil
      ctx.t = 0
      for _, fn in ipairs(ctx.hooks.reset) do fn(ctx) end
      if ctx.onStateLoaded then ctx.onStateLoaded(ctx) end
    end
    if ctx.anchor.savereq then
      ctx.anchor.posState = emu.createSavestate()
      ctx.anchor.savereq = false
      if not ctx.headless then emu.displayMessage("training", "position saved") end
    end
  end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

  -- built-in actions
  ctx.actions.posSave = function() ctx.anchor.savereq = true end
  ctx.actions.posLoad = function()
    if ctx.anchor.posState then ctx.anchor.loadreq = ctx.anchor.posState end
  end
  ctx.actions.hud = function() ctx.ui.hudMode = (ctx.ui.hudMode % 4) + 1 end
  ctx.actions.boxes = function() ctx.ui.hitboxes = not ctx.ui.hitboxes end
  ctx.actions.padSwap = function() ctx.ui.padSwap = not ctx.ui.padSwap end
  ctx.actions.sConv = function() ctx.ui.sConvSF6 = not ctx.ui.sConvSF6 end

  -- host-keyboard hotkeys (GUI only; every isKeyPressed errors headless → pcall)
  local keyPrev = {}
  local function pressed(name)
    local ok, now = pcall(emu.isKeyPressed, name)
    if not ok then return false end
    local was = keyPrev[name]; keyPrev[name] = now
    return now and not was
  end
  local function hotkeys()
    for action, key in pairs(ctx.cfg.keys) do
      if pressed(key) and ctx.actions[action] then ctx.actions[action](ctx) end
    end
  end

  emu.addEventCallback(function()
    ctx.frame = ctx.frame + 1
    if ctx.t < 0 then return end
    ctx.events = {}
    for _, fn in ipairs(ctx.hooks.frame) do fn(ctx) end
    if not ctx.headless then hotkeys() end
    for _, fn in ipairs(ctx.hooks.draw) do fn(ctx) end
    ctx.t = ctx.t + 1
  end, emu.eventType.endFrame)

  return ctx
end

return M
