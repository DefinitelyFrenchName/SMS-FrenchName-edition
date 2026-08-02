-- probe_sms_freetable.lua — is the tail of the audio-bank table at $C0:EDD7
-- actually free? (task #44: Saturn needs 2 spare table entries.)
--
-- The bank table at $C0:ECE7 holds 6-byte records; the loaders index it with an
-- 8-bit id, so id n reads $ECE7 + 6n. Vanilla ids top out at 39 (the 9th
-- character's voice bank), and $EDD7 onward is: 6 zero bytes (id 40), ~35 bytes
-- of unidentified data ($EDDD-$EDFF), then a 64-byte ZERO RUN at $EE00-$EE3F —
-- which ids 47..57 index into.
--
-- This project has already been bitten once by treating quiet memory as free
-- (the ARAM region that turned out to be uploaded from bank $E4), so before
-- putting Saturn's stream pointers there: run boot -> title -> char select ->
-- a full match -> KO -> win screen with a read watch over the whole tail, and
-- report every read with the PC that made it. Absence of reads is not a proof,
-- but combined with "ids never exceed 39" it is the evidence available.
--
-- usage: CHARA=6 CHAR2=9 TAG=free ROM=<rom> tools/run.sh \
--            tools/saturn/probe_sms_freetable.lua 900
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHARA = tonumber(os.getenv("CHARA") or "6")
local CHAR2 = tonumber(os.getenv("CHAR2") or "9")
local TAG = os.getenv("TAG") or "free"
local LOG = assert(io.open(ENV.TRACE .. "saturn/freetable_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram

local LO, HI = 0x00EDD7, 0x00EE3F        -- PRG-ROM file offsets = $C0:EDD7..EE3F
local reads, nread = {}, 0
emu.addMemoryCallback(function(addr)
  nread = nread + 1
  if nread > 60 then return end
  local ok, s = pcall(emu.getState)
  local k = (ok and s and s["cpu.k"]) or 0
  local pc = (ok and s and s["cpu.pc"]) or 0
  local id = (addr - 0x00ECE7) // 6
  reads[#reads + 1] = string.format("$C0:%04X (table id %d) @ %02X:%04X",
    addr & 0xFFFF, id, k, pc)
end, emu.callbackType.read, LO, HI, emu.cpuType.snes, emu.memType.snesPrgRom)

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local marks = {}
local function mark(what) marks[#marks + 1] = string.format("f%-5d %s (reads so far %d)", frames, what, nread) end

local STEPS = {
  function() if sf == 1 then mark("boot") end; return frames >= 900 end,
  function() if sf == 1 then mark("title") end; pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() if sf == 1 then mark("char select") end; return sf > 240 end,
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
  function() if sf == 1 then mark("match live") end; return sf > 120 end,
  -- drain P2 so the round ends: KO, round transition, and the win screen all
  -- get exercised (they load banks too)
  function() emu.write(0x10C9, 1, emu.memType.snesWorkRam); return sf > 5 end,
  function() pulse[0] = beat({ x = true }); return ram(0x10C9) == 0 or sf > 300 end,
  function() if sf == 1 then mark("round 1 KO") end; return sf > 400 end,
  function() emu.write(0x10C9, 1, emu.memType.snesWorkRam); return sf > 5 end,
  function() pulse[0] = beat({ x = true }); return ram(0x10C9) == 0 or sf > 300 end,
  function() if sf == 1 then mark("match won -> win/continue screens") end; return sf > 600 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] or frames > 5000 then
    log(string.format("=== reads of $C0:%04X..$C0:%04X (audio-table tail) ===", LO, HI))
    log(string.format("reached step %d of %d, %d frames", step, #STEPS + 1, frames))
    for _, m in ipairs(marks) do log("  " .. m) end
    log(string.format("--- TOTAL READS: %d ---", nread))
    for _, r in ipairs(reads) do log("  " .. r) end
    if nread == 0 then log("VERDICT: no read of the table tail in this run") end
    emu.stop(0)
  end
end, emu.eventType.endFrame)

print("probe_sms_freetable loaded")
