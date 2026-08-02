-- probe_sms_selectwho.lua — at the select-voice load, WHICH PLAYER is being
-- voiced? (Delivery of Saturn's "Yoroshiku".)
--
-- The mechanism is now known: on confirm, $C0:AE4C reads $1B1E as an index into
-- two parallel tables — $C0:AE75 gives the audio-bank id (22-30 = the nine
-- select-voice banks, each uploading one BRR sample to ARAM $B700) and
-- $C0:AE7F gives the sound id (48/53/58/…, all of which resolve to directory
-- entry 48 = $B700). So Saturn needs only her own bank swapped in; the sound id
-- can stay the shell's.
--
-- The open question is the same one the card portrait got wrong: $1B1E names the
-- CHARACTER, not the player, and Saturn can be summoned over any shell — so a
-- hook keyed on the character alone would fire for an ordinary player picking
-- the same one. This logs everything available at the load so the player can be
-- identified from measurement.
--
-- usage: CHAR=6 CHAR2=9 SAT=1 ROM=build/saturn/<rom> tools/run.sh \
--            tools/saturn/probe_sms_selectwho.lua 600
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "6")
local CHAR2 = tonumber(os.getenv("CHAR2") or "9")
local SATP = tonumber(os.getenv("SAT") or "0")     -- which player gets the flag (0/1), -1 = none
local TAG = os.getenv("TAG") or "who"
local LOG = assert(io.open(ENV.TRACE .. "saturn/selectwho_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local MEM = emu.memType.snesMemory
local WRAM = emu.memType.snesWorkRam

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local hits = 0
for _, a in ipairs({ 0x00AE58, 0x80AE58, 0xC0AE58 }) do
  emu.addMemoryCallback(function()
    hits = hits + 1
    local ok, s = pcall(emu.getState)
    log(string.format(
      "  f%-5d LOAD#%d  A=$%02X (bank id %d)  $1B1E=%02X $1C50=%02X | "
      .. "$1B40=%02X $1B42=%02X $1B80=%02X $1B82=%02X | "
      .. "satflags %02X/%02X  X=%04X",
      frames, hits, (ok and s and s["cpu.a"] or 0) & 0xFF,
      (ok and s and s["cpu.a"] or 0) & 0xFF,
      ram(0x1B1E), ram(0x1C50), ram(0x1B40), ram(0x1B42), ram(0x1B80), ram(0x1B82),
      ram(0x1F100), ram(0x1F101), (ok and s and s["cpu.x"]) or 0))
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, MEM)
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function()
    if sf > 240 then
      log(string.format("=== P1 char %d, P2 char %d, Saturn flag on %s ===",
        CHAR, CHAR2, SATP < 0 and "nobody" or ("P" .. (SATP + 1))))
      return true
    end
    return false
  end,
  function() wr(0x1B40, CHAR); wr(0x1B80, CHAR2); return sf > 30 end,
  -- Arm her the way a player does: HOLD L+R while confirming. Poking the flag
  -- instead does not work and that is informative — the hidden confirm stub
  -- re-decides on every confirm press and clears a flag with no code held, which
  -- also proves the stub runs BEFORE the select-voice load.
  function()
    local b = { a = true }
    if SATP == 0 then b.l = true; b.r = true end
    pulse[0] = beat(b)
    if SATP == 0 then pulse[0].l = true; pulse[0].r = true end
    return ram(0x1B42) == 1 or sf > 120
  end,
  function() pulse[0] = {}; return sf > 90 end,
  function()
    local b = { a = true }
    pulse[1] = beat(b)
    if SATP == 1 then pulse[1].l = true; pulse[1].r = true end
    return sf > 200
  end,
  function() return sf > 120 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("total loads seen: %d", hits))
    log("done"); emu.stop(0)
  end
  if frames > 4000 then log("TIMEOUT step " .. step .. " loads=" .. hits); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_selectwho loaded")
