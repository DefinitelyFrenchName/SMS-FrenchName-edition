-- probe_saturn_throwshot.lua — capture Saturn MID-THROW as raw VRAM + OAM +
-- CGRAM, so her thrown sprite can be composed and LOOKED AT offline.
--
-- Why: the field reports her sprite corrupting while thrown, but every existing
-- instrument (probe_sms_throwoam's sprite-count/stage-VRAM check, and a
-- frame-by-frame OAM/CGRAM fingerprint) reports the same thing on every build
-- tested. None of them can separate a good build from a bad one, so none of them
-- is the right instrument. The rendered sprite is what the report is ABOUT, and
-- it is what settled the 214P projectile after five failed attempts.
--
-- It captures on the victim's throw acts (1C/1D/1E/20/23), several frames across
-- the sequence, and asserts the precondition: the victim must actually be
-- Saturn (charID $1C) and a throw act must actually occur, or it fails loudly
-- rather than producing clean-looking empty output.
--
--   SHELL_ID=7 TAG=v1413 ROM=<build> tools/run.sh tools/saturn/probe_saturn_throwshot.lua 700
-- Output: traces/saturn/throwshot_<TAG>_<n>.{vram,oam,cgram} + a .txt index
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
-- SATURN=0 runs the IDENTICAL flow with the plain shell character as the victim.
-- That control is the whole point: a thrown fighter tumbles and looks odd at
-- sprite scale either way, so "her toss looks strange" means nothing until the
-- same toss with a vanilla victim is next to it.
local SATURN = os.getenv("SATURN") ~= "0"
local P1CHAR = num("P1CHAR", 4)
local TAG = os.getenv("TAG") or "throwshot"
local OUT = ENV.TRACE .. "saturn/"
local LOG = assert(io.open(OUT .. "throwshot_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local OAM, CG, VRAM = emu.memType.snesSpriteRam, emu.memType.snesCgRam, emu.memType.snesVideoRam
local frames, step, sf = 0, 1, 0
local pulse, hold, rec, shots = {}, false, 0, 0
local THROW_ACTS = { [0x1C] = true, [0x1D] = true, [0x1E] = true, [0x20] = true, [0x23] = true }
local seen_throw = false

local function beat(on) return (frames % 7) < 3 and on or {} end
local function poke() wr(0x1B40, P1CHAR); wr(0x1B80, SHELL) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and SATURN and p == 1 then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local function dump(kind, mt, len, n)
  local f = assert(io.open(OUT .. "throwshot_" .. TAG .. "_" .. n .. "." .. kind, "wb"))
  local c = {}
  for i = 0, len - 1 do
    c[#c + 1] = string.char(emu.read(i, mt) or 0)
    if #c == 4096 then f:write(table.concat(c)); c = {} end
  end
  if #c > 0 then f:write(table.concat(c)) end
  f:close()
end

local function shoot()
  shots = shots + 1
  dump("vram", VRAM, 0x10000, shots)
  dump("oam", OAM, 0x220, shots)
  dump("cgram", CG, 0x200, shots)
  log(string.format("SHOT %d frame=%d victim act=%02X pose=%02X char=%02X",
    shots, frames, ram(0x1081), ram(0x1082), ram(0x1080)))
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() poke(); hold = true; return sf > 20 end,
  function() poke(); pulse[0] = beat({ a = true })
             return ram(0x1B42) == 1 or sf > 120 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    poke()
    local m = frames % 14
    pulse[0] = (m < 3) and { a = true } or ((m >= 7 and m < 10) and { start = true } or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); LOG:close(); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 150 end,
  function()
    local want = SATURN and 0x1C or SHELL
    if ram(0x1080) ~= want then
      log(string.format("WRONG VICTIM char=%02X want=%02X", ram(0x1080), want))
      LOG:close(); emu.stop(1)
    end
    if sf < 90 then pulse[0] = { right = true }
    elseif sf % 30 < 6 then pulse[0] = { right = true, x = true }
    else pulse[0] = {} end
    local act = ram(0x1081)
    if THROW_ACTS[act] then
      seen_throw = true
      -- Sample every PHASE, not every Nth frame. A flat "every 7th throw frame"
      -- put all six shots inside act $1C (the grab, which lasts ~60 frames) and
      -- never once caught the toss -- which is the part of the throw the report
      -- is about. Shoot on each act change and again a few frames in.
      if shots < 12 and (act ~= _G.last_act or rec - (_G.last_shot or -99) > 9) then
        shoot(); _G.last_shot = rec
      end
      _G.last_act = act
      rec = rec + 1
    end
    return shots >= 12 or sf > 900
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    if not seen_throw then
      log("NO THROW OCCURRED — harness problem, not a finding")
      LOG:close(); emu.stop(1)
    end
    log("DONE shots=" .. shots); LOG:close(); emu.stop(shots > 0 and 0 or 1)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
