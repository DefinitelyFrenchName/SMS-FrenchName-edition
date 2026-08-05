-- probe_saturn_projoam.lua — IDENTIFY which OAM entries belong to Saturn's 214P
-- projectile, by correlation over time rather than by a plausible property.
--
-- Every previous attempt at this bug guessed the projectile's sprites from a
-- property (a palette row, a distance window) and every one of them was wrong:
-- the palette filter returned zero entries, the distance window returned the
-- FIGHTER. So this probe assumes nothing. It logs the complete live OAM every
-- frame across the projectile's whole lifetime plus the projectile slot's raw
-- struct, and the correlation is done offline: entries that appear when the
-- slot populates, vanish when it clears, and move with it are the projectile's.
--
--   SHELL_ID=6 TAG=v149 ROM=<build> tools/run.sh tools/saturn/probe_saturn_projoam.lua 700
-- Output: traces/saturn/projoam_<TAG>.txt  (one record per frame)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
local SATURN = os.getenv("SATURN") ~= "0"
local TAG = os.getenv("TAG") or "projoam"
local LOG = assert(io.open(ENV.TRACE .. "saturn/projoam_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n") end

local OAM = emu.memType.snesSpriteRam
local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local recording, recframes = false, 0

local function beat(on) return (frames % 7) < 3 and on or {} end
local function setchars() wr(0x1B40, SHELL); wr(0x1B80, 4) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and SATURN and p == 0 then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local function snapshot()
  -- projectile slot, raw: which of these bytes is its screen position is itself
  -- an open question, so dump the head of the struct rather than pick offsets.
  local s = {}
  for i = 0, 0x2F do s[#s + 1] = string.format("%02X", ram(0x1100 + i)) end
  log(string.format("F %d slot1100 %s", frames, table.concat(s)))
  log(string.format("F %d p1 act=%02X x=%02X%02X y=%02X",
    frames, ram(0x1001), ram(0x1022), ram(0x1021), ram(0x1025)))
  for i = 0, 127 do
    local o = i * 4
    local y = emu.read(o + 1, OAM) or 0xE0
    if y < 0xE0 then
      local x = emu.read(o, OAM) or 0
      local t = emu.read(o + 2, OAM) or 0
      local a = emu.read(o + 3, OAM) or 0
      local hi = emu.read(0x200 + math.floor(i / 4), OAM) or 0
      local sh = (i % 4) * 2
      log(string.format("F %d oam %d %d %d %03X %d %d %d %02X",
        frames, i, x + (((hi >> sh) & 1) * 256), y,
        t + ((a & 1) * 256), (a >> 1) & 7, (a >> 4) & 3, (hi >> (sh + 1)) & 1, a))
    end
  end
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
    local m = sf % 60
    if m < 6 then pulse[0] = { down = true }
    elseif m < 12 then pulse[0] = { down = true, left = true }
    elseif m < 18 then pulse[0] = { left = true }
    elseif m < 22 then pulse[0] = { y = true }
    else pulse[0] = {} end
    -- start recording 6 frames BEFORE the slot populates is impossible, so
    -- record continuously from the first press and mark the slot state per
    -- frame; the offline pass finds the before/after boundary itself.
    if not recording and sf > 20 then recording = true end
    if recording then snapshot(); recframes = recframes + 1 end
    return recframes > 200
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("DONE recframes=%d", recframes))
    LOG:close(); emu.stop(recframes > 0 and 0 or 1)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
