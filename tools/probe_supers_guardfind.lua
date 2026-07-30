-- probe_supers_guardfind.lua — locate the guard-success decision in Super S.
-- Reruns the A/B cases from probe_saturn_unblockable.lua and logs every write to the
-- DEFENDER's actionID ($1081) with the writer PC:
--   far 5HK @ 40px  -> HIT through held guard   (the bug)
--   far 5HK @ 48px  -> BLOCKED                  (guard works)
--   5LP     @ 40px  -> BLOCKED                  (control)
-- The blockstun writer (0x0E/0x0F) vs hit writer (0x10+) PCs bracket the decision
-- branch; the pre-block pose writer (0x0C/0x0D) is the proximity-guard trigger.
-- ROM=<Super S> tools/run.sh tools/probe_supers_guardfind.lua 300 -> traces/supers_guardfind.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "supers_guardfind.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local ATTEMPTS = {
  { btn = "a", dist = 40, tag = "5HK@40(unblk)" },
  { btn = "a", dist = 48, tag = "5HK@48(blocked)" },
  { btn = "y", dist = 40, tag = "5LP@40(control)" },
}
local idx, t, needLoad = 1, -1, true
local PRESS = 240

local function pcstr()
  local ok, st = pcall(emu.getState)
  if not ok then return "?" end
  local pc = st["cpu.pc"] or st["snes.cpu.pc"]
  local k  = st["cpu.k"]  or st["snes.cpu.k"]
  if pc == nil then return "?" end
  return string.format("%02X:%04X", k or 0, pc)
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)

-- every write to defender actionID, with writer PC
emu.addMemoryCallback(function(addr, value)
  if t >= PRESS - 20 and ATTEMPTS[idx] then
    log(string.format("[%s] t=%03d WRITE 1081 <= %02X @ %s (p1act=%02X p1step=%02X d=%d)",
      ATTEMPTS[idx].tag, t, value or -1, pcstr(), ram(0x1001), ram(0x1002),
      (ram(0x10A1) + 256 * ram(0x10A2)) - (ram(0x1021) + 256 * ram(0x1022))))
  end
end, emu.callbackType.write, 0x1081, 0x1081, emu.cpuType.snes, emu.memType.snesWorkRam)

-- every write to defender pending-hit code (+0x47): the attack-side verdict.
-- code 2/4 -> block reaction, 6+ -> hit reaction (victim applier $C1:0E2B tables).
emu.addMemoryCallback(function(addr, value)
  if t >= PRESS - 20 and ATTEMPTS[idx] and (value or 0) ~= 0 then
    log(string.format("[%s] t=%03d WRITE 10C7 <= %02X @ %s (p2_16=%02X p2_54=%02X p2act=%02X)",
      ATTEMPTS[idx].tag, t, value or -1, pcstr(), ram(0x1096), ram(0x10D4), ram(0x1081)))
  end
end, emu.callbackType.write, 0x10C7, 0x10C7, emu.cpuType.snes, emu.memType.snesWorkRam)

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
    local x = px + cur.dist
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
  end
  if t == PRESS + 60 then
    log(string.format("[%s] END p2act=%02X", cur.tag, ram(0x1081)))
    idx = idx + 1
    if not ATTEMPTS[idx] then log("DONE"); emu.stop(0) end
    needLoad = true; t = -1
  end
end, emu.eventType.endFrame)
print("probe_supers_guardfind loaded")
