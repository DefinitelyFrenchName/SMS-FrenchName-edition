-- hud_combo.lua — big on-screen combo counter in the classic fighting-game spot: under
-- the ATTACKER's health bar (left when you combo the dummy, right when P2 combos you).
--
-- Drawn on the console surface (game pixels) so it renders chunky at window scale.
-- Counts are the engine's TRUE-chain semantics (combo.lua): only sequences in which the
-- defender never had an actionable frame — classic uninterrupted hitstun chains AND
-- seamless 1-frame meaties (Uranus infinite). Colors:
--   GOLD    = classic true chain (every hit landed in stun)
--   MAGENTA = the chain contains >=1 non-bufferable link (a hit that landed on the
--             defender's first out-of-stun frame) — shown with a "1F" tag
-- Appears from 2 hits, lingers ~1.2 s after the chain ends (blinks out).
local M = {}

function M.init(ctx)
  local C = ctx.C
  local hud = ctx.mod.hud

  local GOLD, MAGENTA = 0xFFD830, 0xFF40C0
  local MIN_HITS = 2
  local LINGER = 72

  -- per defender: what we're currently showing
  local show = { nil, nil }   -- {hits, dmg, tight, ttl}

  local function step()
    local s = ctx.snap
    if not s then return end
    for d = 1, 2 do
      local c = ctx.combo[d]
      if c.active and (c.hits or 0) >= MIN_HITS then
        show[d] = { hits = c.hits, dmg = c.dmg or 0, tight = c.tight, ttl = LINGER }
      elseif show[d] then
        -- keep the ended chain up a moment (also freshen dmg while it settles)
        show[d].ttl = show[d].ttl - 1
        if show[d].ttl <= 0 then show[d] = nil end
      end
    end
  end

  local function boldPrint(x, y, text, color)
    emu.drawString(x, y, text, 0x000000, 0x000000)        -- soft shadow block
    emu.drawString(x + 1, y + 1, text, 0x000000)
    emu.drawString(x, y, text, color)
    emu.drawString(x + 1, y, text, color)                 -- horizontal double = pseudo-bold
  end

  local function draw()
    if not hud.show("panel") then return end
    hud.console()
    for d = 1, 2 do
      local sh = show[d]
      if sh then
        local blink = sh.ttl < 20 and (sh.ttl % 6 < 3)
        if not blink then
          local atk = 3 - d
          local text = sh.hits .. " HITS" .. (sh.tight and " 1F" or "")
          local dmgText = sh.dmg .. " DMG"
          local w = #text * 6 + 1
          local x = (atk == 1) and 16 or (240 - w)
          local dx = (atk == 1) and 16 or (240 - #dmgText * 6)
          local col = sh.tight and MAGENTA or GOLD
          boldPrint(x, 56, text, col)                     -- just under the health bars
          emu.drawString(dx, 66, dmgText, 0xFFFFFF, 0x000000)
        end
      end
    end
    -- status line under the counter anchor (per side; shows even with no combo up)
    local lm = ctx.ui.labelMode
    if (lm == "combo" or lm == "both") and ctx.mod.labels then
      for i = 1, 2 do
        local st = ctx.mod.labels.side[i]
        if st and (st.ttl > 20 or st.ttl % 6 < 3) then
          local sx = (i == 1) and 16 or (240 - #st.text * 6)
          boldPrint(sx, 76, st.text, st.color)
        end
      end
    end
  end

  table.insert(ctx.hooks.frame, step)
  table.insert(ctx.hooks.draw, draw)
  table.insert(ctx.hooks.reset, function() show = { nil, nil } end)
end

return M
