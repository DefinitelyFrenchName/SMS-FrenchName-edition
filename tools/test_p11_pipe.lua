-- test_p11_pipe.lua (patch 11): pipe-stage validation on the PATCHED ROM.
-- Loads traces/training_p11.mss: expects the ROM to draw "TRAINING" on BG3 row 9
-- (checks VRAM words + $7F state + TM force) and screenshots for the eyeball check.
-- Then Start (movelist) -> visible must drop; Start again -> must come back.
-- Output: traces/p11_pipe.txt (+ p11_pipe.png / p11_pipe_movelist.png)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p11_pipe.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end
local function vword(w) return emu.read(w * 2, emu.memType.snesVideoRam) + 256 * emu.read(w * 2 + 1, emu.memType.snesVideoRam) end
local function st7f(off) return emu.read(0x1F000 + off, emu.memType.snesWorkRam) end
local fails = 0
local function check(name, ok, detail)
  log((ok and "PASS " or "FAIL ") .. name .. (detail and (" " .. detail) or ""))
  if not ok then fails = fails + 1 end
end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

-- expected row words: TRAINING with shared font (tile0=0xC7, order GCREVSALPUNIHMTY+BDFJKOW>#)
local ORDER = "GCREVSALPUNIHMTYBDFJKOW"
local function tileOf(c)
  local i = ORDER:find(c, 1, true)
  return 0x2C00 + 0xC7 + (i - 1)
end
local EXPECT = {}
for i = 1, 8 do EXPECT[i] = tileOf(("TRAINING"):sub(i, i)) end

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    check("visible", st7f(2) == 1, string.format("vis=%02X", st7f(2)))
    check("fontup", st7f(1) == 1, string.format("fu=%02X", st7f(1)))
    local ok, got = true, ""
    for i = 1, 8 do
      local w = vword(0x1124 + i - 1)
      got = got .. string.format(" %04X", w)
      if w ~= EXPECT[i] then ok = false end
    end
    check("rowwords", ok, got)
    check("tm", emu.getState()["ppu.mainScreenLayers"] == 0x17,
      string.format("tm=%02X", emu.getState()["ppu.mainScreenLayers"]))
    -- glyph CHR uploaded? T = tile 0xC7+14 -> byte 0xA000+(0xC7+14)*16
    local nz = false
    for i = 0, 15 do if emu.read(0xA000 + (0xC7 + 14) * 16 + i, emu.memType.snesVideoRam) ~= 0 then nz = true end end
    check("chrT", nz)
    local f = io.open(TRACE .. "p11_pipe.png", "wb")
    if not f then print("test_p11_pipe.lua: cannot open " .. (TRACE .. "p11_pipe.png")) emu.stop(1) return end
    f:write(emu.takeScreenshot()); f:close()
  end
  if t >= 80 and t <= 82 then pulse[0] = { start = true } end
  if t == 83 then pulse[0] = nil end
  if t == 140 then
    check("movelist-visdrop", st7f(2) == 0, string.format("vis=%02X f01FA=%02X", st7f(2), ram(0x1FA)))
    check("movelist-rowblank", vword(0x1124) == 0x2000, string.format("w=%04X", vword(0x1124)))
    local f = io.open(TRACE .. "p11_pipe_movelist.png", "wb")
    if not f then print("test_p11_pipe.lua: cannot open " .. (TRACE .. "p11_pipe_movelist.png")) emu.stop(1) return end
    f:write(emu.takeScreenshot()); f:close()
  end
  if t >= 160 and t <= 162 then pulse[0] = { start = true } end
  if t == 163 then pulse[0] = nil end
  if t == 240 then
    check("back-visible", st7f(2) == 1, string.format("vis=%02X", st7f(2)))
    check("back-row", vword(0x1124) == EXPECT[1], string.format("w=%04X want %04X", vword(0x1124), EXPECT[1]))
    log(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
    emu.stop(fails == 0 and 0 or 1)
  end
end, emu.eventType.endFrame)

print("test_p11_pipe loaded")
