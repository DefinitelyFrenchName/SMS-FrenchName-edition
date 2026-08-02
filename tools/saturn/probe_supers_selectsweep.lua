-- probe_supers_selectsweep.lua — walk Super S's character-select cursor across
-- the roster and watch the APU, hunting Saturn's select voice ("Yoroshiku").
--
-- probe_supers_selectvoice.lua showed that poking $1B40 changes nothing about
-- what the select screen plays, and that NO per-character voice bank is resident
-- there (directory entries 28-34, the in-match voices, are all zero). So either
-- a character's select line is streamed in when the cursor reaches them, or it
-- is not a select-screen sound at all.
--
-- This moves the cursor for real and, at every stop, records: the select-screen
-- variables (to find which one is the cursor), any DSP voice that starts and the
-- directory entry it plays from, and which directory entries CHANGED since the
-- last stop (a streamed-in sample shows up as exactly that).
--
-- usage: DIR=right STEPS=12 ROM=<Super S> tools/run.sh \
--            tools/saturn/probe_supers_selectsweep.lua 600
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local NSTOPS = tonumber(os.getenv("STEPS") or "12")
local MOVE = os.getenv("DIR") or "right"
local TAG = os.getenv("TAG") or "sweep"
local LOG = assert(io.open(ENV.TRACE .. "saturn/selectsweep_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram
local ARAM = emu.memType.spcRam
local DSP = emu.memType.spcDspRegisters
local function dsp(r) return emu.read(r, DSP) end

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local function readdir()
  local d, base = {}, dsp(0x5D) * 0x100
  for e = 0, 63 do
    local o = base + e * 4
    d[e] = { emu.read(o, ARAM) + 256 * emu.read(o + 1, ARAM),
             emu.read(o + 2, ARAM) + 256 * emu.read(o + 3, ARAM) }
  end
  return d
end

local watching, lastdir = false, nil
local prev = {}
for v = 0, 7 do prev[v] = -1 end
local pending = {}

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function()
    if sf > 240 then
      watching = true; lastdir = readdir()
      log(string.format("=== Super S select reached at f%d, DIR page $%02X ===",
        frames, dsp(0x5D)))
      log("stop  $1B40 $1B42 $1B80 $008D $0070 | voices started | directory entries changed")
      return true
    end
    return false
  end,
}

for i = 1, NSTOPS do
  STEPS[#STEPS + 1] = function()
    if sf <= 3 then pulse[0] = { [MOVE] = true } else pulse[0] = {} end
    if sf < 70 then return false end
    local d = readdir()
    local changed = {}
    for e = 0, 63 do
      if d[e][1] ~= lastdir[e][1] or d[e][2] ~= lastdir[e][2] then
        changed[#changed + 1] = string.format("%d:$%04X+%d", e, d[e][1], d[e][2] - d[e][1])
      end
    end
    lastdir = d
    local vs = {}
    for _, p in ipairs(pending) do vs[#vs + 1] = p end
    pending = {}
    log(string.format(" %2d   $%02X   $%02X   $%02X   $%02X   $%02X | %-28s | %s",
      i, ram(0x1B40), ram(0x1B42), ram(0x1B80), ram(0x008D), ram(0x0070),
      #vs > 0 and table.concat(vs, " ") or "-",
      #changed > 0 and table.concat(changed, " ") or "-"))
    return true
  end
end

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if watching then
    for v = 0, 7 do
      local s, e = dsp(v * 0x10 + 4), dsp(v * 0x10 + 8)
      if e > 0 and s ~= prev[v] then
        pending[#pending + 1] = string.format("v%d/SRCN%d", v, s)
        prev[v] = s
      end
    end
  end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    local f = assert(io.open(ENV.TRACE .. "saturn/aram_sweep_" .. TAG .. ".bin", "wb"))
    local t = {}
    for a = 0, 0xFFFF do t[#t + 1] = string.char(emu.read(a, ARAM)) end
    f:write(table.concat(t)); f:close()
    log("ARAM dumped; done")
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_supers_selectsweep loaded")
