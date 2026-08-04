-- probe_sms_voicepitch.lua — measurement only, changes nothing: does Saturn's
-- VOICE play at a different pitch depending on which shell she wears?
--
-- Field observation (maintainer, 2026-08-04): her voice pitch varies with the
-- shell character. Parked as "probably risky to change" — this probe exists to
-- turn that into a costed decision rather than a guess.
--
-- What pitch actually is here: the BRR *directory* the port patches only supplies
-- each sample's start/loop ADDRESS — it does not set pitch. Pitch is the SNES
-- DSP's per-voice `VxPITCH` pair (registers $x2/$x3, 14-bit; $1000 = the sample's
-- native rate, so 2x = one octave up), written by the sound driver at key-on.
-- She borrows char 1's sound IDS, so if pitch were a property of the id alone it
-- would be CONSTANT across shells. If it varies, something character-indexed is
-- applied on top — and that is what a fix would have to target.
--
-- Method: hook writes to the DSP's KON register ($4C) and, for every voice keyed
-- on, read back that voice's SRCN ($x4) and PITCH ($x2/$x3). Voice samples live
-- in directory entries 48-63 (P1 $B700 = 48-55, P2 $DB00 = 56-63, see
-- docs/saturn/sound_scope.md), so SRCN >= 48 filters her voice out of the music.
--
--   SHELL_ID=6 ROM=<saturn build> tools/run.sh tools/saturn/probe_sms_voicepitch.lua 600
-- envs: SHELL_ID (6/7/8 — the shell she wears), SATURN=0 (no transform, reference),
--       DUMMY, TAG
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr

