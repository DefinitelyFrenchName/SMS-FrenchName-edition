-- probe_cancelgate.lua — issue #29: measure the 2HP→66 dash-cancel gate behaviourally.
-- Drives 2LP > 2HP (on hit) > buffered 66 on traces/uranus_vs_jupiter.mss (the suite
-- fixture) and logs the frame the dash (act 0x60) actually starts. The patch-1 gate
-- delays that frame: vanilla earliest, gate 0x05 = +5, gate 0x04 = +6 (mkpatch.py doc).
-- ROM=<any> tools/run.sh tools/probe_cancelgate.lua 60   -> traces/cancelgate.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "cancelgate.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local r, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local hit2hp, dashAt = nil, nil

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

-- 66 taps complete at t=93 — BEFORE vanilla's earliest cancel frame, so clean dashes
-- immediately while the gates hold it back (separates clean / 0x05 / 0x04 three ways)
local KF = { {10,{down=true}}, {60,{down=true,y=true}}, {62,{down=true}},
             {77,{down=true,x=true}}, {80,{down=true}},
             {89,{}}, {91,{right=true}}, {92,{}}, {93,{right=true}}, {95,{}} }
emu.addEventCallback(function()
  local best = {}
  for _, e in ipairs(KF) do if t >= 0 and e[1] <= t then best = e[2] end end
  emu.setInput(PL.pad(best), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 5 then wr(0x1021, 0xE8) end
  local a1, a2 = r(0x1001), r(0x1081)
  if t > 78 and not hit2hp and a2 >= 0x10 and a2 <= 0x16 then hit2hp = t end
  if hit2hp and not dashAt and a1 == 0x60 then dashAt = t end
  if t >= 82 and t <= 112 then log(string.format("t=%d a1=%02X a2=%02X", t, a1, a2)) end
  if dashAt or t > 160 then
    if dashAt then
      log(string.format("RESULT hit2hp=%d dashAt=%d delay=%d", hit2hp, dashAt, dashAt - hit2hp))
      emu.stop(0)
    else
      log(string.format("NO-DASH hit2hp=%s (dash never came out in window)", tostring(hit2hp)))
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
print("probe_cancelgate loaded")
