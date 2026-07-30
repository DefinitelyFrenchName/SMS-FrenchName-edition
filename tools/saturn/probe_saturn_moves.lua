-- probe_saturn_moves.lua — first Saturn frame data (Super S). Reloads the
-- saturn_vs_uranus_supers.mss fixture per attempt, presses one button, and logs
-- P1 act transitions + hit/hurt box indices per frame to derive S/A/R.
-- Buttons swept: Y(LP) X(HP) B(LK) A(HK) at the fixture's spacing (128px = far),
-- then the same with P2 parked close (32px) for close variants.
-- ROM=<Super S> tools/run.sh tools/saturn/probe_saturn_moves.lua 240 -> traces/saturn_moves.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/saturn_moves.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local ATTEMPTS = {}
for _, close in ipairs({ false, true }) do
  for _, b in ipairs({ "y", "x", "b", "a" }) do
    ATTEMPTS[#ATTEMPTS + 1] = { btn = b, close = close }
  end
end
local idx = 1
local t, needLoad = -1, true
local PRESS = 240  -- fixture: intro ends ~t=68, clock live from ~t=186

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn/saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local cur = ATTEMPTS[idx]
  local b = PL.pad()
  if cur and t >= PRESS and t <= PRESS + 1 then b = PL.pad({ [cur.btn] = true }) end
  emu.setInput(b, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

local rec, prevAct = {}, nil
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  local cur = ATTEMPTS[idx]
  if not cur then return end
  if cur.close and t == PRESS - 10 then
    local px = ram(0x1021) + 256 * ram(0x1022)
    local x = px + 32
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
  end
  if t >= PRESS - 1 and t <= PRESS + 70 then
    local a, hb, hub, a2 = ram(0x1001), ram(0x1040), ram(0x1041), ram(0x1081)
    rec[#rec + 1] = { t = t - PRESS, a = a, hb = hb, hub = hub, a2 = a2,
                      cls = ram(0x1044), dmg = ram(0x1045) }
  end
  if t == PRESS + 71 then
    -- summarize: act sequence + active window (hb ~= 0)
    local seq, lastA = {}, nil
    local firstAct, lastAct, endAct = nil, nil, nil
    for _, r in ipairs(rec) do
      if r.a ~= lastA then seq[#seq + 1] = string.format("%02X@%d", r.a, r.t); lastA = r.a end
      if r.hb ~= 0 and not firstAct then firstAct = r.t end
      if r.hb ~= 0 then lastAct = r.t end
    end
    for _, r in ipairs(rec) do
      if firstAct and r.t > (lastAct or 0) and r.a == 0x00 and not endAct then endAct = r.t end
    end
    local p2hit = false
    local clsmax, dmgseen = 0, 0
    for _, r in ipairs(rec) do
      if r.a2 >= 0x0E and r.a2 <= 0x16 then p2hit = true end
      if r.a ~= 0x00 and r.cls > clsmax then clsmax = r.cls end
      if r.a ~= 0x00 and r.dmg > dmgseen then dmgseen = r.dmg end
    end
    log(string.format("%s %-5s: acts[%s] active=%s..%s neutral@%s p2hit/block=%s cls=%02X dmg=%d",
      cur.close and "CLOSE" or "FAR ", cur.btn:upper(),
      table.concat(seq, " "), tostring(firstAct), tostring(lastAct), tostring(endAct), tostring(p2hit), clsmax, dmgseen))
    rec = {}; idx = idx + 1
    if not ATTEMPTS[idx] then log("DONE"); emu.stop(0) end
    needLoad = true; t = -1
  end
end, emu.eventType.endFrame)
print("probe_saturn_moves loaded")
