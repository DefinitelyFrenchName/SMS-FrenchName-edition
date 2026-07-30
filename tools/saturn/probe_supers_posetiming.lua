-- probe_supers_posetiming.lua — per-frame alignment of attacker hitbox activation vs
-- defender pre-block pose entry, Saturn far 5LP vs far 5HK (the unblockable), d=40px.
-- Logs p1 act/step/+0x40(hit idx)/+0x41 and p2 act/+0x47 each frame around the press.
-- ROM=<Super S> tools/run.sh tools/saturn/probe_supers_posetiming.lua 300 -> traces/saturn/supers_posetiming.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/supers_posetiming.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local ATTEMPTS = {
  { btn = "y", tag = "5LP" },
  { btn = "a", tag = "5HK" },
  { btn = "b", tag = "5LK" },
}
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
  local p2 = (t >= 200) and PL.pad({ right = true }) or PL.pad()
  emu.setInput(p1, 0, 0); emu.setInput(p2, 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  local cur = ATTEMPTS[idx]
  if not cur then return end
  if t == PRESS - 12 then
    local px = ram(0x1021) + 256 * ram(0x1022)
    local x = px + 40
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
  end
  if t >= PRESS - 2 and t <= PRESS + 24 then
    local d = (ram(0x10A1) + 256 * ram(0x10A2)) - (ram(0x1021) + 256 * ram(0x1022))
    log(string.format("[%s] t=%+03d p1: act=%02X step=%02X pose05=%02X cel18=%02X hit40=%02X hurt41=%02X | p2: act=%02X pend47=%02X d=%d",
      cur.tag, t - PRESS, ram(0x1001), ram(0x1002), ram(0x1005), ram(0x1018), ram(0x1040), ram(0x1041),
      ram(0x1081), ram(0x10C7), d))
  end
  if t == PRESS + 40 then
    log("")
    idx = idx + 1
    if not ATTEMPTS[idx] then log("DONE"); emu.stop(0) end
    needLoad = true; t = -1
  end
end, emu.eventType.endFrame)
print("probe_supers_posetiming loaded")
