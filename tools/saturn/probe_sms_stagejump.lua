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
-- usage: CHAR=8 ROM=build/saturn/<rom> tools/run.sh \
--            tools/saturn/probe_sms_stagejump.lua 500
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "8")
local CHAR2 = tonumber(os.getenv("CHAR2") or "4")
local TAG = os.getenv("TAG") or ("jump" .. (os.getenv("CHAR") or "8"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/stagejump_" .. TAG .. ".txt", "w"))
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

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local watching, shots = false, 0
local basey

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
  function() return sf > 240 end,
  function()
    pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
    return ram(0x1000) == CHAR or sf > 600
  end,
  -- wait for the round to be actually RUNNING ($01FA == $80), not just loaded;
  -- during the intro the pads are ignored, which is why earlier attempts never
  -- got a jump
  -- and wait for NEUTRAL: $01FA == $80 only means the round is live, while the
  -- fighters may still be in their entrance (act $22). Pads are ignored there,
  -- which is why no earlier attempt ever produced a jump.
  function() return ram(0x01FA) == 0x80 and ram(0x1001) == 0x00 and sf > 30 end,
  function()
    if sf == 1 then
      watching = true
      log(string.format("=== running: P1 char %d, $01FA=$%02X, scene $%02X ===",
        ram(0x1000), ram(0x01FA), ram(0x008E)))
      log("  frame act | +21..+28 (x/y candidates)      | BG1 h,v  BG2 h,v  BG3 h,v  BG4 h,v")
    end
    -- The "GO!" banner is still up for a while after $01FA turns $80 and the act
    -- reaches neutral, and the pads do nothing until it clears — so wait well
    -- past it before trying to jump.
    if sf >= 120 and sf <= 150 then pulse[0] = { up = true } else pulse[0] = {} end
    if sf >= 110 and sf <= 200 then
      local sc = sc4()
      local st = {}
      for i = 0x21, 0x28 do st[#st + 1] = string.format("%02X", ram(0x1000 + i)) end
      -- also log what the GAME sees on the pad: $4218/9 is the autopoll result
      -- and $5C-$5F the engine's own held words, so a jump that never happens
      -- can be told apart from an input that never arrived
      local pad = emu.read(0x804218, MEM) + 256 * emu.read(0x804219, MEM)
      log(string.format("  %4d %02X  | %s | %4d,%-4d %4d,%-4d %4d,%-4d %4d,%-4d | pad %04X held %02X%02X",
        sf, ram(0x1001), table.concat(st, " "),
        sc[0].h, sc[0].v, sc[1].h, sc[1].v, sc[2].h, sc[2].v, sc[3].h, sc[3].v,
        pad, ram(0x005D), ram(0x005C)))
    end
    if (sf == 118 or sf == 132 or sf == 145 or sf == 175) and shots < 4 then
      shots = shots + 1
      local f = io.open(ENV.TRACE .. "saturn/stagejump_" .. TAG .. "_" .. sf .. ".png", "wb")
      f:write(emu.takeScreenshot()); f:close()
    end
    return sf > 205
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log("done"); emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_stagejump loaded")
