-- labels.lua — event popups: MEATY / REVERSAL / PUNISH / COUNTER / THROW TECH / THROWN /
-- TRADE. All derived from framedata events + class history; drawn stacked above the frame
-- meter with a fade. COUNTER is SF-style "hit during startup" — informational only (this
-- game has no counter-hit bonus). M.fired collects {t, text} for headless assertions.
local M = {}

function M.init(ctx)
  local C = ctx.C
  local CLS = C.CLS
  local fd = ctx.mod.framedata   -- loaded before labels; hud loads after → looked up lazily

  local popups = {}     -- {text, color, ttl}
  M.fired = {}
  local TTL = 90

  local COLORS = {
    MEATY = 0xFF8020, REVERSAL = 0x40C0FF, PUNISH = 0xFF3030, COUNTER = 0xE0E040,
    ["THROW TECH"] = 0x40C0B0, THROWN = 0xA040C8, TRADE = 0xC0C0C0,
  }

  local lastText, lastT = nil, -99
  local function fire(text, who)
    local full = (who and ("P" .. who .. " ") or "") .. text
    if full == lastText and ctx.t - lastT < 30 then return end
    lastText, lastT = full, ctx.t
    table.insert(popups, 1, { text = full, color = COLORS[text] or C.COL.text, ttl = TTL })
    while #popups > 3 do table.remove(popups) end
    M.fired[#M.fired + 1] = { t = ctx.t, text = full }
  end
  M.fire = fire

  -- per-player constraint tracking (last frame the player was in a constrained class)
  local CONSTR = { [CLS.HITSTUN] = true, [CLS.BLOCKSTUN] = true, [CLS.KNOCKDOWN] = true,
                   [CLS.THROWN] = true }
  local lastConstrained = { -99, -99 }

  local function step()
    local s = ctx.snap
    if not s then return end
    for i = 1, 2 do
      if CONSTR[s.p[i].cls] then lastConstrained[i] = ctx.t end
      -- throw tech / thrown transitions
      local prev = ctx.prev and ctx.prev.p[i]
      if prev then
        if s.p[i].act == 0x23 and prev.act ~= 0x23 then fire("THROW TECH", i) end
        if (s.p[i].act == 0x1D or s.p[i].act == 0x1B) and prev.act == 0x1C then
          fire("THROWN", i)
        end
      end
    end
    -- trade: both connects this frame in opposite directions
    if #ctx.events >= 2 then
      local defs = {}
      for _, ev in ipairs(ctx.events) do defs[ev.defender] = true end
      if defs[1] and defs[2] then fire("TRADE") end
    end
    for k = #popups, 1, -1 do
      popups[k].ttl = popups[k].ttl - 1
      if popups[k].ttl <= 0 then table.remove(popups, k) end
    end
  end

  table.insert(fd.on.moveStart, function(ev)
    if ev.t - lastConstrained[ev.player] <= 2 then fire("REVERSAL", ev.player) end
  end)

  table.insert(fd.on.connect, function(ev)
    if ev.kind == "throw" then return end       -- thrown/tech labels handle throws
    local defClsAtHit = ev.defCls
    -- meaty: the attack was already active before this frame AND the defender's constraint
    -- ended within 2 frames of the connect (covers the same-frame-block case)
    local m = ev.atkMv
    local wasActiveEarly = m and m.firstActiveT and m.firstActiveT < ev.t
    if wasActiveEarly and ev.t - lastConstrained[ev.defender] <= 2 and ev.kind == "hit" then
      fire("MEATY", ev.attacker)
    end
    if ev.kind == "hit" then
      if defClsAtHit == CLS.RECOVERY or defClsAtHit == CLS.RECOVERY_C then
        fire("PUNISH", ev.attacker)
      elseif defClsAtHit == CLS.STARTUP or (defClsAtHit == CLS.ACTIVE) then
        fire("COUNTER", ev.attacker)
      end
    end
  end)

  local function draw()
    local hud = ctx.mod.hud
    if not hud or not hud.show("panel") or #popups == 0 then return end
    local surf = hud.hudSurface()
    if not surf then return end
    local w = surf.visibleWidth or surf.width
    local h = surf.visibleHeight or surf.height
    for k, p in ipairs(popups) do
      local y = h - 100 - (k - 1) * 12
      local x = math.floor(w / 2) - #p.text * 3
      if p.ttl > 20 or p.ttl % 4 < 2 then     -- blink at the end of life
        emu.drawString(x, y, p.text, p.color, C.COL.black)
      end
    end
  end

  table.insert(ctx.hooks.frame, step)
  table.insert(ctx.hooks.draw, draw)
  table.insert(ctx.hooks.reset, function()
    popups = {}; lastConstrained = { -99, -99 }; lastText = nil
  end)
end

return M
