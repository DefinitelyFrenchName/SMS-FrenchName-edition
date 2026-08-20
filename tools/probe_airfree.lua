-- probe_airfree.lua — which PLAYER-STRUCT bytes does a busy match segment
-- never write? (Phase 5 of the anime-fighter feasibility programme: the
-- air-action counter needs a per-player cell, and a struct byte is the
-- natural home because round transitions re-init the structs.)
--
--   SMS_FMODE=census tools/run.sh tools/probe_airfree.lua 120
--       -> traces/airfree_census.txt   per-offset write counts, both structs
--   SMS_FMODE=magic SMS_OFF=7E tools/run.sh tools/probe_airfree.lua 120
--       -> traces/airfree_magic_<off>.txt   poke 0xA5 into the offset on both
--          structs, run the same segment, assert it SURVIVES (a cell nothing
--          writes in the census could still be cleared by a path the census
--          missed — the poke is the positive check).
--
-- Struct writes go through dp,X addressing (D=0), i.e. CPU addresses
-- 0x001000-0x0010FF in the $00-bank WRAM mirror; absolute-indexed writers use
-- $7E too, so BOTH ranges are watched. ⚠ Scope: this watches a match segment
-- (jumps, dashes, attacks, hits, a throw attempt, KO-ish damage) loaded from
-- a savestate — the BOOT path is NOT covered; a promotion beyond exp tier
-- owes the full boot→title→select→match watch per [SMS-33].
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = os.getenv("SMS_FMODE") or "census"
local OFF = tonumber(os.getenv("SMS_OFF") or "7E", 16)
local LOG = assert(io.open(ENV.TRACE .. (MODE == "census" and "airfree_census.txt"
    or string.format("airfree_magic_%02X.txt", OFF)), "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local STATE = "uranus_vs_jupiter_clean.mss"
local writes = {}                 -- offset within a struct (0..0x7F), both players folded
for i = 0, 0x7F do writes[i] = 0 end

-- the watchers: no io, no getState, nothing that can throw (trap 12)
local function watch(a)
  writes[a & 0x7F] = writes[a & 0x7F] + 1
end
emu.addMemoryCallback(watch, emu.callbackType.write, 0x001000, 0x0010FF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(watch, emu.callbackType.write, 0x7E1000, 0x7E10FF, emu.cpuType.snes, emu.memType.snesMemory)

local t, loaded = -1, false
emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_airfree: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

-- a busy segment: walk, jab, jump, double-taps, HP, throw attempt, repeat
local function p(base, o) return PL.ram(base + o) end
local function fwdDir()
  return p(0x1000, 0x21) + 256 * p(0x1000, 0x22) < p(0x1080, 0x21) + 256 * p(0x1080, 0x22)
      and "right" or "left"
end
emu.addEventCallback(function()
  if t < 0 then return end
  local b1, b2 = {}, {}
  local c = t % 240
  local fwd = fwdDir()
  if c < 40 then b1[fwd] = true
  elseif c < 44 then b1.y = true
  elseif c < 70 then if (c % 10) < 4 then b1[fwd] = true end       -- double taps
  elseif c < 76 then b1.up = true; b1[fwd] = true
  elseif c < 110 then if (c % 12) < 4 then b1.x = true end          -- air/ground HP
  elseif c < 140 then b1[fwd] = true; if (c % 14) < 4 then b1.x = true end
  elseif c < 180 then b2[fwd == "right" and "left" or "right"] = true -- P2 walks too
    if (c % 16) < 4 then b2.y = true end
  elseif c < 220 then if (c % 8) < 3 then b1.b = true end           -- kicks
  end
  emu.setInput(PL.pad(b1), 0, 0)
  emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  if MODE == "magic" and t == 5 then
    PL.wr(0x1000 + OFF, 0xA5); PL.wr(0x1080 + OFF, 0xA5)
    log(string.format("t=5 poked A5 into +0x%02X on both structs", OFF))
  end
  if t == 1400 then
    if MODE == "census" then
      log("write counts over 1400 busy frames (both structs folded per offset):")
      local free = {}
      for i = 0, 0x7F do
        local n = writes[i]
        if n > 0 then
          log(string.format("  +0x%02X: %d", i, n))
        else
          free[#free + 1] = string.format("+0x%02X", i)
        end
      end
      log("")
      log("ZERO-WRITE offsets (candidates; boot path unwatched): " .. table.concat(free, " "))
    else
      local a, b = PL.ram(0x1000 + OFF), PL.ram(0x1080 + OFF)
      log(string.format("t=1400 +0x%02X: P1=%02X P2=%02X -> %s", OFF, a, b,
          (a == 0xA5 and b == 0xA5) and "SURVIVED" or "CLOBBERED"))
    end
    LOG:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_airfree loaded: " .. MODE)
