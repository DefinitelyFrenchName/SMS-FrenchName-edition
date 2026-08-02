-- probe_sms_voiceid.lua — map a VOICE sound id to the BRR directory entry the
-- DSP actually plays it from (task #44).
--
-- Background. The NMI at $C0:D4F2 forwards P1's $1078 to APU port 0 and P2's
-- $10F8 to port 1 with bit 7 SET (`ora #$80`). Character procs in bank $C1
-- request voices with `lda #id / sta $78,X`; the ids run 50 + (charID-1)*5 + k.
-- The BRR directory is resident in ARAM: a 32-byte record per character at
-- $34C0 + (charID-1)*32, holding 8 entries — 0-3 describe that character's
-- samples in P1's bank at $B700, 4-7 the same samples in P2's bank at $DB00.
--
-- This probe forces each id in turn and reads the DSP's SRCN register for the
-- voice that starts, which IS the directory index. That converts the layout
-- above from inference into measurement, and tells us whether Saturn can keep
-- fixed ids (patching one character's half-record) or must follow her shell's.
--
-- usage: CHARA=6 CHAR2=9 IDLO=68 IDHI=76 TAG=ura ROM=<rom> tools/run.sh \
--            tools/saturn/probe_sms_voiceid.lua 600
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHARA = tonumber(os.getenv("CHARA") or "6")
local CHAR2 = tonumber(os.getenv("CHAR2") or "9")
local IDLO = tonumber(os.getenv("IDLO") or "48")
local IDHI = tonumber(os.getenv("IDHI") or "96")
local PLAYER = tonumber(os.getenv("PLAYER") or "0")     -- 0 = P1 ($1078), 1 = P2 ($10F8)
local TAG = os.getenv("TAG") or "x"
local LOG = assert(io.open(ENV.TRACE .. "saturn/voiceid_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram
local DSP = emu.memType.spcDspRegisters
local ARAM = emu.memType.spcRam
local function dsp(r) return emu.read(r, DSP) end

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

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
  function() return sf > 90 end,
}

-- sweep state. The voice channel is fixed per player (measured: P1 = DSP voice
-- 4, P2 = voice 5), so watch only that one — scanning all eight picked up music
-- voices retriggering and produced junk rows. Each id gets an idle GAP first so
-- the previous sample has released, then the SRCN is read only once it has both
-- CHANGED and gone audible.
local VOICE = tonumber(os.getenv("VOICE") or (PLAYER == 0 and "4" or "5"))
local GAP = tonumber(os.getenv("GAP") or "24")
local inmatch, id, phase, waited = false, IDLO, "gap", 0
local results = {}
local before = { srcn = -1, envx = 0 }

local function vstate()
  return { srcn = dsp(VOICE * 0x10 + 4), envx = dsp(VOICE * 0x10 + 8) }
end

-- what the NMI actually put on the APU ports (P2's id should arrive with bit 7
-- set — $C0:D500 `ora #$80` — and that bit is the only thing telling the driver
-- to use the $DB00 half of the record)
local sent = {}
for port = 0, 2 do
  for _, b in ipairs({ 0x002140 + port, 0x802140 + port }) do
    emu.addMemoryCallback(function(_, value)
      if (value or 0) ~= 0 then sent[port] = value end
    end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
  end
end

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if not inmatch then
    local fn = STEPS[step]
    if fn and fn() then step = step + 1; sf = 0; pulse = {} end
    if not STEPS[step] then
      inmatch = true
      log(string.format("=== P1 char %d, P2 char %d — driving %s ===",
        CHARA, CHAR2, PLAYER == 0 and "P1 ($1078)" or "P2 ($10F8, |$80)"))
      log(string.format("DSP DIR page = $%02X  (directory base ARAM $%02X00)",
        dsp(0x5D), dsp(0x5D)))
      log("--- ARAM directory records, char 1..9 @ $34C0 + (char-1)*32 ---")
      for c = 1, 9 do
        local base = 0x34C0 + (c - 1) * 32
        local parts = {}
        for e = 0, 7 do
          local o = base + e * 4
          parts[#parts + 1] = string.format("[%02X%02X/%02X%02X]",
            emu.read(o + 1, ARAM), emu.read(o, ARAM),
            emu.read(o + 3, ARAM), emu.read(o + 2, ARAM))
        end
        log(string.format("  char %d dir idx %3d..%3d  %s", c,
          48 + (c - 1) * 8, 55 + (c - 1) * 8, table.concat(parts, " ")))
      end
      log("--- id sweep: id -> DSP voice/SRCN that starts ---")
    end
    return
  end

  if id > IDHI then
    log("--- summary ---")
    for _, r in ipairs(results) do log("  " .. r) end
    log("done")
    emu.stop(0)
    return
  end

  if phase == "gap" then
    waited = waited + 1
    if waited >= GAP then before = vstate(); waited = 0; phase = "fire" end
  elseif phase == "fire" then
    sent[0], sent[1] = nil, nil
    emu.write(PLAYER == 0 and 0x1078 or 0x10F8, id, emu.memType.snesWorkRam)
    phase, waited = "wait", 0
  else
    waited = waited + 1
    local now = vstate()
    if now.envx > 0 and now.srcn ~= before.srcn then
      results[#results + 1] = string.format(
        "id %3d ($%02X) -> SRCN %3d   [port0=%s port1=%s]", id, id, now.srcn,
        sent[0] and string.format("$%02X", sent[0]) or "-",
        sent[1] and string.format("$%02X", sent[1]) or "-")
      log("  " .. results[#results])
      id = id + 1; phase, waited = "gap", 0
    elseif waited > 20 then
      results[#results + 1] = string.format("id %3d ($%02X) -> (silent; SRCN stayed %3d)",
        id, id, now.srcn)
      log("  " .. results[#results])
      id = id + 1; phase, waited = "gap", 0
    end
  end

  if frames > 6000 then log("TIMEOUT step=" .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_voiceid loaded")
