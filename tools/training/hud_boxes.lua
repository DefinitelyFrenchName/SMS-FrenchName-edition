-- hud_boxes.lua — hitbox/hurtbox/collision overlay on the ConsoleScreen surface (aligns
-- with game pixels). Box data is read live from the ROM tables in bank $8A (pointer tables
-- indexed by charID*2: hit $8A:C1F1 8-byte entries, hurt $8A:C229 16-byte body+head pairs,
-- coll $8A:C23D 8-byte), so ROM-hack box patches (e.g. patch 7) render truthfully.
-- Box format [x_off_r, w_r, x_off_l, w_l, y_off(signed), h, flags, ?]: origin at the feet,
-- +y down; facing selects the (x_off, w) pair. Colors: attack red, hurt body green /
-- head yellow, collision blue. Hurtboxes hidden while invulnerable (idx 0 / hurt>=0x80).
-- Projectile slots draw with their owner's tables. Toggle: key '8'.
local M = {}

function M.init(ctx)
  local C = ctx.C
  local hud = ctx.mod.hud
  local BUS = emu.memType.snesMemory
  local function r8(a) return emu.read(a, BUS) end
  local function r16(a) return r8(a) + 256 * r8(a + 1) end
  local function sgn(v) return v > 127 and v - 256 or v end

  local PT_HIT, PT_HURT, PT_COLL = 0x8AC1F1, 0x8AC229, 0x8AC23D

  -- cache per charID: table base addresses
  local bases = {}
  local function tablesFor(char)
    local b = bases[char]
    if not b then
      b = { hit = 0x8A0000 + r16(PT_HIT + char * 2),
            hurt = 0x8A0000 + r16(PT_HURT + char * 2),
            coll = 0x8A0000 + r16(PT_COLL + char * 2) }
      bases[char] = b
    end
    return b
  end

  local function readBox(addr, facingLeft)
    local xo, w
    if facingLeft then xo, w = sgn(r8(addr + 2)), r8(addr + 3)
    else xo, w = sgn(r8(addr)), r8(addr + 1) end
    local yo, h = sgn(r8(addr + 4)), r8(addr + 5)
    if h == 0 or w == 0 then return nil end
    return xo, w, yo, h
  end

  local function drawBox(sx, sy, addr, facingLeft, color)
    local xo, w, yo, h = readBox(addr, facingLeft)
    if not xo then return end
    local x, y = sx + xo, sy + yo
    emu.drawRectangle(x, y, w, h, 0xC8000000 + color, true)   -- faint fill (high alpha = more transparent)
    emu.drawRectangle(x, y, w, h, color, false)
  end

  local function drawFor(base, snapP)
    if not snapP or snapP.char == 0 or snapP.char > 9 then return end
    local s = ctx.snap
    local wramR = function(a) return emu.read(a, C.WRAM) end
    local x = wramR(base + 0x21) + 256 * wramR(base + 0x22)
    local y = wramR(base + 0x25) + 256 * wramR(base + 0x26)
    local camX = s.cam
    local camY = wramR(C.CAMERA_X + 2) + 256 * wramR(C.CAMERA_X + 3)
    local sx, sy = x - camX, y - camY
    local facingLeft = wramR(base + 0x09) ~= 0
    local hb, hub, coll = wramR(base + 0x40), wramR(base + 0x41), wramR(base + 0x42)
    local hurtState = wramR(base + 0x46)
    local step = wramR(base + 0x02)
    local T = tablesFor(snapP.char)
    if coll ~= 0 then drawBox(sx, sy, T.coll + coll * 8, facingLeft, 0x4060E0) end
    if hub ~= 0 and hurtState < 0x80 then
      drawBox(sx, sy, T.hurt + hub * 16, facingLeft, 0x40C040)      -- body
      drawBox(sx, sy, T.hurt + hub * 16 + 8, facingLeft, 0xC0FF00)  -- head
    end
    if hb ~= 0 and step >= 1 then
      drawBox(sx, sy, T.hit + hb * 8, facingLeft, 0xE03028)
    end
  end

  local function draw()
    if not ctx.ui.hitboxes or not hud.show("boxes") then return end
    local s = ctx.snap
    if not s then return end
    hud.console()
    for i = 1, 2 do
      drawFor(C.BASE[i], s.p[i])
      if s.proj[i].alive then
        drawFor(C.PROJ[i], { char = s.p[i].char })
      end
    end
  end

  table.insert(ctx.hooks.draw, draw)
  table.insert(ctx.hooks.reset, function() bases = {} end)
end

return M
