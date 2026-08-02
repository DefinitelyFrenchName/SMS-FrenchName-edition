-- probe_sms_voicecheck.lua — does Saturn's voice actually land in the APU?
-- (task #44 acceptance test for the injection built by mksaturn_smoke.py.)
--
-- Checks, in one match:
--   1. her sample bank is byte-identical in ARAM at $B700 (P1) / $DB00 (P2)
--      to build/saturn/saturn_voice.brr;
--   2. char 1's directory half for HER player holds her sample boundaries;
--   3. the OTHER half is still char 1's vanilla record (we must never touch the
--      opponent's side);
--   4. firing her ids 49..52 starts DSP voice 4/5 on directory entries 48..51
--      (+4 for P2) — i.e. the driver really resolves her ids to her samples.
--
-- SATURN=0 runs the same checks inverted: no Saturn, so $B700 must hold the
-- shell's bank and the directory must be char 1's vanilla record — that is the
-- RESTORE path, which is what keeps a later Moon match sounding right.
--
-- usage: SATURN=1 PLAYER=0 CHARA=6 CHAR2=9 ROM=build/saturn/<rom> \
--            tools/run.sh tools/saturn/probe_sms_voicecheck.lua 900
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHARA = tonumber(os.getenv("CHARA") or "6")
local CHAR2 = tonumber(os.getenv("CHAR2") or "9")
local SATURN = (os.getenv("SATURN") or "1") ~= "0"
local PLAYER = tonumber(os.getenv("PLAYER") or "0")   -- which side is Saturn
local TAG = os.getenv("TAG") or (SATURN and ("sat_p" .. PLAYER) or "vanilla")
local LOG = assert(io.open(ENV.TRACE .. "saturn/voicecheck_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram
local ARAM = emu.memType.spcRam
local DSP = emu.memType.spcDspRegisters
local WRAM = emu.memType.snesWorkRam

local fails, checks = 0, 0
local function check(ok, what, detail)
  checks = checks + 1
  if not ok then fails = fails + 1 end
  log(string.format("  [%s] %s%s", ok and "PASS" or "FAIL", what,
    detail and ("  — " .. detail) or ""))
end

local function readfile(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local d = f:read("*a"); f:close(); return d
end
local BRR = readfile(ENV.ROOT .. "build/saturn/saturn_voice.brr")

-- Saturn's flag/latch live in $7F (long) = work RAM offset $1Fxxx.
local FLAG = { [0] = 0x1F100, [1] = 0x1F101 }
local LATCH = { [0] = 0x1F102, [1] = 0x1F103 }
local MAGIC = 0xA5

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
    emu.write(0x1B40, CHARA, WRAM)
    emu.write(0x1B80, CHAR2, WRAM)
    return sf > 20
  end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = beat({ a = true }); return sf > 60 end,
  function()
    -- arm her the way the hidden char-select code does: set the SELECT flag.
    -- The round-load DMA stub latches it at the effects transfer; the voice
    -- hook accepts either, because the bank load may run before that point.
    if SATURN and sf == 1 then emu.write(FLAG[PLAYER], MAGIC, WRAM) end
    return sf > 240
  end,
  function()
    pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
    return ram(0x1000) ~= 0 and ram(0x1080) ~= 0 or sf > 600
  end,
  function()
    -- the $EF helper only transforms at neutral, after the round intro; waiting
    -- on the id (rather than a fixed delay) keeps this honest on slow loads
    if not SATURN then return sf > 180 end
    return ram(PLAYER == 0 and 0x1000 or 0x1080) == 0x1C or sf > 600
  end,
  function() return sf > 30 end,
}

local inmatch = false
local id, phase, waited = 49, "gap", 0
local VOICE = PLAYER == 0 and 4 or 5
local before = { srcn = -1 }
local function vstate()
  return { srcn = emu.read(VOICE * 0x10 + 4, DSP), envx = emu.read(VOICE * 0x10 + 8, DSP) }
end

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if not inmatch then
    local fn = STEPS[step]
    if fn and fn() then step = step + 1; sf = 0; pulse = {} end
    if not STEPS[step] then
      inmatch = true
      local base = PLAYER == 0 and 0xB700 or 0xDB00
      local mine = 0x34C0 + (PLAYER == 0 and 0 or 0x10)
      local theirs = 0x34C0 + (PLAYER == 0 and 0x10 or 0)
      log(string.format("=== %s | P1 char %d P2 char %d | Saturn on %s ===",
        SATURN and "SATURN" or "VANILLA", CHARA, CHAR2,
        SATURN and ("P" .. (PLAYER + 1)) or "nobody"))
      log(string.format("struct charIDs: P1 $%02X  P2 $%02X   flags $%02X/$%02X latches $%02X/$%02X",
        ram(0x1000), ram(0x1080), ram(0x1F100), ram(0x1F101), ram(0x1F102), ram(0x1F103)))

      if SATURN then
        check(ram(PLAYER == 0 and 0x1000 or 0x1080) == 0x1C,
          "her player transformed to object id $1C")
      end
      local _ok, _err = pcall(function()

      -- 1. the sample bank in ARAM
      if BRR then
        local diff, first = 0, nil
        for i = 1, #BRR do
          if emu.read(base + i - 1, ARAM) ~= BRR:byte(i) then
            diff = diff + 1; first = first or (base + i - 1)
          end
        end
        if SATURN then
          local d = nil
          if diff ~= 0 then
            d = string.format("%d bytes differ, first at $%04X", diff, first or 0)
          end
          check(diff == 0, string.format("her %d-byte bank is resident at $%04X", #BRR, base), d)
        else
          check(diff > 0, string.format("$%04X holds the SHELL's bank, not hers", base),
            string.format("%d of %d bytes differ (expected: many)", diff, #BRR))
        end
      else
        check(false, "build/saturn/saturn_voice.brr readable")
      end

      -- 2/3. the directory halves
      local function rd(a)
        local t = {}
        for e = 0, 3 do
          t[e] = { emu.read(a + e * 4, ARAM) + 256 * emu.read(a + e * 4 + 1, ARAM),
                   emu.read(a + e * 4 + 2, ARAM) + 256 * emu.read(a + e * 4 + 3, ARAM) }
        end
        return t
      end
      local function fmt(t)
        local s = {}
        for e = 0, 3 do s[#s + 1] = string.format("[%04X/%04X]", t[e][1], t[e][2]) end
        return table.concat(s, " ")
      end
      -- her four samples, as sizes, give the expected starts
      local SIZES = { 0x546, 0xa5f, 0xd1d, 0x72c }
      local want, acc = {}, base
      for e = 0, 3 do want[e] = acc; acc = acc + SIZES[e + 1] end
      local got = rd(mine)
      log(string.format("  directory @ $%04X (hers)  %s", mine, fmt(got)))
      local okdir = true
      for e = 0, 3 do if got[e][1] ~= want[e] then okdir = false end end
      if SATURN then
        local d = nil
        if not okdir then
          d = string.format("want %04X %04X %04X %04X", want[0], want[1], want[2], want[3])
        end
        check(okdir, string.format("her directory half at $%04X points at her samples", mine), d)
      else
        local d = nil
        if okdir then d = "still holds Saturn's offsets — the restore path did not run" end
        check(not okdir, string.format("directory at $%04X was RESTORED to vanilla", mine), d)
      end
      local other = rd(theirs)
      log(string.format("  directory @ $%04X (other) %s", theirs, fmt(other)))
      local otherok = true
      for e = 0, 3 do if other[e][1] == want[e] then otherok = false end end
      check(otherok, string.format("the opponent's half at $%04X is untouched", theirs))
      end)
      if not _ok then log("  !! init error: " .. tostring(_err)) ; fails = fails + 1 end
      log("--- id sweep (hers are 49..52) ---")
    end
    return
  end

  if id > 52 then
    log(string.format("=== %d checks, %d FAILED ===", checks, fails))
    log(fails == 0 and "ALL PASS" or "FAILURES PRESENT")
    emu.stop(fails == 0 and 0 or 1)
    return
  end
  if phase == "gap" then
    waited = waited + 1
    if waited >= 24 then before = vstate(); waited = 0; phase = "fire" end
  elseif phase == "fire" then
    emu.write(PLAYER == 0 and 0x1078 or 0x10F8, id, WRAM)
    phase, waited = "wait", 0
  else
    waited = waited + 1
    local now = vstate()
    if waited > 6 and now.envx > 0 and now.srcn ~= before.srcn then
      local want = 48 + (id - 49) + (PLAYER == 0 and 0 or 4)
      check(now.srcn == want, string.format("id %d -> directory entry %d", id, want),
        now.srcn == want and nil or string.format("got %d", now.srcn))
      id = id + 1; phase, waited = "gap", 0
    elseif waited > 24 then
      check(false, string.format("id %d started a voice", id), "silent")
      id = id + 1; phase, waited = "gap", 0
    end
  end
  if frames > 6000 then log("TIMEOUT at step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_voicecheck loaded")
