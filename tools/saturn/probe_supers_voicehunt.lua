-- probe_supers_voicehunt.lua — where, if anywhere, does Super S say Saturn's
-- name? Logs EVERY voice the APU starts across the whole select -> confirm ->
-- versus -> match-start flow, with the BRR directory entry it came from, plus
-- every change to the directory itself.
--
-- Run it for two different characters and diff: any line that belongs to the
-- CHARACTER differs between the runs; menu blips and music do not. This is the
-- same SRCN-reading trick that identified the in-match voices, applied to the
-- one sound still missing (the select "Yoroshiku").
--
-- Already ruled out by the earlier probes:
--   * no per-character voice bank is resident at the select screen (directory
--     entries 28-34, the in-match voices, are all zero there);
--   * moving the cursor across the roster streams nothing in and plays only the
--     same handful of menu blips whatever character is highlighted.
--
-- usage: CHAR=10 ROM=<Super S> tools/run.sh \
--            tools/saturn/probe_supers_voicehunt.lua 900
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "10")
local CHAR2 = tonumber(os.getenv("CHAR2") or os.getenv("CHAR") or "10")
local TAG = os.getenv("TAG") or ("hunt" .. (os.getenv("CHAR") or "10"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/voicehunt_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local ARAM = emu.memType.spcRam
local DSP = emu.memType.spcDspRegisters
local function dsp(r) return emu.read(r, DSP) end

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local function dirent(e)
  local o = dsp(0x5D) * 0x100 + e * 4
  return emu.read(o, ARAM) + 256 * emu.read(o + 1, ARAM),
         emu.read(o + 2, ARAM) + 256 * emu.read(o + 3, ARAM)
end

local watching, phase = false, "?"
local prev, seen = {}, {}
for v = 0, 7 do prev[v] = -1 end
local lastdir = {}

emu.addEventCallback(function()
  if not watching then return end
  for v = 0, 7 do
    local s, e = dsp(v * 0x10 + 4), dsp(v * 0x10 + 8)
    if e > 0 and s ~= prev[v] then
      prev[v] = s
      local st, lp = dirent(s)
      -- log each distinct sample once per phase: repeats are music loops
      local key = phase .. "/" .. s
      if not seen[key] then
        seen[key] = true
        -- PITCH names the playback rate outright: DSP rate = 32000 * P / $1000,
        -- so this makes the render rate a measurement instead of an assumption
        local pit = emu.read(v * 0x10 + 2, DSP) + 256 * emu.read(v * 0x10 + 3, DSP)
        log(string.format(
          "  f%-5d [%s] voice %d  SRCN %3d  ARAM $%04X..$%04X (%d bytes)  PITCH $%04X = %d Hz",
          frames, phase, v, s, st, lp, lp - st, pit, math.floor(32000 * pit / 0x1000)))
      end
    end
  end
  -- directory churn (a streamed-in sample shows here)
  local base = dsp(0x5D) * 0x100
  for e = 0, 47 do
    local o = base + e * 4
    local w = emu.read(o, ARAM) + 256 * emu.read(o + 1, ARAM)
    if lastdir[e] ~= nil and lastdir[e] ~= w then
      log(string.format("  f%-5d [%s] DIRECTORY entry %d start $%04X -> $%04X",
        frames, phase, e, lastdir[e], w))
    end
    lastdir[e] = w
  end
end, emu.eventType.endFrame)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function()
    if sf > 240 then
      watching = true; phase = "select"
      log(string.format("=== Super S, P1 = %d — voice hunt ===", CHAR))
      log(string.format("DIR page $%02X", dsp(0x5D)))
      return true
    end
    return false
  end,
  -- entry 16 is a SHARED streamed slot: each confirmed character's line is
  -- uploaded there, played, and then overwritten by the next one. Selecting the
  -- same character on both sides is the simplest way to make the slot's final
  -- contents unambiguously hers.
  function() wr(0x1B40, CHAR); wr(0x1B80, CHAR2); return sf > 30 end,
  function()
    if sf == 1 then phase = "confirm-p1" end
    pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 120
  end,
  function() pulse[0] = {}; return sf > 60 end,
  function()
    if sf == 1 then phase = "confirm-p2" end
    pulse[1] = beat({ a = true }); return sf > 90
  end,
  function()
    if sf == 1 then phase = "versus" end
    -- dump ARAM once the selection voice has been uploaded: entry 16 at $4D00
    -- is the per-character slot, and this is the only window where it is both
    -- loaded and not yet displaced by the match's own banks
    if sf == 200 then
      local st, lp = dirent(16)
      log(string.format("  ARAM DUMP at f%d: entry 16 = $%04X..$%04X (%d bytes)",
        frames, st, lp, lp - st))
      local f = assert(io.open(ENV.TRACE .. "saturn/aram_versus_" .. TAG .. ".bin", "wb"))
      local t = {}
      for a = 0, 0xFFFF do t[#t + 1] = string.char(emu.read(a, ARAM)) end
      f:write(table.concat(t)); f:close()
    end
    return sf > 300
  end,
  function()
    if sf == 1 then phase = "load" end
    pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
    return (ram(0x1000) ~= 0 and ram(0x1080) ~= 0) or sf > 600
  end,
  function() if sf == 1 then phase = "match" end; return sf > 420 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("final: P1 id $%02X, P2 id $%02X", ram(0x1000), ram(0x1080)))
    log("done"); emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_supers_voicehunt loaded")
