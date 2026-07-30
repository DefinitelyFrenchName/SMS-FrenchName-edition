-- probe_saturn_unblockable.lua — verify Super S Saturn's notorious property: her FAR
-- 5LK / 5HK reportedly never trigger the opponent's guard (newchallenger.net).
-- Per attempt: reload fixture, park P2 at a swept distance HOLDING AWAY (block input),
-- Saturn presses one kick; classify BLOCKED (P2 reaches 0x0C-0x0F) vs HIT (0x10-0x16)
-- vs WHIFF. Control: the same sweep with 5LP (blockable) proves the rig detects guard.
-- ROM=<Super S> tools/run.sh tools/saturn/probe_saturn_unblockable.lua 400 -> traces/saturn/saturn_unblk.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/saturn_unblk.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local ATTEMPTS = {}
for _, c in ipairs({ false, true }) do            -- stand-block, crouch-block
  for _, b in ipairs({ "a", "y" }) do             -- 5HK, 5LP control
    for _, d in ipairs({ 36, 40, 44 }) do
      ATTEMPTS[#ATTEMPTS + 1] = { btn = b, dist = d, crouch = c }
    end
  end
end
local idx, t, needLoad = 1, -1, true
local PRESS = 240

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn/saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local cur = ATTEMPTS[idx]
  local p1 = PL.pad()
  if cur and t >= PRESS and t <= PRESS + 1 then p1 = PL.pad({ [cur.btn] = true }) end
  -- P2 on the right blocks from t=200: away (stand) or down-away (crouch) per attempt
  local hold = cur and (cur.crouch and { right = true, down = true } or { right = true }) or {}
  local p2 = (t >= 200) and PL.pad(hold) or PL.pad()
  emu.setInput(p1, 0, 0); emu.setInput(p2, 0, 1)
end, emu.eventType.inputPolled)

local sawBlock, sawHit, sawBlockstun = false, false, false
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
  if t == PRESS + 2 then cur.p1act = ram(0x1001) end
  if t >= PRESS then
    local a2 = ram(0x1081)
    if a2 == 0x0C or a2 == 0x0D then sawBlock = true end
    if a2 == 0x0E or a2 == 0x0F then sawBlockstun = true end
    if a2 >= 0x10 and a2 <= 0x16 then sawHit = true end
  end
  if t == PRESS + 60 then
    local verdict = sawHit and (sawBlock and "HIT (guard came out but lost?)" or "HIT-NO-GUARD")
                    or sawBlockstun and "BLOCKED"
                    or sawBlock and "GUARD-POSE-ONLY"
                    or "WHIFF"
    log(string.format("%s %s d=%3d p1act=%02X: preblock=%s blockstun=%s hit=%s -> %s",
      cur.btn:upper(), cur.crouch and "CRB" or "STB", cur.dist, cur.p1act or 0, tostring(sawBlock), tostring(sawBlockstun), tostring(sawHit), verdict))
    sawBlock, sawHit, sawBlockstun = false, false, false
    idx = idx + 1
    if not ATTEMPTS[idx] then log("DONE"); emu.stop(0) end
    needLoad = true; t = -1
  end
end, emu.eventType.endFrame)
print("probe_saturn_unblockable loaded")
