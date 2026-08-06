-- dummy.lua — composable dummy behavior layers for the non-swapped player (default P2).
--
-- A dummy frame resolves through a priority stack; the first layer that returns a pad
-- mask wins (recorder playback overrides everything and is handled by recorder.lua):
--   1. wakeup one-shot  (block / jab / backdash / throw / play recording slot)
--   2. throw-tech mash  (fresh press every other frame while held — 30Hz latch, patch-8
--      measured mechanics: 2 sampled presses escape for half damage)
--   3. guard            (off / all / after-first-hit)
--   4. pose             (stand / crouch / jump)
-- Keyboard quick-modes 1-7 mirror the old trainer.lua set; the menu (P6) exposes all axes.
local M = {}

function M.init(ctx)
  local C = ctx.C
  local CLS = C.CLS
  local input = ctx.mod.input
  local gs = ctx.mod.gamestate

  M.port = 2                    -- dummy player index
  M.pose = "stand"              -- stand|crouch|jump
  M.guard = "off"               -- off|all|afterhit
  M.tech = true                 -- auto throw-tech
  M.wakeup = "off"              -- off|block|jab|backdash|throw|slot
  M.enabled = true

  local gotHit = false          -- for guard=afterhit
  local wakeArmed = false
  local backdashPhase = 0
  local oneshot = { mask = 0, frames = 0 }   -- held a few frames (30Hz input latch)

  -- quick modes (keyboard 1-7, trainer.lua parity)
  local QUICK = {
    { name = "off",          set = { enabled = false } },
    { name = "guard all",    set = { enabled = true, guard = "all", pose = "stand", wakeup = "off" } },
    { name = "guard after hit", set = { enabled = true, guard = "afterhit", pose = "stand" } },
    { name = "crouch",       set = { enabled = true, guard = "off", pose = "crouch", wakeup = "off" } },
    { name = "wakeup jab",   set = { enabled = true, guard = "off", wakeup = "jab" } },
    { name = "wakeup backdash", set = { enabled = true, guard = "off", wakeup = "backdash" } },
    { name = "wakeup slot",  set = { enabled = true, guard = "off", wakeup = "slot" } },
  }
  for n, q in ipairs(QUICK) do
    ctx.actions["dummy" .. n] = function()
      for k, v in pairs(q.set) do M[k] = v end
      if not ctx.headless then emu.displayMessage("training", "dummy: " .. q.name) end
    end
    ctx.cfg.keys["dummy" .. n] = tostring(n)
  end

  local function mask(...)
    local m = 0
    for _, b in ipairs({ ... }) do m = m + b end
    return m
  end

  -- input stage (after recorder: recorder set ctx.out[port] already if playing).
  -- NOTE: runs at inputPolled, so ctx.snap is the last CLASSIFIED frame (frame hooks
  -- ordered dummy-before-framedata would see cls=nil — track state here instead).
  local function stage()
    if not M.enabled then return end
    local i = M.port
    if ctx.out[i] then return end                      -- playback wins
    if ctx.ui.padSwap then return end                  -- user is driving the dummy
    local s = ctx.snap
    if not s then return end
    local d = s.p[i]
    if d.cls == CLS.HITSTUN or d.cls == CLS.THROWN then gotHit = true end
    if d.cls == CLS.KNOCKDOWN or d.cls == CLS.THROWN then wakeArmed = true end
    local onL = gs.onLeft(i)
    local m = nil

    -- 1. wakeup one-shot on leaving a constrained state
    if wakeArmed and (d.cls == CLS.NEUTRAL or d.cls == CLS.MOVEMENT or d.cls == CLS.BLOCKHOLD)
       and M.wakeup ~= "off" then
      wakeArmed = false
      if M.wakeup == "jab" then oneshot = { mask = mask(C.M_LP), frames = 3 }
      elseif M.wakeup == "throw" then oneshot = { mask = mask(C.M_FWD, C.M_HP), frames = 3 }
      elseif M.wakeup == "backdash" then backdashPhase = 6
      elseif M.wakeup == "slot" and ctx.mod.recorder then
        ctx.mod.recorder.startPlay()
        return
      elseif M.wakeup == "block" then
        -- just fall through to guard layer with gotHit set
        gotHit = true
      end
    end
    if oneshot.frames > 0 then
      m = oneshot.mask
      oneshot.frames = oneshot.frames - 1
    end
    if backdashPhase > 0 then
      -- double-tap back: back,neutral,back held briefly
      local ph = 7 - backdashPhase
      if ph == 1 or ph >= 3 then m = mask(C.M_BACK) else m = 0 end
      backdashPhase = backdashPhase - 1
    end

    -- 2. throw-tech mash (fresh press every other frame; +0x50 latches at 30Hz).
    -- (#44: the original `(act == 0x1C or hurt >= 0x80 and act == 0x1C)` was a
    -- tautology — `and` binds tighter than `or`, so the hurt term had no effect.
    -- Simplified to what it always computed; if an invulnerable-frame exclusion
    -- was ever intended, that is a new feature, not a restoration.)
    if not m and M.tech and d.act == 0x1C then
      m = (ctx.t % 2 == 0) and mask(C.M_HK) or 0
    end

    -- 3. guard
    if not m and M.guard ~= "off" and (M.guard == "all" or gotHit) then
      m = mask(C.M_BACK, C.M_DOWN)                     -- down-back blocks everything blockable
    end

    -- 4. pose ("stand" = NO override, so a second pad / scripted input can drive the dummy)
    if not m then
      if M.pose == "crouch" then m = mask(C.M_DOWN)
      elseif M.pose == "jump" then m = mask(C.M_UP)
      else return end
    end

    ctx.out[i] = input.padOf(m, onL)
  end

  table.insert(ctx.hooks.input, stage)
  table.insert(ctx.hooks.reset, function()
    gotHit = false; wakeArmed = false; backdashPhase = 0
    oneshot = { mask = 0, frames = 0 }
  end)
end

return M
