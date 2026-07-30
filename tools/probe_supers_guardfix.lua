-- probe_supers_guardfix.lua — A/B validation of the one-byte guard fix for Saturn's
-- unblockable far kicks. Hypothesis: her far 5HK/5LK startup pose records ($84:9209
-- + 4*pose, bytes [cel, hit, hurt, coll]) carry hit=00 where well-formed moves carry a
-- zero-size "threat marker" box (e.g. 0x1B) that arms the opponent's proximity guard.
-- Runs far 5HK and far 5LK, each unpatched then with the pose-record THREAT CLASS
-- (byte0, read into +0x18) poked 00->09 (pose 0x20 @ file 0x049289, 0x1D @ 0x04927D).
-- Expect: 5HK HIT -> BLOCKED. 5LK tested at 24px (inside its <34px reach).
-- ROM=<Super S> tools/run.sh tools/probe_supers_guardfix.lua 400 -> traces/supers_guardfix.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "supers_guardfix.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local FIX_5HK = 0x049289  -- pose 0x20 byte0 (threat class)
local FIX_5LK = 0x04927D  -- pose 0x1D byte0 (threat class)

local ATTEMPTS = {
  { btn = "a", dist = 40, patch = nil,     tag = "5HK@40 vanilla " },
  { btn = "a", dist = 40, patch = FIX_5HK, tag = "5HK@40 patched " },
  { btn = "b", dist = 24, patch = nil,     tag = "5LK@24 vanilla " },
  { btn = "b", dist = 24, patch = FIX_5LK, tag = "5LK@24 patched " },
  { btn = "a", dist = 40, patch = FIX_5HK, tag = "5HK@40 patched NOBLOCK", noblock = true },
  { btn = "b", dist = 24, patch = FIX_5LK, tag = "5LK@24 patched NOBLOCK", noblock = true },
}
local idx, t, needLoad = 1, -1, true
local PRESS = 240

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
    -- reset both fix bytes to vanilla, then apply this attempt's patch
    emu.write(FIX_5HK, 0x00, PL.PRG)
    emu.write(FIX_5LK, 0x00, PL.PRG)
    local cur = ATTEMPTS[idx]
    if cur and cur.patch then emu.write(cur.patch, 0x09, PL.PRG) end
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local cur = ATTEMPTS[idx]
  local p1 = PL.pad()
  if cur and t >= PRESS and t <= PRESS + 1 then p1 = PL.pad({ [cur.btn] = true }) end
  local p2 = (t >= 200 and cur and not cur.noblock) and PL.pad({ right = true }) or PL.pad()
  emu.setInput(p1, 0, 0); emu.setInput(p2, 0, 1)
end, emu.eventType.inputPolled)

local sawBlockstun, sawHit, sawPose = false, false, false
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  local cur = ATTEMPTS[idx]
  if not cur then return end
  if t == PRESS - 12 then
    local px = ram(0x1021) + 256 * ram(0x1022)
    local x = px + cur.dist
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
  end
  if t == PRESS + 5 then
    log(string.format("%s   [dbg] rom5HK=%02X rom5LK=%02X p1hit40=%02X p1pose=%02X",
      cur.tag, PL.rom(FIX_5HK), PL.rom(FIX_5LK), ram(0x1040), ram(0x1005)))
  end
  if t >= PRESS then
    local a2 = ram(0x1081)
    if a2 == 0x0C or a2 == 0x0D then sawPose = true end
    if a2 == 0x0E or a2 == 0x0F then sawBlockstun = true end
    if a2 >= 0x10 and a2 <= 0x16 then sawHit = true end
  end
  if t == PRESS + 60 then
    local verdict = sawHit and "HIT" or sawBlockstun and "BLOCKED" or sawPose and "POSE-ONLY(whiff)" or "WHIFF"
    log(string.format("%s pose=%s blockstun=%s hit=%s -> %s",
      cur.tag, tostring(sawPose), tostring(sawBlockstun), tostring(sawHit), verdict))
    sawBlockstun, sawHit, sawPose = false, false, false
    idx = idx + 1
    if not ATTEMPTS[idx] then log("DONE"); emu.stop(0) end
    needLoad = true; t = -1
  end
end, emu.eventType.endFrame)
print("probe_supers_guardfix loaded")
