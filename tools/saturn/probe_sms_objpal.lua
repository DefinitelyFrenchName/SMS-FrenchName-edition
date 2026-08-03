-- probe_sms_objpal.lua — field report (2026-08-04): fighting AGAINST Saturn, the
-- PROJECTILES (and only the projectiles) come out the wrong colours.
--
-- Known mechanism, recorded in mksaturn_smoke.py since v0.11.1: both games draw
-- projectiles with **OAM palette 2**, and the transform injects Super S's blue
-- effects palette into CGRAM shadow row `$0640` (= OBJ pal 2) so HER fireballs
-- are blue instead of the shell game's fire-orange. OBJ pal 2 is shared, so the
-- opponent's projectiles recolour too. It was accepted as a tradeoff; this probe
-- asks whether it has to be one.
--
-- What it measures:
--   * the whole OBJ half of the CGRAM shadow ($0600-$06FF = OBJ palettes 0-7),
--     Saturn vs vanilla, so the changed row is shown rather than assumed
--   * a histogram of which OAM palette indices are actually in use in a match
--     (the full 3-bit field, not a truncated one) — i.e. is there a spare row to
--     move her projectiles onto
--
--   SATURN=1 ROM=<saturn build> tools/run.sh tools/saturn/probe_sms_objpal.lua 500
-- envs: SATURN=0|1, P1CHAR (default 7 Neptune — has a projectile), DUMMY (6)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr

