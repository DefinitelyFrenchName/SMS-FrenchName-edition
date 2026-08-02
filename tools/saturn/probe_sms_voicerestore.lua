-- probe_sms_voicerestore.lua — the session-hygiene half of task #44.
--
-- Saturn's voice works by overwriting char 1's half of the resident BRR
-- directory (ARAM $34C0 for P1 / $34D0 for P2) with HER sample boundaries. That
-- directory is uploaded once at boot and never refreshed, so without a restore a
-- Saturn match would leave Moon voicing from the wrong offsets — a buzz — for
-- the rest of the session. mksaturn_smoke.py therefore puts char 1's vanilla
-- record back on any non-Saturn voice-bank load, gated on a DIRTY flag in
-- $7F:F107/F108.
--
-- The scenario has two halves and this probe covers the second one directly:
--   * "a Saturn match sets DIRTY and installs her offsets" is proven by
--     probe_sms_voicecheck.lua (it reads both);
--   * this probe proves the RESTORE: it dirties ARAM by hand at character
--     select — writing her directory over char 1's half and setting the DIRTY
--     flag, exactly the state a previous Saturn match leaves behind — then
--     starts an ordinary Moon match and checks that the load put char 1's own
--     record back and cleared the flag.
--
-- (Driving two real matches would be closer to life, but ending a VS match from
-- an autopilot proved unreliable — the KO never landed — and a probe that
-- silently never reaches its second match is worse than one that is explicit
-- about what it sets up.)
--
-- usage: ROM=build/saturn/<rom> tools/run.sh \
--            tools/saturn/probe_sms_voicerestore.lua 900
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local PLAYER = tonumber(os.getenv("PLAYER") or "0")
local TAG = os.getenv("TAG") or ("restore_p" .. (tonumber(os.getenv("PLAYER") or "0") + 1))
local LOG = assert(io.open(ENV.TRACE .. "saturn/voicerestore_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram
local ARAM = emu.memType.spcRam
local WRAM = emu.memType.snesWorkRam
local MAGIC = 0xA5
local DIRTY = PLAYER == 0 and 0x1F107 or 0x1F108
local HALF = 0x34C0 + (PLAYER == 0 and 0 or 0x10)
-- what a Saturn match leaves behind (her bank at $B700 / $DB00; sizes from
-- tools/saturn/extract_saturn_voice.py)
local SIZES = { 0x546, 0xa5f, 0xd1d, 0x72c }
local BASE = PLAYER == 0 and 0xB700 or 0xDB00
-- and what char 1's record should look like afterwards
local VANILLA1 = PLAYER == 0 and 0xBCB2 or 0xE0B2

local fails, checks = 0, 0
local function check(ok, what, detail)
  checks = checks + 1
  if not ok then fails = fails + 1 end
  log(string.format("  [%s] %s%s", ok and "PASS" or "FAIL", what,
    detail and ("  — " .. detail) or ""))
end
local function dirline(a)
  local s = {}
  for e = 0, 3 do
    s[#s + 1] = string.format("[%02X%02X/%02X%02X]",
      emu.read(a + e * 4 + 1, ARAM), emu.read(a + e * 4, ARAM),
      emu.read(a + e * 4 + 3, ARAM), emu.read(a + e * 4 + 2, ARAM))
  end
  return table.concat(s, " ")
end
local function entry1(a) return emu.read(a + 4, ARAM) + 256 * emu.read(a + 5, ARAM) end

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
    emu.write(0x1B40, 1, WRAM)          -- P1 = MOON, the character we hijack
    emu.write(0x1B80, 9, WRAM)
    return sf > 20
  end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = beat({ a = true }); return sf > 60 end,
  function()
    if sf == 1 then
      -- leave behind exactly what a finished Saturn match leaves behind
      local acc = BASE
      for e = 0, 3 do
        local stop = acc + SIZES[e + 1]
        emu.write(HALF + e * 4, acc & 0xFF, ARAM)
        emu.write(HALF + e * 4 + 1, acc >> 8, ARAM)
        emu.write(HALF + e * 4 + 2, stop & 0xFF, ARAM)
        emu.write(HALF + e * 4 + 3, stop >> 8, ARAM)
        acc = stop
      end
      emu.write(DIRTY, MAGIC, WRAM)
      log(string.format("=== dirtied $%04X before the load: %s (DIRTY=$%02X) ===",
        HALF, dirline(HALF), ram(DIRTY)))
      check(entry1(HALF) ~= VANILLA1, "setup: the directory really is dirty")
    end
    return sf > 200
  end,
  function()
    pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
    return ram(0x1000) ~= 0 and ram(0x1080) ~= 0 or sf > 600
  end,
  function() return sf > 180 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("=== after an ordinary P%d load (P1 char $%02X, P2 char $%02X) ===",
      PLAYER + 1, ram(0x1000), ram(0x1080)))
    log("  $" .. string.format("%04X ", HALF) .. dirline(HALF))
    check(ram(0x1000) == 1, "P1 is Moon (the hijacked character)",
      string.format("charID $%02X", ram(0x1000)))
    check(entry1(HALF) == VANILLA1,
      string.format("char 1's half at $%04X was RESTORED", HALF),
      string.format("entry 1 start = $%04X, vanilla is $%04X", entry1(HALF), VANILLA1))
    check(ram(DIRTY) == 0, "DIRTY flag cleared",
      string.format("= $%02X", ram(DIRTY)))
    log(string.format("=== %d checks, %d FAILED ===", checks, fails))
    log(fails == 0 and "ALL PASS" or "FAILURES PRESENT")
    emu.stop(fails == 0 and 0 or 1)
  end
  if frames > 6000 then log("TIMEOUT at step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_voicerestore loaded")