local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
local SATURN = os.getenv("SATURN") ~= "0"
local DUMMY = num("DUMMY", 4)
local ROW = num("ROW", 4)
local TAG = os.getenv("TAG") or ("voicepitch_" .. (SATURN and "sat" or "van") .. SHELL)
local LOG = assert(io.open(ENV.TRACE .. "saturn/" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local DSP = emu.memType.spcDspRegisters
local function dsp(r) return emu.read(r, DSP) or 0 end

local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local seen, order, keyons = {}, {}, 0
local allkeyons, allsrcn = 0, {}
local VOICE_LO = num("VOICE_LO", 48)
local acts = {}
local function beat(on) return (frames % 7) < 3 and on or {} end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if p == 0 and hold and SATURN then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

-- The DSP is programmed through the SPC700's two ports: $00F2 latches the
-- register index, $00F3 writes it. A write callback on memType.spcDspRegisters
-- never fires (tried first: 0 key-ons while her specials were demonstrably
-- running), so shadow the register file from the port writes instead — that is
-- the traffic itself and cannot be missed.
local dspaddr = 0
local shadow = {}
emu.addMemoryCallback(function(_, v) dspaddr = v or 0 end,
  emu.callbackType.write, 0xF2, 0xF2, emu.cpuType.spc, emu.memType.spcMemory)

emu.addMemoryCallback(function(_, value)
  shadow[dspaddr] = value or 0
  if dspaddr ~= 0x4C then return end          -- KON: one bit per voice
  if (value or 0) == 0 then return end
  for v = 0, 7 do
    if ((value >> v) & 1) == 1 then
      local base = v * 16
      local pitch = (shadow[base + 2] or 0) | ((shadow[base + 3] or 0) << 8)
      local srcn = shadow[base + 4] or 0
      -- count EVERYTHING first: "no key-ons matching my filter" and "my callback
      -- never fired" look identical in a summary, and only one of them is a
      -- finding (HANDOFF §5)
      allkeyons = allkeyons + 1
      local sk = string.format("step%-2d srcn=%02d pitch=$%04X", step, srcn, pitch)
      allsrcn[sk] = (allsrcn[sk] or 0) + 1
      if srcn >= VOICE_LO then                -- the per-player VOICE banks
        keyons = keyons + 1
        -- tag with the flow step: the CHARACTER-SELECT confirm voice is a
        -- different path from the in-match voices (bank-id table $C0:AE75,
        -- sound id = 21 + charID — i.e. the id itself is per-CHARACTER), so it
        -- is the better suspect for anything that varies with the shell
        local key = string.format("step%-2d srcn=%02d pitch=$%04X", step, srcn, pitch)
        if not seen[key] then
          seen[key] = 0; order[#order + 1] = key
        end
        seen[key] = seen[key] + 1
      end
    end
  end
end, emu.callbackType.write, 0xF3, 0xF3, emu.cpuType.spc, emu.memType.spcMemory)

local STEPS = {
  function() return frames >= 900 end,
  -- ROW: 4 = practice (default), 2 = vs-COM, 1 = 2P VS. The character-select
  -- CONFIRM voice never fired in practice, and it is the one audio path whose
  -- sound id is per-CHARACTER (21 + charID, table $C0:AE75) — so it has to be
  -- checked in a mode that plays it.
  function()
    local want = (ROW == 4) and 1 or ROW
    pulse[0] = beat({ down = true }); return ram(0x1B10) == want
  end,
  function()
    if ROW ~= 4 then return true end
    pulse[0] = beat({ right = true }); return ram(0x1B10) == 4
  end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() wr(0x1B40, SHELL); wr(0x1B80, DUMMY); hold = true; return sf > 20 end,
  function() wr(0x1B40, SHELL); wr(0x1B80, DUMMY)
             pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    wr(0x1B40, SHELL); wr(0x1B80, DUMMY)
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then
      log("MATCH-LOAD-FAIL (select-phase data above is still valid)")
      local ss = {}
      for k, v in pairs(allsrcn) do ss[#ss + 1] = string.format("%s x%d", k, v) end
      table.sort(ss); for _, l in ipairs(ss) do log("    " .. l) end
      emu.stop(1)
    end
    return false
  end,
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 150 end,
  function()
    if sf == 1 then
      log(string.format("IN MATCH: p1=%02X (shell %d, %s) dummy=%02X",
        ram(0x1000), SHELL, SATURN and "SATURN" or "vanilla", ram(0x1080)))
    end
    -- 236+LP and 214+LP: two of her voiced specials (v0.13.0)
    local m = sf % 60
    if m < 6 then pulse[0] = { down = true }
    elseif m < 12 then pulse[0] = { down = true, right = true }
    elseif m < 18 then pulse[0] = { right = true }
    elseif m < 22 then pulse[0] = { y = true }
    elseif m < 30 then pulse[0] = {}
    elseif m < 36 then pulse[0] = { down = true }
    elseif m < 42 then pulse[0] = { down = true, left = true }
    elseif m < 48 then pulse[0] = { left = true }
    elseif m < 52 then pulse[0] = { y = true }
    else pulse[0] = {} end
    acts[ram(0x1001)] = (acts[ram(0x1001)] or 0) + 1
    return sf > 900
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("ALL key-ons: %d ; matching srcn>=%d: %d", allkeyons, VOICE_LO, keyons))
    local ss = {}
    for k, v in pairs(allsrcn) do ss[#ss + 1] = string.format("%s x%d", k, v) end
    table.sort(ss)
    log("  EVERY key-on by flow step:")
    for _, l in ipairs(ss) do log("    " .. l) end
    local aa = {}
    for k, v in pairs(acts) do if v > 20 then aa[#aa + 1] = string.format("%02X x%d", k, v) end end
    table.sort(aa)
    log("  P1 acts seen (>20f): " .. table.concat(aa, " "))
    for _, k in ipairs(order) do log(string.format("  %s  x%d", k, seen[k])) end
    log(string.format("FINAL p1=%02X shell=%d %s", ram(0x1000), SHELL,
      SATURN and "SATURN" or "vanilla"))
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_voicepitch loaded: shell " .. SHELL .. (SATURN and " SATURN" or " vanilla"))
