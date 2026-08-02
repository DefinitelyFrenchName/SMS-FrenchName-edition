-- probe_sms_selectvoice.lua — how does SMS say a character's line when you
-- pick her at the select screen? (Delivery path for Saturn's "Yoroshiku".)
--
-- The maintainer confirms every sailor has her own spoken sentence at character
-- select. A first pass showed the voice plays from **SRCN 48** — which is char
-- 1's directory entry 0, i.e. a FIXED entry pointing at ARAM $B700 — with the
-- same boundaries whichever character is chosen. So the per-character part
-- cannot be the directory; it has to be what gets UPLOADED to $B700 first.
--
-- This watches both halves at once: every call into the two audio-bank loaders
-- ($C0:EB4B verbatim, $C0:EC5E relocating) with the table id in A, and every
-- DSP voice start with its SRCN, pitch and directory entry. Then it dumps ARAM
-- so the resident bank can be matched back to a ROM source.
--
-- Run for two characters and diff: whatever differs is the delivery mechanism,
-- and that is what Saturn needs to borrow.
--
-- usage: CHAR=6 ROM=<sms rom> tools/run.sh \
--            tools/saturn/probe_sms_selectvoice.lua 600
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "6")
local TAG = os.getenv("TAG") or ("sel" .. (os.getenv("CHAR") or "6"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/smsselect_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local ARAM = emu.memType.spcRam
local DSP = emu.memType.spcDspRegisters
local MEM = emu.memType.snesMemory
local function dsp(r) return emu.read(r, DSP) end

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local phase = "boot"

-- (a) every audio-bank load, with the table id
for _, spec in ipairs({ { 0xEB4B, "EB4B" }, { 0xEC5E, "EC5E" } }) do
  for _, bank in ipairs({ 0x000000, 0x800000, 0xC00000 }) do
    local a = bank + spec[1]
    emu.addMemoryCallback(function()
      local ok, s = pcall(emu.getState)
      local A = (ok and s and s["cpu.a"]) or 0
      local off = emu.read(0x7E0010, MEM) + 256 * emu.read(0x7E0011, MEM)
      log(string.format("  f%-5d [%s] LOAD %s  table id %d  dp$10=$%04X",
        frames, phase, spec[2], A & 0xFF, off))
    end, emu.callbackType.exec, a, a, emu.cpuType.snes, MEM)
  end
end

-- (b) every voice start
local prev = {}
for v = 0, 7 do prev[v] = -1 end
local dumped = false
emu.addEventCallback(function()
  if phase == "boot" then return end
  local base = dsp(0x5D) * 0x100
  for v = 0, 7 do
    local s, e = dsp(v * 0x10 + 4), dsp(v * 0x10 + 8)
    if e > 0 and s ~= prev[v] then
      prev[v] = s
      local o = base + s * 4
      local st = emu.read(o, ARAM) + 256 * emu.read(o + 1, ARAM)
      local lp = emu.read(o + 2, ARAM) + 256 * emu.read(o + 3, ARAM)
      local pit = emu.read(v * 0x10 + 2, DSP) + 256 * emu.read(v * 0x10 + 3, DSP)
      log(string.format("  f%-5d [%s] voice %d SRCN %3d  $%04X..$%04X (%d B)  %d Hz",
        frames, phase, v, s, st, lp, lp - st, math.floor(32000 * pit / 0x1000)))
      -- the moment the select line starts, freeze a copy of ARAM
      if s == 48 and phase:find("confirm") and not dumped then
        dumped = true
        local f = assert(io.open(ENV.TRACE .. "saturn/aram_smssel_" .. TAG .. ".bin", "wb"))
        local t = {}
        for a = 0, 0xFFFF do t[#t + 1] = string.char(emu.read(a, ARAM)) end
        f:write(table.concat(t)); f:close()
        log(string.format("  f%-5d ARAM dumped while the select line is playing", frames))
      end
    end
  end
end, emu.eventType.endFrame)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function()
    if sf > 240 then
      phase = "select"
      log(string.format("=== SMS select, P1 = %d (DIR page $%02X) ===", CHAR, dsp(0x5D)))
      return true
    end
    return false
  end,
  function() wr(0x1B40, CHAR); wr(0x1B80, CHAR); return sf > 30 end,
  function()
    if sf == 1 then phase = "confirm-p1" end
    pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 120
  end,
  function() pulse[0] = {}; return sf > 90 end,
  function()
    if sf == 1 then phase = "confirm-p2" end
    pulse[1] = beat({ a = true }); return sf > 150
  end,
  function() if sf == 1 then phase = "post" end; return sf > 240 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 4000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_selectvoice loaded")
