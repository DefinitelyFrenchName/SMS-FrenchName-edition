-- combo.lua — combo counter: hit count + damage + TRUE/DROPPED tag per defender.
-- A hit while the defender has had an actionable frame since the previous hit marks the
-- combo DROPPED (SF6's "fake combo" blue). The combo closes when the defender has been
-- actionable ~10 frames with no live threat from the attacker.
local M = {}

function M.init(ctx)
  local C = ctx.C
  local CLS = C.CLS

  -- per defender index
  local combos = { { active = false }, { active = false } }
  ctx.combo = combos

  local FREE = { [CLS.NEUTRAL] = true, [CLS.MOVEMENT] = true, [CLS.BLOCKHOLD] = true }

  table.insert(ctx.mod.framedata.on.connect, function(ev)
    if ev.kind == "block" then return end
    local c = combos[ev.defender]
    local prevHP = ctx.prev and ctx.prev.p[ev.defender].hp or ctx.snap.p[ev.defender].hp
    if not c.active or c.defWasFree then
      -- fresh combo — a hit after the defender had an actionable frame RESTARTS the count
      -- (tagged reset=true so the HUD can show the pressure string wasn't a true combo)
      local reset = c.active and c.defWasFree or false
      c.active = true; c.hits = 0; c.startHP = prevHP; c.reset = reset
      c.freeFrames = 0; c.defWasFree = false
    end
    c.hits = c.hits + 1
    c.defWasFree = false
    c.freeFrames = 0
    c.lastHitT = ctx.t
    c.dmg = c.startHP - ctx.snap.p[ev.defender].hp
  end)

  local function step()
    local s = ctx.snap
    if not s then return end
    for d = 1, 2 do
      local c = combos[d]
      if c.active then
        c.dmg = c.startHP - s.p[d].hp
        local a = 3 - d
        -- the connect frame itself shows the defender's PRE-reaction class — only count
        -- freedom strictly after the hit frame
        if ctx.t > (c.lastHitT or -1) then
          if FREE[s.p[d].cls] then
            c.defWasFree = true
            c.freeFrames = c.freeFrames + 1
          else
            c.freeFrames = 0
          end
        end
        local threat = s.p[a].cls == CLS.ACTIVE or s.p[a].cls == CLS.STARTUP
                       or s.proj[a].alive
        if c.freeFrames >= 10 and not threat then
          c.active = false          -- keep last values for display
        end
      end
    end
  end

  table.insert(ctx.hooks.frame, step)
  table.insert(ctx.hooks.reset, function()
    combos[1] = { active = false }; combos[2] = { active = false }
    ctx.combo = combos
  end)
end

return M
