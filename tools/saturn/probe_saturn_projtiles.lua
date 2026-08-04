-- probe_saturn_projtiles.lua — capture Saturn's 214P projectile as SPRITES, to
-- chase the field report "the 214P projectile has a corrupted sprite since
-- v0.14.6 — some tiles missing, some in the wrong place".
--
-- Note the wording: TILES, not colours. v0.14.9 moved her projectiles to OBJ
-- palette row 7, which is a palette change and cannot drop or displace a tile —
-- so the palette work is probably not the cause, and the report predates it.
-- v0.14.6 is also the build that made 2P VS transform at all, so "since 0.14.6"
-- may mean FIRST VISIBLE rather than introduced there. Bisect, do not assume.
--
-- What it records while the projectile is alive: every OAM entry (tile index,
-- attribute byte, position, size bit) plus the VRAM bytes of each tile those
-- entries reference. A missing tile shows up as a blank VRAM tile behind a live
-- OAM entry; a misplaced one shows up as the same tile index at a different
-- position, or a different index for the same sprite slot.
--
--   SHELL_ID=6 TAG=v149 ROM=<build> tools/run.sh tools/saturn/probe_saturn_projtiles.lua 700
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
-- SATURN=0 plays the plain shell character: the CONTROL. A vanilla projectile
-- referencing blank VRAM would mean "blank tiles" is normal here and proves
-- nothing; if only hers does, the defect is hers.
local SATURN = os.getenv("SATURN") ~= "0"
local TAG = os.getenv("TAG") or "projtiles"
local LOG = assert(io.open(ENV.TRACE .. "saturn/projtiles_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local OAM = emu.memType.snesSpriteRam
local VRAM = emu.memType.snesVideoRam
local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local captured = false

local function beat(on) return (frames % 7) < 3 and on or {} end
local function setchars() wr(0x1B40, SHELL); wr(0x1B80, 4) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and SATURN and p == 0 then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local function capture(why)
  captured = true
  -- The rendered frame is the only metric that is guaranteed to separate a
  -- known-good build from a known-bad one, which is exactly the control the
  -- earlier OAM metric lacked. v0.14.1 is intact per the maintainer; v0.14.6
  -- shows the fragmented projectile. Any measurement that cannot tell those two
  -- apart is measuring the wrong thing.
  local sf_ = io.open(ENV.TRACE .. "saturn/proj_" .. TAG .. ".png", "wb")
  if sf_ then sf_:write(emu.takeScreenshot()); sf_:close() end
  log("=== " .. why .. " (frame " .. frames .. ") ===")
  log(string.format("proj slots: $1100 id=%02X  $1180 id=%02X", ram(0x1100), ram(0x1180)))
  -- OAM: 128 entries of 4 bytes, then 32 bytes of high table (x9 + size)
  local used = {}
  for i = 0, 127 do
    local o = i * 4
    local y = emu.read(o + 1, OAM) or 0
    if y < 0xE0 then                       -- offscreen sprites park at y>=$E0
      local x = emu.read(o, OAM) or 0
      local t = emu.read(o + 2, OAM) or 0
      local a = emu.read(o + 3, OAM) or 0
      local tile = t | ((a & 1) << 8)
      local pal = (a >> 1) & 7
      used[#used + 1] = { i = i, x = x, y = y, tile = tile, pal = pal, attr = a }
    end
  end
  log(string.format("live OAM entries: %d", #used))
  -- Locate her sprites by POSITION, not palette: the palette row moved in
  -- v0.14.9 (2 -> 7), so a palette filter compares different things across the
  -- builds being bisected and reported 0 entries on one of them.
  local px = ram(0x1121) + 256 * ram(0x1122)
  local py = ram(0x1125)
  log(string.format("projectile object: x=%d y=%d", px % 512, py))
  -- both axes: an x-only window caught the FIGHTER (y=97 while the projectile
  -- sits at y=168) and buried the signal in unrelated sprites
  -- Position alone is NOT enough: a 32 px window around the projectile also
  -- contains the fighter, and a vanilla-Neptune control showed the same tiles
  -- and the same "blank" count as Saturn — i.e. the earlier metric was measuring
  -- the character, not the projectile, and the v0.14.8 "bisection" built on it
  -- was unsound. A projectile is drawn on ITS SLOT'S palette row (2 for $1100,
  -- 3 for $1180; her own row is 7 from v0.14.9), so require the palette too.
  local mine = {}
  for _, e in ipairs(used) do
    local dx = math.min(math.abs(e.x - (px % 256)), 256 - math.abs(e.x - (px % 256)))
    local dy = math.abs(e.y - py)
    if (e.pal == 2 or e.pal == 3 or e.pal == 7) and dx <= 64 and dy <= 64 then
      mine[#mine + 1] = e
    end
  end
  log(string.format("entries near the projectile: %d (of %d live)", #mine, #used))
  for _, e in ipairs(mine) do
    local base = e.tile * 32
    local blank = true
    local sum = 0
    for b = 0, 31 do
      local v = emu.read(base + b, VRAM) or 0
      if v ~= 0 then blank = false end
      sum = (sum + v * (b + 1)) % 65536
    end
    log(string.format("  oam%-3d x=%3d y=%3d tile=$%03X pal=%d attr=$%02X  vram=%s sum=$%04X",
      e.i, e.x, e.y, e.tile, e.pal, e.attr, blank and "BLANK" or "data ", sum))
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
    -- 214 + LP, repeatedly; capture 20 frames after the projectile appears
    local m = sf % 60
    if m < 6 then pulse[0] = { down = true }
    elseif m < 12 then pulse[0] = { down = true, left = true }
    elseif m < 18 then pulse[0] = { left = true }
    elseif m < 22 then pulse[0] = { y = true }
    else pulse[0] = {} end
    if not captured and (ram(0x1100) ~= 0 or ram(0x1180) ~= 0) then
      if not _G.seen_at then _G.seen_at = sf end
      if sf - _G.seen_at >= 20 then capture("projectile live, +20f") end
    end
    return sf > 900
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    if not captured then log("NO PROJECTILE SEEN — harness problem, not a finding") end
    emu.stop(captured and 0 or 1)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)
