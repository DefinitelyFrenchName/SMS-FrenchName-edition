-- probe_sms_voiceload.lua — how SMS loads a fighter's VOICE bank + its sample
-- directory (task #44 plumbing).
--
-- Static RE says:
--   P1: $C0:88D9  lda $1D00 / clc / adc #$1E / jsl $80:EB4B   (no relocation)
--   P2: $C0:8A2E  $10 = $2400 / lda $1D03 / adc #$1E / jsl $80:EC5E
--       ($C0:EC5E is the relocating uploader — it ADDS dp $10 to every block's
--        ARAM destination, which is how P2's bank reaches $DB00.)
--   directory: 32-byte per-character record at $E4:2CC4 + (charID-1)*32
--              (8 entries x [start16, loop16]; 0-3 = $B700 set, 4-7 = +$2400)
--
-- This probe checks all of that on real hardware behaviour: it drives a VS
-- match with configurable characters and logs
--   (a) every exec of the two loader entry points, with A (= bank id) and dp $10
--   (b) every PRG-ROM read inside the directory table, with the reading PC
--   (c) a mid-match dump of ARAM $3400-$35FF, to see the directory as uploaded.
--
-- usage: CHARA=6 CHAR2=9 TAG=ura_chibi ROM=<rom> tools/run.sh \
--            tools/saturn/probe_sms_voiceload.lua 400
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHARA = tonumber(os.getenv("CHARA") or "6")
local CHAR2 = tonumber(os.getenv("CHAR2") or "9")
local TAG = os.getenv("TAG") or "x"
local LOG = assert(io.open(ENV.TRACE .. "saturn/voiceload_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = PL.pad(pulse[p])
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local function st()
  local ok, s = pcall(emu.getState)
  if not ok or not s then return 0, 0, 0 end
  return (s["cpu.a"] or 0), (s["cpu.k"] or 0), (s["cpu.pc"] or 0)
end

-- (a) the two loader entry points -------------------------------------------
local loads = {}
for _, spec in ipairs({ { 0xEB4B, "EB4B verbatim" }, { 0xEC5E, "EC5E relocating" } }) do
  for _, bank in ipairs({ 0x000000, 0x800000, 0xC00000 }) do
    local a = bank + spec[1]
    emu.addMemoryCallback(function()
      local A, k, pc = st()
      local off = emu.read(0x7E0010, emu.memType.snesMemory)
                + emu.read(0x7E0011, emu.memType.snesMemory) * 256
      loads[#loads + 1] = string.format(
        "f%-5d %s  A=%04X (bank id %d) dp$10=%04X  from %02X:%04X",
        frames, spec[2], A, A & 0xFF, off, k, pc)
    end, emu.callbackType.exec, a, a, emu.cpuType.snes, emu.memType.snesMemory)
  end
end

-- (b) reads of the per-character directory table ($E4:2CA4..$E4:2E04) --------
local DIRLO, DIRHI = 0x242CA4, 0x242E04     -- PRG-ROM file offsets
local dirreads, ndir = {}, 0
emu.addMemoryCallback(function(addr)
  ndir = ndir + 1
  if ndir > 40 then return end
  local A, k, pc = st()
  local rel = addr - 0x242CC4
  dirreads[#dirreads + 1] = string.format(
    "f%-5d read $E4:%04X (char %d entry %d) @ %02X:%04X",
    frames, addr & 0xFFFF, rel >= 0 and (rel // 32) + 1 or 0,
    rel >= 0 and (rel % 32) // 4 or -1, k, pc)
end, emu.callbackType.read, DIRLO, DIRHI, emu.cpuType.snes, emu.memType.snesPrgRom)

-- ARAM access ---------------------------------------------------------------
local ARAM
for _, n in ipairs({ "spcMemory", "spcRam", "SpcMemory" }) do
  if emu.memType[n] then ARAM = emu.memType[n] end
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function()
    emu.write(0x1B40, CHARA, emu.memType.snesWorkRam)
    emu.write(0x1B80, CHAR2, emu.memType.snesWorkRam)
    return sf > 20
  end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = beat({ a = true }); return sf > 60 end,
  function() return sf > 240 end,
  function()
    pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
    return ram(0x1000) == CHARA or sf > 600
  end,
  function() return ram(0x1000) == CHARA and ram(0x1080) ~= 0 end,
  function() return sf > 60 end,
}

local done = false
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] and not done then
    done = true
    log(string.format("=== P1 char %d (RAM $1D00=%d)  P2 char %d (RAM $1D03=%d) ===",
      CHARA, ram(0x1D00), CHAR2, ram(0x1D03)))
    log("--- voice-bank loader calls ---")
    if #loads == 0 then log("  (none seen — autopilot may not have reloaded)") end
    for _, l in ipairs(loads) do log("  " .. l) end
    log("--- directory-table reads (" .. ndir .. " total) ---")
    for _, l in ipairs(dirreads) do log("  " .. l) end
    if ARAM then
      local f = assert(io.open(ENV.TRACE .. "saturn/aram_dir_" .. TAG .. ".bin", "wb"))
      local t = {}
      for a = 0, 0xFFFF do t[#t + 1] = string.char(emu.read(a, ARAM)) end
      f:write(table.concat(t)); f:close()
      log("--- ARAM $3500 (voice directory as uploaded) ---")
      for e = 0, 7 do
        local b = {}
        for i = 0, 3 do b[i] = emu.read(0x3500 + e * 4 + i, ARAM) end
        log(string.format("  entry %d  start $%02X%02X  loop $%02X%02X",
          e, b[1], b[0], b[3], b[2]))
      end
      log("--- ARAM $3400 (main directory, entries 0-3 for reference) ---")
      for e = 0, 3 do
        local b = {}
        for i = 0, 3 do b[i] = emu.read(0x3400 + e * 4 + i, ARAM) end
        log(string.format("  entry %d  start $%02X%02X  loop $%02X%02X",
          e, b[1], b[0], b[3], b[2]))
      end
    else
      log("NO ARAM MEMTYPE")
    end
    log("done")
    emu.stop(0)
  end
  if frames > 4000 then
    log("TIMEOUT step=" .. step .. " p1char=" .. string.format("%02X", ram(0x1000)))
    for _, l in ipairs(loads) do log("  " .. l) end
    emu.stop(1)
  end
end, emu.eventType.endFrame)

print("probe_sms_voiceload loaded")
