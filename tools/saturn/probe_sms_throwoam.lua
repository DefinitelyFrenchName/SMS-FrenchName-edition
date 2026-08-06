-- probe_sms_throwoam.lua — field bug 1 (throw corruption), the A/B that the
-- previous round did not run: the SAME throw with the dummy as Saturn and as the
-- plain vanilla shell, instrumented at the layer the tiles actually come from.
--
-- Known already (probe_sms_throwbug.lua): acts 1C->1D->1E->20 run normally, her
-- cels DO stream, stage-tile VRAM is untouched for a normal throw, and the downed
-- sprite is still drawn from tiles that are not hers. So the fault is not "no
-- data arrived" — it is WHERE the data went, or WHICH tiles the sprite points at.
-- This probe logs both halves of that:
--   * every cel DMA with its VRAM DESTINATION (the old probe logged src+len only)
--   * OAM at chosen frames: each visible sprite's x/y/tile/attr, split into the
--     two fighters by x position, so "the victim's sprites are reading tiles from
--     the thrower's window" is directly visible
--
-- SATURN=1 arms the dummy with L+R; SATURN=0 runs the identical flow vanilla.
-- Diff the two logs — anything that differs is the port's doing.
--
--   SATURN=1 ROM=<saturn build> tools/run.sh tools/saturn/probe_sms_throwoam.lua 500
--   SATURN=0 ROM=<saturn build> tools/run.sh tools/saturn/probe_sms_throwoam.lua 500
-- envs: SATURN=0|1, P1CHAR (thrower, default 4=Jupiter), DUMMY (default 6=Uranus)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local MEMT = emu.memType.snesMemory

local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SATURN = os.getenv("SATURN") ~= "0"
local CMD = os.getenv("CMD") == "1"      -- drive a COMMAND grab (360+P) instead
local CONTACT = num("CONTACT", 18)       -- px the victim is parked at for the SPD
local P1CHAR = num("P1CHAR", 4)      -- Jupiter: has a command throw too
local DUMMY = num("DUMMY", 6)        -- Uranus shell (6/7/8 only, since v0.14.5)