local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SATURN = os.getenv("SATURN") ~= "0"
local SATP1 = os.getenv("SATP1") == "1"   -- P1 is the Saturn shell and shoots
local P1CHAR = num("P1CHAR", SATP1 and 6 or 7)   -- Neptune 214+P / Uranus shell
local DUMMY = num("DUMMY", 6)       -- Uranus shell -> Saturn when armed
local TAG = os.getenv("TAG") or ("objpal_" .. (SATURN and "saturn" or "vanilla"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local frames, step, sf = 0, 1, 0
local pulse = {}
local hold = false
local function beat(on) return (frames % 7) < 3 and on or {} end
local seen, shot, projframes = {}, false, 0

-- WHO loads OBJ palette rows 5 and 6, and does anything ever DRAW with them?
-- They differ between a Saturn and a vanilla match (found 2026-08-04) but no
-- sprite used them in the first sample, so the question is what subsystem owns
-- them. Rows are $7E:0600 + row*0x20, so row 5 = $06A0..$06BF, row 6 = $06C0..$06DF.
local cw, cwseen = 0, {}
if os.getenv("PALWATCH") == "1" then
  for a = 0x06A0, 0x06DF do
    emu.addMemoryCallback(function(addr, value)
      local ok, st = pcall(emu.getState)
      local pc = string.format("%02X:%04X", ok and st["cpu.k"] or 0, ok and st["cpu.pc"] or 0)
      local row = (addr >= 0x06C0) and 6 or 5
      local key = pc .. "/row" .. row
      if not cwseen[key] then
        cwseen[key] = true; cw = cw + 1
        if cw <= 12 then
          log(string.format("  CGRAMW row%d <= %02X @ %s (first write from this PC)",
            row, value or -1, pc))
        end
      end
    end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesWorkRam)
  end
end

-- WHO writes the projectile's +0x08 (the attr/palette byte: OAM attr = +0x08<<1,
-- so palette = +0x08 & 7). WorkRam-typed, because WRAM $0000-$1FFF is aliased
-- into every $00-$3F / $80-$BF bank and an address-typed watch misses stores
-- made with another DB.
local aw = 0
emu.addMemoryCallback(function(_, value)
  if aw >= 10 or (value or 0) == 0 then return end
  local ok, st = pcall(emu.getState)
  aw = aw + 1
  log(string.format("  ATTRW $1108 <= %02X @ %02X:%04X", value or -1,
    ok and st["cpu.k"] or 0, ok and st["cpu.pc"] or 0))
end, emu.callbackType.write, 0x1108, 0x1108, emu.cpuType.snes, emu.memType.snesWorkRam)

-- OBJ half of the CGRAM shadow: $7E:0600 + row*0x20, rows 0-7 = OBJ palettes 0-7
local function palrow(r)
  local t = {}
  for i = 0, 15 do
    local lo = ram(0x600 + r * 32 + i * 2)
    local hi = ram(0x600 + r * 32 + i * 2 + 1)
    t[#t + 1] = string.format("%04X", lo + 256 * hi)
  end
  return table.concat(t, " ")
end
local function dumppals(label)
  log("  --- OBJ palettes " .. label .. " ---")
  for r = 0, 7 do log(string.format("   pal%d: %s", r, palrow(r))) end
end

-- which OAM palette indices are actually used (attr bits 1-3 = the full field)
local function palhist(label)
  local h = {}
  for i = 0, 7 do h[i] = 0 end
  local n = 0
  for i = 0, 127 do
    local o = i * 4
    if (emu.read(o + 1, emu.memType.snesSpriteRam) or 0) < 0xE0 then
      local a = emu.read(o + 3, emu.memType.snesSpriteRam) or 0
      local p = (a >> 1) & 7
      h[p] = h[p] + 1; n = n + 1
    end
  end
  local parts = {}
  for i = 0, 7 do if h[i] > 0 then parts[#parts + 1] = string.format("pal%d=%d", i, h[i]) end end
  log(string.format("  OAM palette use %s (%d sprites): %s", label, n, table.concat(parts, " ")))
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    -- arm the DUMMY only: in practice the dummy's cursor is confirmed through
    -- the P2 pad ([$FE] low byte $62), so P1 stays its own character
    if p == (SATP1 and 0 or 1) and hold and SATURN then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

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
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 150 end,
  function()
    if sf == 1 then
      log(string.format("IN MATCH: p1=%02X dummy=%02X (%s)",
        ram(0x1000), ram(0x1080), SATURN and "SATURN" or "vanilla"))
      dumppals("in match, no projectile")
      palhist("idle")
    end
    -- 214+LP = Neptune's Deep Submerge; 236+LP = Saturn's qcf projectile
    local m = sf % 40
    if SATP1 then
      if m < 6 then pulse[0] = { down = true }
      elseif m < 12 then pulse[0] = { down = true, right = true }
      elseif m < 18 then pulse[0] = { right = true }
      elseif m < 22 then pulse[0] = { y = true }
      else pulse[0] = {} end
    else
      if m < 6 then pulse[0] = { down = true }
      elseif m < 12 then pulse[0] = { down = true, left = true }
      elseif m < 18 then pulse[0] = { left = true }
      elseif m < 22 then pulse[0] = { y = true }
      else pulse[0] = {} end
    end
    -- projectile slots $1100 / $1180
    -- accumulate palette usage over the WHOLE match window: a single-frame
    -- sample says nothing about whether a row is spare
    for i = 0, 127 do
      local o = i * 4
      if (emu.read(o + 1, emu.memType.snesSpriteRam) or 0) < 0xE0 then
        local a = emu.read(o + 3, emu.memType.snesSpriteRam) or 0
        seen[(a >> 1) & 7] = (seen[(a >> 1) & 7] or 0) + 1
      end
    end
    if (ram(0x1100) ~= 0 or ram(0x1180) ~= 0) and not shot then
      shot = true
      log(string.format("  PROJECTILE LIVE at sf=%d: $1100=%02X $1180=%02X",
        sf, ram(0x1100), ram(0x1180)))
      local f = io.open(ENV.TRACE .. "saturn/" .. TAG .. "_proj.png", "wb")
      f:write(emu.takeScreenshot()); f:close()
    end
    if projframes < 6 and (ram(0x1100) ~= 0 or ram(0x1180) ~= 0) then
      projframes = projframes + 1
      palhist("projectile live")
      -- the sprite emitter builds the OAM attr from the object's +0x08 (<<9),
      -- so +0x08 should BE the palette index. Read it for the live projectile.
      for _, b in ipairs({ 0x1100, 0x1180 }) do
        if ram(b) ~= 0 then
          log(string.format("    proj slot $%04X: id=%02X +08=%02X +0A=%02X%02X",
            b, ram(b), ram(b + 8), ram(b + 0x0B), ram(b + 0x0A)))
        end
      end
    end
    if sf > 900 then
      local parts = {}
      for i = 0, 7 do parts[#parts + 1] = string.format("pal%d=%d", i, seen[i] or 0) end
      log("  CUMULATIVE OAM palette use over the match: " .. table.concat(parts, " "))
      return true
    end
    return false
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    dumppals("final")
    log(string.format("FINAL p1=%02X dummy=%02X", ram(0x1000), ram(0x1080)))
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_objpal loaded: " .. (SATURN and "SATURN" or "vanilla"))
