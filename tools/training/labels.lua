-- labels.lua — event popups: GC / REVERSAL / PUNISH / THROW TECH / THROWN / TRADE.
-- (A MEATY label existed through v0.20; removed 2026-07-20 on player feedback — it read
-- as noise/backseat-coaching in live play. The meaty *timing* facts live in patch_notes.)
-- All derived from framedata events + class history; drawn above the frame meter and/or
-- under the combo counter (ctx.ui.labelMode). M.fired collects {t, text} for tests.
--
-- GC (guard cancel) is this game's defining mechanic: a special canceling blockstun.
-- Measured (Mars fireball out of blocked Uranus 2HP): the special's act starts DIRECTLY
-- from a blockstun act (0x0E/0x0F -> attack act, stun flag still set on the transition
-- frame) — so the trigger is a move starting <=1 frame from a BLOCKSTUN frame. REVERSAL
-- is scoped to hard-constraint exits (hitstun/knockdown/throw) so the two never overlap.
-- (No COUNTER label: the game has no counter-hit bonus.)
local M = {}

function M.init(ctx)
  local C = ctx.C
  local CLS = C.CLS
  local fd = ctx.mod.framedata   -- loaded before labels; hud loads after → looked up lazily

  local popups = {}     -- {text, color, ttl}
  M.fired = {}
  M.side = { nil, nil } -- latest label per player, for the under-combo-counter display
  local TTL = 90
  ctx.ui.labelMode = ctx.ui.labelMode or "both"   -- off | meter | combo | both

  local COLORS = {
    REVERSAL = 0x40C0FF, PUNISH = 0xFF3030, GC = 0x40FF80,
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
    -- per-side slot (the side already conveys the player, so no P-prefix here)
    local entry = { text = text, color = COLORS[text] or C.COL.text, ttl = TTL }
    if who then M.side[who] = entry
    else M.side[1] = entry; M.side[2] = { text = text, color = entry.color, ttl = TTL } end
  end
  M.fire = fire

  -- per-player constraint tracking (last frame the player was in a constrained class);
  -- blockstun tracked separately: exits into a move are GC, hard-constraint exits REVERSAL
  local HARD = { [CLS.HITSTUN] = true, [CLS.KNOCKDOWN] = true, [CLS.THROWN] = true }
  local lastHard = { -99, -99 }
  local lastBlockstun = { -99, -99 }

  local function step()
    local s = ctx.snap
    if not s then return end
    for i = 1, 2 do
      local cls = s.p[i].cls
      if HARD[cls] then lastHard[i] = ctx.t end
      if cls == CLS.BLOCKSTUN then lastBlockstun[i] = ctx.t end
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
    for i = 1, 2 do
      if M.side[i] then
        M.side[i].ttl = M.side[i].ttl - 1
        if M.side[i].ttl <= 0 then M.side[i] = nil end
      end
    end
  end

  table.insert(fd.on.moveStart, function(ev)
    if ev.t - lastBlockstun[ev.player] <= 1 then fire("GC", ev.player)
    elseif ev.t - lastHard[ev.player] <= 2 then fire("REVERSAL", ev.player) end
  end)

  table.insert(fd.on.connect, function(ev)
    if ev.kind == "throw" then return end       -- thrown/tech labels handle throws
    local defClsAtHit = ev.defCls
    if ev.kind == "hit" then
      if defClsAtHit == CLS.RECOVERY or defClsAtHit == CLS.RECOVERY_C then
        fire("PUNISH", ev.attacker)
      end
    end
  end)

  local function draw()
    local lm = ctx.ui.labelMode
    if lm ~= "meter" and lm ~= "both" then return end
    local hud = ctx.mod.hud
    if not hud or not hud.show("bar") or #popups == 0 then return end  -- issue #19: meter popups follow the meter
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
    popups = {}; M.side = { nil, nil }; lastText = nil; M.fired = {}  -- issue #15
    lastHard = { -99, -99 }; lastBlockstun = { -99, -99 }
  end)
end

return M
