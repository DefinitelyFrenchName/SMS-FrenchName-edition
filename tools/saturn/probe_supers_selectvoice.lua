-- probe_supers_selectvoice.lua — find Saturn's character-select voice
-- ("Yoroshiku") in Super S, task #44 follow-up.
--
-- It is NOT in the per-character voice bank: the maintainer confirmed it is
-- absent from all seven of her in-match samples, so it lives in whatever sample
-- set the SELECT screen loads. Rather than hunt memory by hand, this uses the
-- trick that settled the in-match ids: the DSP's SRCN register names the BRR
-- directory entry a voice is playing from, so we just watch every voice across
-- the select and read off which entry starts.
--
-- Run it twice with different CHAR values and diff: the entry that changes with
-- the character IS the select voice. Everything else is menu blips and music.
--
-- The log also carries what is needed to extract it: the DSP DIR page, and the
-- directory entry's start/end, which map linearly into ROM (Super S uploads
-- samples uncompressed, so a byte search finds the source — see
-- docs/saturn/sound_scope.md Phase 2).
--
-- usage: CHAR=10 ROM=<Super S> tools/run.sh \
--            tools/saturn/probe_supers_selectvoice.lua 400
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "10")
local TAG = os.getenv("TAG") or ("char" .. (os.getenv("CHAR") or "10"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/selectvoice_" .. TAG .. ".txt", "w"))
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

local watching, starts = false, {}
local prev = {}
for v = 0, 7 do prev[v] = -1 end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function()
    if sf == 1 then
      watching = true
      log(string.format("=== Super S char select, P1 = %d ===", CHAR))
      log(string.format("DSP DIR page = $%02X (directory base ARAM $%02X00)",
        dsp(0x5D), dsp(0x5D)))
    end
    wr(0x1B40, CHAR); wr(0x1B80, 6)
    return sf > 60
  end,
  function()  -- confirm P1: the select voice should fire around here
    if sf == 1 then log(string.format("--- confirm P1 at f%d ---", frames)) end
    pulse[0] = beat({ a = true })
    return ram(0x1B42) == 1 or sf > 120
  end,
  function() pulse[0] = {}; return sf > 180 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if watching then
    for v = 0, 7 do
      local s, e = dsp(v * 0x10 + 4), dsp(v * 0x10 + 8)
      if e > 0 and s ~= prev[v] then
        starts[#starts + 1] = { f = frames, v = v, srcn = s }
        log(string.format("  f%-5d voice %d -> SRCN %3d", frames, v, s))
        prev[v] = s
      end
    end
  end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log("--- directory entries for every SRCN seen ---")
    local seen, dir = {}, dsp(0x5D) * 0x100
    for _, s in ipairs(starts) do
      if not seen[s.srcn] then
        seen[s.srcn] = true
        local a = dir + s.srcn * 4
        local st = emu.read(a, ARAM) + 256 * emu.read(a + 1, ARAM)
        local lp = emu.read(a + 2, ARAM) + 256 * emu.read(a + 3, ARAM)
        log(string.format("  SRCN %3d  start $%04X  loop $%04X", s.srcn, st, lp))
      end
    end
    local f = assert(io.open(ENV.TRACE .. "saturn/aram_select_" .. TAG .. ".bin", "wb"))
    local t = {}
    for a = 0, 0xFFFF do t[#t + 1] = string.char(emu.read(a, ARAM)) end
    f:write(table.concat(t)); f:close()
    log("ARAM dumped to traces/saturn/aram_select_" .. TAG .. ".bin")
    log("done")
    emu.stop(0)
  end
  if frames > 4000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_supers_selectvoice loaded")
