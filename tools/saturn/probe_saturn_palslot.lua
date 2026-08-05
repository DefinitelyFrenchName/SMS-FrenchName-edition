-- probe_saturn_palslot.lua — does Saturn's fighter palette follow the button the
-- player confirmed with?
--
-- Patch 3 (in REF) replaced the vanilla two-palette scheme with up to 32 slots
-- per character, chosen at the character select: A=0 B=1 Y=2 X=3, then L/R/Start
-- modifiers for 4..31. The slot for the round lands in $1D02 (P1) / $1D05 (P2).
-- Before v0.14.12 her transform copied palette 0 unconditionally and threw that
-- choice away, so she looked the same on every button.
--
-- The probe confirms with PALBTN and then reports BOTH the slot variable and the
-- 32 bytes actually in CGRAM, because those answer different questions: the slot
-- says the select screen did its job, the CGRAM row says her transform honoured
-- it. Checking only one would pass on a build where the other is broken.
--
--   PALBTN=y SHELL_ID=6 ROM=<build> tools/run.sh tools/saturn/probe_saturn_palslot.lua 500
-- Output: traces/saturn/palslot_<PALBTN>.txt, last line "PALSLOT ..."
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
local BTN = (os.getenv("PALBTN") or "a"):lower()
-- PLAYER=2 arms the dummy instead: her P2 transform reads $1D05, a different
-- variable through a different branch of the copier, so P1 passing proves
-- nothing about it (HANDOFF trap #1).
local PLAYER = num("PLAYER", 1)
local STRUCT = PLAYER == 2 and 0x1080 or 0x1000
local CGROW = PLAYER == 2 and 144 or 128      -- P2's fighter row is CGRAM $0620
-- TAG keeps runs on DIFFERENT BUILDS from clobbering each other: the output was
-- keyed only by button, so a negative-control run on an older ROM silently
-- overwrote the good build's rows and a later comparison read the wrong build.
local TAG = (os.getenv("TAG") or BTN) .. (PLAYER == 2 and "_p2" or "")
local LOG = assert(io.open(ENV.TRACE .. "saturn/palslot_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local CG = emu.memType.snesCgRam
local frames, step, sf = 0, 1, 0
local pulse, hold, done = {}, false, false
local function beat(on) return (frames % 7) < 3 and on or {} end
local function setchars()
  if PLAYER == 2 then wr(0x1B40, 4); wr(0x1B80, SHELL)
  else wr(0x1B40, SHELL); wr(0x1B80, 4) end
end
local function confirm() local t = {}; t[BTN] = true; return t end
-- POKE1/POKE2 force the two slot variables to DIFFERENT values during the round
-- load. In practice mode the dummy's slot is always 0, so a P2 run cannot
-- otherwise tell "the copier reads $1D05" from "the copier always uses slot 0".
local POKE1, POKE2 = num("POKE1", -1), num("POKE2", -1)
local function poke()
  if POKE1 >= 0 then wr(0x1D02, POKE1) end
  if POKE2 >= 0 then wr(0x1D05, POKE2) end
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and p == (PLAYER - 1) then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local function measure()
  done = true
  if ram(STRUCT) ~= 0x1C then
    log("NOT-SATURN charID=" .. ram(STRUCT)); LOG:close(); emu.stop(1)
  end
  local row = {}
  for i = 0, 31 do row[#row + 1] = string.format("%02X", emu.read(CGROW * 2 + i, CG) or 0) end
  log(string.format("PALSLOT btn=%s p%d shell=%d p1slot=%d p2slot=%d cgram=%s",
    BTN, PLAYER, SHELL, ram(0x1D02), ram(0x1D05), table.concat(row)))
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() setchars(); hold = true; return sf > 20 end,
  -- the CHARACTER confirm: this is the press whose button picks the palette
  function() setchars(); pulse[0] = beat(confirm())
             return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    -- later screens are advanced with A/Start regardless; only the confirm above
    -- carries the palette choice
    setchars()
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    poke()
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); LOG:close(); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; poke(); if sf > 90 then measure(); return true end; return false end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then LOG:close(); emu.stop(done and 0 or 1) end
  if frames > 6000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
