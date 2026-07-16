-- ds_clash.lua: Neptune mirror. Both players throw Deep Submerge (214LP) at once; the two
-- fireballs travel toward centre and CLASH (projectile-vs-projectile branch $C0:C395 tests
-- both hit boxes). Logs both projectile slots + draws both live hit boxes (yellow, on the
-- balls thanks to patch 9), screenshots the clash. P1 faces right (214 = down,down-left,left);
-- P2 faces left (down,down-right,right). P2X pokes P2 closer so the balls meet.
-- GUI use: open the v0.7_all5_neptuneds build, load traces/neptune_vs_neptune.mss, run this.
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
STATE = STATE or "neptune_vs_neptune.mss"
OUT   = OUT or "ds_clash.txt"
P2X   = P2X or 0xF0        -- bring P2 to x=240 (~112px apart) so the two balls overlap
DRAW  = (DRAW ~= false)
local WRAM = emu.memType.snesWorkRam
local BUS  = emu.memType.snesMemory
local loaded, t = false, -1
local function w8(a) return emu.read(a, WRAM) end
local function b8(a) return emu.read(a, BUS) end
local function b16(a) return b8(a) + 256 * b8(a + 1) end
local function sgn(v) return v > 127 and v - 256 or v end
local log = io.open(TRACE .. OUT, "w")
local PT_HIT = 0x8AC1F1

local P1 = { [8]={down=true},[11]={down=true,left=true},[14]={left=true,y=true},[17]={} }
local P2 = { [8]={down=true},[11]={down=true,right=true},[14]={right=true,y=true},[17]={} }
local c1, a1, c2, a2 = {}, -1, {}, -1

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(TRACE .. STATE, "rb"); local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss); loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t >= 0 then
    for k, v in pairs(P1) do if k <= t and k > a1 then c1 = v; a1 = k end end
    for k, v in pairs(P2) do if k <= t and k > a2 then c2 = v; a2 = k end end
  end
  local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
  local i1 = {}; for k, v in pairs(base) do i1[k] = v end; for k, v in pairs(c1) do i1[k] = v end
  local i2 = {}; for k, v in pairs(base) do i2[k] = v end; for k, v in pairs(c2) do i2[k] = v end
  emu.setInput(i2, 0, 1); emu.setInput(i1, 0, 0)
end, emu.eventType.inputPolled)

local function drawProj(pbase)
  local pid = w8(pbase)
  if pid == 0 or pid >= 0x80 then return end
  local hb = w8(pbase + 0x40)
  if hb == 0 then return end
  local ox = w8(pbase + 0x21) + 256 * w8(pbase + 0x22)
  local oy = w8(pbase + 0x25) + 256 * w8(pbase + 0x26)
  local camx = w8(0x0A00) + 256 * w8(0x0A01)
  local camy = w8(0x0A02) + 256 * w8(0x0A03)
  local sx, sy = ox - camx, oy - camy
  local facingL = w8(pbase + 0x09) ~= 0
  local tbl = 0x8A0000 + b16(PT_HIT + pid * 2)
  local e = tbl + hb * 8
  local xo, wid
  if facingL then xo, wid = sgn(b8(e + 2)), b8(e + 3) else xo, wid = sgn(b8(e)), b8(e + 1) end
  local yo, h = sgn(b8(e + 4)), b8(e + 5)
  pcall(emu.selectDrawSurface, emu.drawSurface.consoleScreen)
  emu.drawLine(sx - 8, sy, sx + 8, sy, 0x00FFFF)
  if wid ~= 0 and h ~= 0 then
    emu.drawRectangle(sx + xo, sy + yo, wid, h, 0x80FF3030, true)
    emu.drawRectangle(sx + xo, sy + yo, wid, h, 0xFFF030, false)
  end
end

local shots = {}
local clashShot = false

emu.addEventCallback(function()
  if t < 0 then return end
  if P2X and t == 1 then emu.write(0x10A1, P2X, WRAM) end   -- bring P2 closer so the balls meet
  local a1v = w8(0x1100); local al1 = a1v ~= 0 and a1v < 0x80
  local a2v = w8(0x1180); local al2 = a2v ~= 0 and a2v < 0x80
  if DRAW then drawProj(0x1100); drawProj(0x1180) end
  if t <= 70 then
    log:write(string.format("t=%03d  P1proj[%s id=%02X X=%04X Y=%04X hb=%02X]  P2proj[%s id=%02X X=%04X Y=%04X hb=%02X]\n",
      t, al1 and "LIVE" or "----", a1v, w8(0x1121)+256*w8(0x1122), w8(0x1125)+256*w8(0x1126), w8(0x1140),
         al2 and "LIVE" or "----", a2v, w8(0x11A1)+256*w8(0x11A2), w8(0x11A5)+256*w8(0x11A6), w8(0x11C0)))
  end
  -- screenshot the moment both are live and close (the clash), and a couple around it
  if al1 and al2 and not clashShot then
    local dx = math.abs((w8(0x1121)+256*w8(0x1122)) - (w8(0x11A1)+256*w8(0x11A2)))
    if dx < 24 then
      local f = io.open(TRACE .. "ds_clash_" .. t .. ".png", "wb"); if f then f:write(emu.takeScreenshot()); f:close() end
    end
  end
  if t == 70 then log:close(); emu.stop(0) end
  t = t + 1
end, emu.eventType.endFrame)

print("ds_clash loaded")
