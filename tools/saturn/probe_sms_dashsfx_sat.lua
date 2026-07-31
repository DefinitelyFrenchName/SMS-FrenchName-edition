
-- probe_sms_dashsfx.lua — measure SMS's native $78 sfx values for jump,
-- forward dash (66) and backdash (44) with an untransformed character.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/dashsfx_sat.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
-- log every write to DP $78 (both mirrors) with P1 act
for _, a in ipairs({0x7E0078, 0x000078}) do
  emu.addMemoryCallback(function(addr, value)
    if t > 0 and (value or 0) ~= 0 then
      log(string.format("t=%d $78 <= %02X act=%02X", t, value, ram(0x1001)))
    end
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
local buttons = {}
emu.addEventCallback(function()
  emu.setInput(PL.pad(buttons), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  -- P2 park
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
    wr(0x10A1, 0x30); wr(0x10A2, 0x01)
  end
  -- jump
  if t == 100 then buttons = {up=true}; log("-- jump") end
  if t == 106 then buttons = {} end
  -- forward dash 66
  if t == 200 then log("-- fwd dash 66 (hold)") end
  if t >= 200 and t <= 201 then buttons = {right=true} end
  if t >= 202 and t <= 204 then buttons = {} end
  if t >= 205 and t <= 240 then buttons = {right=true} end
  if t == 241 then buttons = {} end
  if t == 215 or t == 235 then log(string.format("  t=%d act=%02X", t, ram(0x1001))) end
  -- backdash 44
  if t == 300 then log("-- backdash 44") end
  if t == 300 or t == 301 then buttons = {left=true} end
  if t == 302 or t == 303 or t == 304 then buttons = {} end
  if t == 305 or t == 306 or t == 307 then buttons = {left=true} end
  if t == 308 then buttons = {} end
  if t == 420 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)
print("dashsfx loaded")
