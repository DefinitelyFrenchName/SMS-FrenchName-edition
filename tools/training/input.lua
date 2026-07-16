-- input.lua — the input pipeline (runs in the inputPolled callback).
--
-- Order (probe-verified: getInput at the top of inputPolled = physical pad):
--   1. read physical pads for both ports -> ctx.pads.phys[i]
--   2. apply pad-swap -> ctx.pads.eff[i]  (user's pad can drive the dummy)
--   3. run ctx.hooks.input stages (menu, recorder, dummy, playback) — a stage may set
--      ctx.out[i] = pad table (override) — later stages win by overwriting
--   4. emu.setInput(out or eff, 0, port) for BOTH ports (port = 3rd arg!)
local M = {}

function M.init(ctx)
  local C = ctx.C

  local function copyPad(src)
    local t = {}
    for _, k in ipairs(C.PAD_KEYS) do t[k] = src[k] or false end
    return t
  end

  -- pad table -> normalized mask (side-aware: back/fwd from onLeft)
  function M.maskOf(pad, onLeft)
    local m = 0
    if pad.down then m = m + C.M_DOWN end
    if pad.up then m = m + C.M_UP end
    local back, fwd = pad.left, pad.right
    if not onLeft then back, fwd = pad.right, pad.left end
    if back then m = m + C.M_BACK end
    if fwd then m = m + C.M_FWD end
    for key, bit in pairs(C.BTN_OF_KEY) do
      if pad[key] then m = m + bit end
    end
    return m
  end

  -- normalized mask -> pad table for a player currently on side onLeft
  function M.padOf(mask, onLeft)
    local t = copyPad(C.FALSE_PAD)
    local band = function(b) return mask % (b + b) >= b end
    t.down = band(C.M_DOWN); t.up = band(C.M_UP)
    local back, fwd = band(C.M_BACK), band(C.M_FWD)
    if onLeft then t.left, t.right = back, fwd
    else t.left, t.right = fwd, back end
    for key, bit in pairs(C.BTN_OF_KEY) do t[key] = band(bit) end
    return t
  end

  -- default pad source; the headless test harness replaces this
  ctx.padSource = ctx.padSource or function(port)
    local ok, t = pcall(emu.getInput, port)
    if ok and type(t) == "table" then return t end
    return C.FALSE_PAD
  end

  local function pipeline()
    local phys = { copyPad(ctx.padSource(0)), copyPad(ctx.padSource(1)) }
    local eff
    if ctx.ui.padSwap then
      eff = { copyPad(C.FALSE_PAD), phys[1] }
    else
      eff = { phys[1], phys[2] }
    end
    ctx.pads = { phys = phys, eff = eff }
    ctx.out = { nil, nil }
    for _, fn in ipairs(ctx.hooks.input) do fn(ctx) end
    for i = 1, 2 do
      emu.setInput(ctx.out[i] or eff[i], 0, i - 1)
    end
  end

  emu.addEventCallback(pipeline, emu.eventType.inputPolled)
end

return M
