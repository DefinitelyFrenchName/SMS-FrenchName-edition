-- probe_sms_stagejump.lua — reproduce and MEASURE the ported stage's vertical
-- slide (task #43).
--
-- Field report: on the ported stage only, during a jump the shadows and the
-- opponent slide toward the bottom of the screen and return on landing. Two
-- earlier probe attempts never got the character to jump at all (p1y never left
-- $00C0), so nothing about the vertical behaviour has ever been measured — the
-- first job is simply to make a jump happen and watch.
--
-- Logs, per frame across a jump: P1's Y, and all four BG layers' scroll
-- registers (write-only, so they are shadowed from writes). Run it on the stage
-- build and on a vanilla stage and diff: whatever tracks the camera on one and
-- not the other is the fault.
--
-- STAGE forces the scene id at $7E:008E just before the loader reads it
-- ($C0:8586), which is the documented way to summon a specific stage — stage
-- choice is NOT simply P1's character, and the first run of this probe measured
-- scene $00 while believing it had the ported one. STAGE=2 = Pluto's slot = the
-- ported stage on a stage build. The header line records the scene actually
-- loaded; check it before trusting anything below.
--
-- Also logs each layer's TILEMAP ADDRESS, because the question for #43 is which
-- PLANE holds the ground after the port's re-cut, not merely that some plane
-- fails to track.
--
-- usage: STAGE=2 CHAR=8 ROM=build/saturn/<rom> tools/run.sh \
--            tools/saturn/probe_sms_stagejump.lua 500
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "8")
local CHAR2 = tonumber(os.getenv("CHAR2") or "4")
local STAGE = tonumber(os.getenv("STAGE") or "") -- nil = whatever the game picks
local WALK = os.getenv("WALK") == "1"
local TAG = os.getenv("TAG") or ("jump" .. (os.getenv("CHAR") or "8"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/stagejump_" .. TAG .. ".txt", "w"))
local oamseq = assert(io.open(ENV.TRACE .. "saturn/stagejump_" .. TAG .. "_oamseq.bin", "wb"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local MEM = emu.memType.snesMemory

-- Mesen exposes the PPU's own scroll values, which is far better than shadowing
-- the write-only registers: an earlier version tracked $210D-$2114 writes and
-- captured nothing at all.
local function scrolls()
  local ok, s = pcall(emu.getState)
  if not ok or not s then return {} end
  local t = {}
  -- emu.getState() returns a FLAT table with dotted string keys, not nested
  -- tables: the fields are "ppu.layers[0].hscroll" and friends
  for i = 0, 3 do
    t[i] = { h = s[string.format("ppu.layers[%d].hscroll", i)] or -1,
             v = s[string.format("ppu.layers[%d].vscroll", i)] or -1 }
  end
  return t
end
local function sc4()
  local ok, t = pcall(scrolls)
  if not ok or not t or not t[0] then
    return { [0] = { h = -1, v = -1 }, [1] = { h = -1, v = -1 },
             [2] = { h = -1, v = -1 }, [3] = { h = -1, v = -1 } }
  end
  return t
end

-- which VRAM tilemap/CHR each BG plane is pointed at (the port SWAPs the two
-- stage maps between planes, so "BG1" alone does not say which art moved)
local function bases()
  local ok, s = pcall(emu.getState)
  if not ok or not s then return "?" end
  local t = {}
  for i = 0, 3 do
    t[#t + 1] = string.format("BG%d map=%04X chr=%04X", i + 1,
      s[string.format("ppu.layers[%d].tilemapAddress", i)] or 0xFFFF,
      s[string.format("ppu.layers[%d].chrAddress", i)] or 0xFFFF)
  end
  return table.concat(t, "  ")
end

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local watching, shots = false, 0
local basey
local forced = 0

-- Force the scene id every time the loader is about to read it. The write must
-- happen at $C0:8586 (the instruction before the read at $858C) — poking $8E
-- earlier is useless, the scene is re-derived per load.
if STAGE then
  emu.addMemoryCallback(function()
    forced = forced + 1
    wr(0x8E, STAGE * 2)
  end, emu.callbackType.exec, 0x808586, 0x808586, emu.cpuType.snes, emu.memType.snesMemory)
end

-- $7E:008F is the per-stage sprite-attribute byte: 0x18 on the nine stages that
-- draw the fighters at OBJ priority 3, 0x10 on stage 2 (the slot the port
-- targets) which draws them at 2. It is mirrored into each player's +0x08.
-- Log who writes it, so the port can set it like every other stage.
local sf8 = 0
for _, a in ipairs({ 0x00008F, 0x7E008F }) do
  emu.addMemoryCallback(function(_ad, value)
    if frames < 1200 or sf8 > 8 then return end
    sf8 = sf8 + 1
    local ok, st = pcall(emu.getState)
    log(string.format("  $008F <= %02X @%02X:%04X A=%04X X=%04X Y=%04X",
      value or 0, ok and (st["cpu.k"] or 0) or 0, ok and (st["cpu.pc"] or 0) or 0,
      ok and (st["cpu.a"] or 0) or 0, ok and (st["cpu.x"] or 0) or 0, ok and (st["cpu.y"] or 0) or 0))
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function()
    emu.write(0x1B40, CHAR, emu.memType.snesWorkRam)
    emu.write(0x1B80, CHAR2, emu.memType.snesWorkRam)
    return sf > 20
  end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = beat({ a = true }); return sf > 60 end,
  -- the config screen appears during this wait and auto-advances on a timer,
  -- so the captures have to happen HERE, not after it
  function()
    if sf % 20 == 0 and sf <= 220 then
      local f = io.open(ENV.TRACE .. "saturn/stagename_" .. TAG .. "_cfg" .. sf .. ".png", "wb")
      f:write(emu.takeScreenshot()); f:close()
    end
    return sf > 240
  end,
  function()
    pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
    return ram(0x1000) == CHAR or sf > 600
  end,
  -- SIT on the button-config screen: the maintainer reports the STAGE NAME is
  -- printed at its bottom, which is the only place the game names a stage — and
  -- therefore where a ported stage has to be renamed ("Silver Millennium light").
  function()
    if sf % 3 == 0 and sf <= 60 then
      local f = io.open(ENV.TRACE .. "saturn/stagename_" .. TAG .. "_" .. sf .. ".png", "wb")
      f:write(emu.takeScreenshot()); f:close()
      local vb = {}
      for a = 0, 0xFFFF do vb[#vb + 1] = string.char(emu.read(a, emu.memType.snesVideoRam) or 0) end
      local vf = io.open(ENV.TRACE .. "saturn/stagename_" .. TAG .. "_vram" .. sf .. ".bin", "wb")
      vf:write(table.concat(vb)); vf:close()
    end
    return sf > 210
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_stagename loaded")
