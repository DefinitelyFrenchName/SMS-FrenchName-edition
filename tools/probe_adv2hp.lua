-- probe_adv2hp.lua — issue #28: measure Uranus 2HP on-hit advantage by frame-advance,
-- straight from RAM acts (independent of the framedata module it validates).
-- Replicates the T2H scenario: uranus_vs_jupiter_tm.mss, point-blank poke @5, 2HP @60.
-- Advantage = (P2 first free frame) - (P1 first free frame); negative = P1 recovers later.
-- ROM=<v0.7-family> tools/run.sh tools/probe_adv2hp.lua 60   -> traces/adv2hp.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "adv2hp.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local r, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local p1free, p2hit, p2free = nil, nil, nil

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_tm.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local b = PL.pad()
  if t >= 60 and t <= 61 then b = PL.pad({ down = true, x = true })
  elseif t >= 62 and t <= 63 then b = PL.pad({ down = true }) end
  emu.setInput(b, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 5 then wr(0x1021, 0xE8) end
  local a1, a2 = r(0x1001), r(0x1081)
  -- "free" = first ACTIONABLE frame, same set for both players (neutral/walk/crouch/
  -- block-ready/etc). 2HP recovers INTO crouch (act 0x03) — requiring exactly 0x00
  -- undercounts P1's advantage by the uncrouch animation.
  local function actionable(a) return a <= 0x04 or a == 0x0C or a == 0x0D or a == 0x21 end
  if t > 65 then
    if not p2hit and a2 >= 0x10 and a2 <= 0x16 then p2hit = t end
    if p2hit and not p1free and a1 ~= 0x55 and a1 ~= 0x56 and actionable(a1) then p1free = t end
    if p2hit and not p2free and actionable(a2) then p2free = t end
  end
  if t % 1 == 0 and t >= 58 and t <= 130 then
    log(string.format("t=%d a1=%02X a2=%02X", t, a1, a2))
  end
  if (p1free and p2free) or t > 200 then
    if p1free and p2free then
      log(string.format("RESULT p2hit=%d p1free=%d p2free=%d adv=%+d", p2hit, p1free, p2free, p2free - p1free))
      emu.stop(0)
    else
      log(string.format("INCOMPLETE p2hit=%s p1free=%s p2free=%s", tostring(p2hit), tostring(p1free), tostring(p2free)))
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
print("probe_adv2hp loaded")