local TAG = os.getenv("TAG") or ("throwoam_" .. (CMD and "cmd_" or "") .. (SATURN and "saturn" or "vanilla"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local frames, step, sf = 0, 1, 0
local pulse = {}
local hold = false
local dmawin, dmalog = false, 0
local lastpose, lastact, maxspr = -1, -1, 0
local vram0, vramdiff = {}, -1
local walkact, walkvic, walklog = -1, -1, 0
local function beat(on) return (frames % 7) < 3 and on or {} end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if p == 1 and hold and SATURN then b.l = true; b.r = true end   -- arm the DUMMY
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

-- VRAM address latch, so each DMA can be attributed to a window
local vaddr = 0
for _, base in ipairs({ 0x002116, 0x802116 }) do
  emu.addMemoryCallback(function(_, v) vaddr = (vaddr & 0xFF00) | (v or 0) end,
    emu.callbackType.write, base, base, emu.cpuType.snes, MEMT)
  emu.addMemoryCallback(function(_, v) vaddr = (vaddr & 0x00FF) | ((v or 0) << 8) end,
    emu.callbackType.write, base + 1, base + 1, emu.cpuType.snes, MEMT)
end

for _, base in ipairs({ 0x00420B, 0x80420B }) do
  emu.addMemoryCallback(function(_, value)
    if not dmawin or dmalog > 60 then return end
    for ch = 0, 7 do
      if ((value or 0) >> ch) & 1 == 1 then
        local c = 0x804300 + ch * 16
        local b = emu.read(c + 1, MEMT) or 0
        if b == 0x18 or b == 0x19 then
          dmalog = dmalog + 1
          local sb = emu.read(c + 4, MEMT) or 0
          local sa = ((emu.read(c + 3, MEMT) or 0) << 8) | (emu.read(c + 2, MEMT) or 0)
          local ln = ((emu.read(c + 6, MEMT) or 0) << 8) | (emu.read(c + 5, MEMT) or 0)
          -- VRAM word address -> tile number at 4bpp (32 bytes = 16 words / tile)
          log(string.format("  +%3df CEL-DMA src=$%02X:%04X len=%04X -> VRAM $%04X (tile %3d, %d tiles)",
            sf, sb, sa, ln, vaddr, math.floor(vaddr / 16), math.floor(ln / 32)))
        end
      end
    end
  end, emu.callbackType.write, base, base, emu.cpuType.snes, MEMT)
end

-- WHO writes the victim's pose (+0x05)? During a throw the thrower's script is
-- the suspect: if it drives the victim's pose with SMS pose numbers, a ported
-- character whose table is its own (and shorter) gets an out-of-range index.
-- WorkRam-TYPED callback, not snesMemory: WRAM $0000-$1FFF is aliased into the
-- low half of every $00-$3F and $80-$BF bank, so an address-typed watch on
-- $00:1085 / $7E:1085 misses a store made with any other DB (the renderer runs
-- with DB=$84). This cost a round here — the first watch saw nothing during the
-- throw hold and the pose was demonstrably changing.
local posew = 0
emu.addMemoryCallback(function(addr, value)
  if not dmawin or posew >= 30 then return end
  local st = select(2, pcall(emu.getState)) or {}
  posew = posew + 1
  log(string.format("  +%3df POSEW <= %02X @ %02X:%04X", sf, value or -1,
    st["cpu.k"] or 0, st["cpu.pc"] or 0))
end, emu.callbackType.write, 0x1085, 0x1085, emu.cpuType.snes, emu.memType.snesWorkRam)

-- which of the two thrown-pose read sites actually runs. $C1:0740 is the normal
-- throw interpreter; $C1:0C5C belongs to the second one (the command/carry
-- throws). Both are patched to the same stub, so this is the coverage check.
local site1, site2 = 0, 0
emu.addMemoryCallback(function() site1 = site1 + 1 end,
  emu.callbackType.exec, 0xC10740, 0xC10740, emu.cpuType.snes, MEMT)
emu.addMemoryCallback(function() site2 = site2 + 1 end,
  emu.callbackType.exec, 0xC10C5C, 0xC10C5C, emu.cpuType.snes, MEMT)

-- OAM dump: x/y/tile/attr per sprite, grouped by which fighter owns the x range
local function oamdump(label)
  local x1, x2 = ram(0x1010), ram(0x1090)     -- rough per-player screen x
  log(string.format("  --- OAM %s (p1x~%d p2x~%d) ---", label, x1, x2))
  local rows = {}
  for i = 0, 127 do
    local o = i * 4
    local y = emu.read(o + 1, emu.memType.snesSpriteRam) or 0
    if y < 0xE0 then
      local x = emu.read(o, emu.memType.snesSpriteRam) or 0
      local t = emu.read(o + 2, emu.memType.snesSpriteRam) or 0
      local a = emu.read(o + 3, emu.memType.snesSpriteRam) or 0
      local tile = t | ((a & 1) << 8)
      rows[#rows + 1] = string.format("%d:(%d,%d)t%03X p%d%s", i, x, y, tile,
        (a >> 1) & 3, (a & 0x40) ~= 0 and "F" or "")
    end
  end
  -- summarise the tile ranges in use — that is the signal, not the raw list
  local lo, hi, n = 0xFFF, 0, 0
  for i = 0, 127 do
    local o = i * 4
    local y = emu.read(o + 1, emu.memType.snesSpriteRam) or 0
    if y < 0xE0 then
      local t = (emu.read(o + 2, emu.memType.snesSpriteRam) or 0)
              | (((emu.read(o + 3, emu.memType.snesSpriteRam) or 0) & 1) << 8)
      if t < lo then lo = t end
      if t > hi then hi = t end
      n = n + 1
    end
  end
  log(string.format("  sprites=%d  tile range $%03X..$%03X", n, lo, hi))
  for i = 1, #rows, 6 do
    log("    " .. table.concat(rows, "  ", i, math.min(i + 5, #rows)))
  end
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() wr(0x1B40, P1CHAR); wr(0x1B80, DUMMY); hold = true; return sf > 20 end,
  function() wr(0x1B40, P1CHAR); wr(0x1B80, DUMMY)
             pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    wr(0x1B40, P1CHAR); wr(0x1B80, DUMMY)
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 120 end,
  function()   -- walk in and KEEP TRYING until the grab actually connects.
    -- A fixed walk-then-tap is not deterministic here: the match start drifts by
    -- tens of frames with the char-select mash, so some runs never threw at all
    -- and reported a clean OAM for a throw that never happened. Gate on the
    -- victim's act instead of on a frame number.
    if sf == 1 then
      log(string.format("IN MATCH: p1=%02X dummy=%02X  (%s)",
        ram(0x1000), ram(0x1080), SATURN and "SATURN" or "vanilla"))
      oamdump("idle")
    end
    local va = ram(0x1081)
    if va == 0x1C or (CMD and va ~= 0x00 and va ~= 0x01 and va ~= 0x12) then
      log(string.format("GRAB CONNECTED at sf=%d (%s) victim act=%02X",
        sf, CMD and "command" or "normal", va))
      return true
    end
    if CMD then
      -- Jupiter's SPD, minimum input per the maintainer: **6 2 4 8 + P**, with
      -- the 8 and the P allowed on the same frame, and you must be at CONTACT
      -- range for it to land. (The regression suite's longer "6321478" motion
      -- does come out here, but its up-steps make him jump and it always
      -- whiffed.) Uranus's SPD is the same motion with K.
      local ax = ram(0x1021) + 256 * ram(0x1022)
      local dx = (ax + CONTACT) % 65536
      wr(0x10A1, dx % 256); wr(0x10A2, math.floor(dx / 256))
      local m = sf % 40
      if m < 6 then pulse[0] = { right = true }
      elseif m < 12 then pulse[0] = { down = true }
      elseif m < 18 then pulse[0] = { left = true }
      elseif m < 24 then pulse[0] = { up = true, x = true }
      else pulse[0] = {} end
    else
      pulse[0] = (sf % 24 < 18) and { right = true }
        or { right = true, x = true }
    end
    if walkact ~= ram(0x1001) or walkvic ~= ram(0x1081) then
      walkact, walkvic = ram(0x1001), ram(0x1081)
      if walklog < 40 then
        walklog = walklog + 1
        log(string.format("    sf=%d p1 act=%02X victim act=%02X", sf, walkact, walkvic))
      end
    end
    if sf > 900 then log("THROW-NEVER-CONNECTED"); emu.stop(1) end
    return false
  end,
  function()   -- the grab is already live; release everything and watch it play out
    pulse[0] = {}
    if sf == 1 then
      vram0 = {}
      for a = 0x4000, 0x5FFF, 64 do vram0[#vram0 + 1] = emu.read(a, emu.memType.snesVideoRam) or 0 end
    end
    dmawin = (sf >= 1 and sf <= 250)
    -- POSE is struct +0x05 (renderer $C0:9A0E: `lda $05,x` -> pose*2 indexes the
    -- char's pose->spritelist table; the list's first byte is the sprite COUNT)
    if sf >= 1 then
      local pose, act = ram(0x1085), ram(0x1081)
      if pose ~= lastpose or act ~= lastact then
        log(string.format("  +%3df dummy act=%02X POSE +05 = %02X", sf, act, pose))
        lastpose, lastact = pose, act
      end
      -- the regression metric: OAM flooding. Count visible sprites every frame
      -- and keep the worst — 127 is the runaway emitter, ~50 is healthy.
      local n = 0
      for i = 0, 127 do
        if (emu.read(i * 4 + 1, emu.memType.snesSpriteRam) or 0) < 0xE0 then n = n + 1 end
      end
      if n > maxspr then maxspr = n end
    end
    if sf == 250 then
      local i, diff = 0, 0
      for a = 0x4000, 0x5FFF, 64 do
        i = i + 1
        if (emu.read(a, emu.memType.snesVideoRam) or 0) ~= vram0[i] then diff = diff + 1 end
      end
      vramdiff = math.floor(100 * diff / i)
    end
    if sf == 40 or sf == 90 or sf == 150 or sf == 210 then
      log(string.format("  +%3df p1 act=%02X  dummy id=%02X act=%02X +18=%02X",
        sf, ram(0x1001), ram(0x1080), ram(0x1081), ram(0x1098)))
      oamdump("throw+" .. sf)
      local f = io.open(ENV.TRACE .. "saturn/" .. TAG .. "_" .. sf .. ".png", "wb")
      if not f then print("probe_sms_throwoam.lua: cannot open " .. (ENV.TRACE .. "saturn/" .. TAG .. "_" .. sf .. ".png")) emu.stop(1) return end
      f:write(emu.takeScreenshot()); f:close()
    end
    return sf > 260
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("FINAL p1=%02X dummy=%02X  MAX-SPRITES=%d %s",
      ram(0x1000), ram(0x1080), maxspr,
      maxspr >= 120 and "*** OAM FLOOD ***" or "(healthy)")
      .. string.format("  stage-tile VRAM changed %d%%  site1=%d site2=%d",
        vramdiff, site1, site2))
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_throwoam loaded: " .. (SATURN and "SATURN" or "vanilla"))
