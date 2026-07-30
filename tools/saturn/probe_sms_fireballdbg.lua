-- probe_sms_fireballdbg.lua — why doesn't the spawned fireball's proc run?
-- Exec counters along the chain: projectile-loop dispatch $C1:1708, mini-stub
-- $C1:15C8, tramp3 $EF:DB30, proc $EF:280B; plus proj slot state.
-- ROM=build/saturn/SailorMoonS_saturn_smoke.sfc tools/run.sh tools/saturn/probe_sms_fireballdbg.lua 150
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/fireballdbg.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local n = { loop = 0, stub = 0, tramp = 0, proc = 0 }

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local function counter(tag)
  return function() if t >= 140 then n[tag] = n[tag] + 1 end end
end
emu.addMemoryCallback(counter("loop"), emu.callbackType.exec, 0xC11708, 0xC11708, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(counter("stub"), emu.callbackType.exec, 0xC115C8, 0xC115C8, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(counter("tramp"), emu.callbackType.exec, 0xEFDB30, 0xEFDB30, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(counter("proc"), emu.callbackType.exec, 0xEF280B, 0xEF280B, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local p1 = PL.pad()
  local q = 140
  if t == q or t == q + 1 then p1 = PL.pad({ down = true })
  elseif t == q + 2 or t == q + 3 then p1 = PL.pad({ down = true, right = true })
  elseif t == q + 4 or t == q + 5 then p1 = PL.pad({ right = true })
  elseif t == q + 6 or t == q + 7 then p1 = PL.pad({ right = true, y = true }) end
  emu.setInput(p1, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1000 + o, 0) end
  end
  if t >= 150 and t <= 230 and t % 10 == 0 then
    log(string.format("t=%03d proj id=%02X act=%02X | loop=%d stub=%d tramp=%d proc=%d",
      t, ram(0x1100), ram(0x1101), n.loop, n.stub, n.tramp, n.proc))
  end
  if t == 232 then log("DONE"); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_sms_fireballdbg loaded")
