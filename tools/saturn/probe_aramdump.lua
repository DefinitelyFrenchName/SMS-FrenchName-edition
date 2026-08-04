-- probe_aramdump.lua — dump the APU's 64 KB ARAM once Saturn is in a match, so
-- her voice samples can be decoded to WAV (tools/saturn/brr.py) and pitched by
-- ear. That ear test is what originally established ~8 kHz (sound_scope.md
-- "Playback rate: RESOLVED"), and it is the way to settle the 2026-08-04 field
-- report that her voices sound sharp.
--
--   SHELL_ID=6 ROM=<saturn build> tools/run.sh tools/saturn/probe_aramdump.lua 500
-- writes traces/saturn/aram_<shell>.bin
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
local LOG = assert(io.open(ENV.TRACE .. "saturn/aramdump.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local function beat(on) return (frames % 7) < 3 and on or {} end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if p == 0 and hold then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() wr(0x1B40, SHELL); wr(0x1B80, 4); hold = true; return sf > 20 end,
  function() wr(0x1B40, SHELL); wr(0x1B80, 4)
             pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    wr(0x1B40, SHELL); wr(0x1B80, 4)
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 200 end,
  function()
    local out = {}
    for a = 0, 0xFFFF do out[#out + 1] = string.char(emu.read(a, emu.memType.spcRam) or 0) end
    local f = assert(io.open(ENV.TRACE .. "saturn/aram_" .. SHELL .. ".bin", "wb"))
    f:write(table.concat(out)); f:close()
    log(string.format("dumped 64 KB ARAM (p1 id=%02X, shell %d)", ram(0x1000), SHELL))
    -- the BRR directory, so sample starts can be resolved without guessing
    local dirp = (emu.read(0x5D, emu.memType.spcDspRegisters) or 0) * 0x100
    log(string.format("DSP DIR = $%04X", dirp))
    for e = 48, 55 do
      local o = dirp + e * 4
      local st = (emu.read(o, emu.memType.spcRam) or 0) | ((emu.read(o + 1, emu.memType.spcRam) or 0) << 8)
      local lp = (emu.read(o + 2, emu.memType.spcRam) or 0) | ((emu.read(o + 3, emu.memType.spcRam) or 0) << 8)
      log(string.format("  entry %02d: start $%04X loop $%04X", e, st, lp))
    end
    return true
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then emu.stop(0) end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_aramdump loaded: shell " .. SHELL)
