-- ds_overlay.lua: draw Neptune's Deep Submerge fireball HITBOX (from its own object
-- box table $8A:FD51, resolved via the projectile's +0x00) plus an origin crosshair on
-- the console surface, and screenshot across the descent. Lets us SEE box-vs-sprite.
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
STATE = STATE or "neptune_vs_jupiter.mss"
BTN   = BTN or "y"
local BUS  = emu.memType.snesMemory
local WRAM = emu.memType.snesWorkRam
local loaded, t = false, -1
local function w8(a) return emu.read(a, WRAM) end
local function b8(a) return emu.read(a, BUS) end
local function b16(a) return b8(a) + 256 * b8(a + 1) end
local function sgn(v) return v > 127 and v - 256 or v end
local PT_HIT = 0x8AC1F1

local PLAN = { [8]={down=true},[11]={down=true,left=true},[14]={left=true,[BTN]=true},[17]={} }
local cur, applied = {}, -1

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(TRACE .. STATE, "rb"); local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss); loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t >= 0 then for k, v in pairs(PLAN) do if k <= t and k > applied then cur = v; applied = k end end end
  local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
  local in1 = {}; for k, v in pairs(base) do in1[k] = v end
  for k, v in pairs(cur) do in1[k] = v end
  emu.setInput(in1, 0, 0)
end, emu.eventType.inputPolled)

local shots = { [30]=1,[36]=1,[42]=1,[45]=1,[48]=1 }

local function draw()
  local pid = w8(0x1100)
  if pid == 0 or pid >= 0x80 then return end
  local hb = w8(0x1140)
  local ox = w8(0x1121) + 256 * w8(0x1122)
  local oy = w8(0x1125) + 256 * w8(0x1126)
  local camx = w8(0x0A00) + 256 * w8(0x0A01)
  local camy = w8(0x0A02) + 256 * w8(0x0A03)
  local facingL = w8(0x1109) ~= 0
  local sx, sy = ox - camx, oy - camy
  pcall(emu.selectDrawSurface, emu.drawSurface.consoleScreen)
  -- origin reference: magenta full-width line at origin-Y; green brackets at +/-11
  emu.drawLine(0, sy, 255, sy, 0xFF00FF)
  emu.drawLine(0, sy - 11, 255, sy - 11, 0x40FF40)
  emu.drawLine(0, sy + 11, 255, sy + 11, 0x40FF40)
  emu.drawLine(sx, sy - 14, sx, sy + 14, 0xFF00FF)
  -- hit box (red, filled) from the projectile's OWN object table
  if hb ~= 0 then
    local tbl = 0x8A0000 + b16(PT_HIT + pid * 2)
    local e = tbl + hb * 8
    local xo, wid
    if facingL then xo, wid = sgn(b8(e + 2)), b8(e + 3) else xo, wid = sgn(b8(e)), b8(e + 1) end
    local yo, h = sgn(b8(e + 4)), b8(e + 5)
    if wid ~= 0 and h ~= 0 then
      emu.drawRectangle(sx + xo, sy + yo, wid, h, 0x80FF3030, true)
      emu.drawRectangle(sx + xo, sy + yo, wid, h, 0xFF3030, false)
    end
  end
end

emu.addEventCallback(function()
  if t < 0 then return end
  if w8(0x1100) ~= 0 and w8(0x1100) < 0x80 then draw() end
  if shots[t] then
    local f = io.open(TRACE .. "ds_ov_" .. BTN .. "_" .. t .. ".png", "wb")
    if f then f:write(emu.takeScreenshot()); f:close() end
  end
  if t > 60 then emu.stop(0) end
  t = t + 1
end, emu.eventType.endFrame)

print("ds_overlay loaded")
