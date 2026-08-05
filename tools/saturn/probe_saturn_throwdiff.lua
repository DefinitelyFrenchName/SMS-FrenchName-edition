-- probe_saturn_throwdiff.lua — frame-by-frame fingerprint of Saturn being
-- thrown, so two builds can be compared for ANY divergence.
--
-- Field report (v0.14.12): her sprite corrupts while she is thrown; v0.14.11 is
-- clean. The existing throw probe reports "healthy / stage-tile VRAM 0%" on both
-- builds, i.e. it cannot separate a known-good build from a known-bad one, which
-- by this project's own rule makes it the wrong instrument for this question.
--
-- So this records a per-frame fingerprint of everything the sprite could be made
-- of -- OAM, the victim's struct, and the CGRAM rows -- and prints it. Diff the
-- two logs: the first frame that differs localises the fault, and identical logs
-- are themselves a finding (the difference is not in what this samples).
--
--   SATURN=1 TAG=v1412 ROM=<build> tools/run.sh tools/saturn/probe_saturn_throwdiff.lua 700
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
local P1CHAR = num("P1CHAR", 4)
local TAG = os.getenv("TAG") or "throwdiff"
local LOG = assert(io.open(ENV.TRACE .. "saturn/throwdiff_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n") end

local OAM, CG, VRAM = emu.memType.snesSpriteRam, emu.memType.snesCgRam, emu.memType.snesVideoRam
local frames, step, sf = 0, 1, 0
local pulse, hold, rec = {}, false, 0

local function beat(on) return (frames % 7) < 3 and on or {} end
local function setchars() wr(0x1B40, P1CHAR); wr(0x1B80, SHELL) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and p == 1 then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local function h32(mt, lo, n)
  local s = 0
  for i = 0, n - 1 do s = (s * 33 + (emu.read(lo + i, mt) or 0)) % 0x100000000 end
  return s
end

local function snap()
  -- the victim is P2 ($1080); log its act/pose plus every live sprite's tile so
  -- a wrong tile shows up directly, not only as a hash
  local tiles = {}
  for i = 0, 127 do
    local y = emu.read(i * 4 + 1, OAM) or 0xE0
    if y < 0xE0 then
      local t = emu.read(i * 4 + 2, OAM) or 0
      local a = emu.read(i * 4 + 3, OAM) or 0
      tiles[#tiles + 1] = string.format("%03X", t | ((a & 1) << 8))
    end
  end
  log(string.format("F %d act=%02X pose=%02X n=%d oam=%08X cg=%08X tiles=%s",
    frames, ram(0x1081), ram(0x1082), #tiles, h32(OAM, 0, 0x220), h32(CG, 0, 0x200),
    table.concat(tiles, ",")))
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() setchars(); hold = true; return sf > 20 end,
  function() setchars(); pulse[0] = beat({ a = true })
             return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    setchars()
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 150 end,
  function()
    -- walk P1 into range and throw: forward, then toward+HP at contact
    if sf < 90 then pulse[0] = { right = true }
    elseif sf % 30 < 6 then pulse[0] = { right = true, x = true }
    else pulse[0] = {} end
    snap(); rec = rec + 1
    return rec > 260
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("DONE rec=" .. rec); LOG:close(); emu.stop(rec > 0 and 0 or 1) end
  if frames > 6000 then log("TIMEOUT " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
