-- probe_p11_vs70.lua (patch 11): read $0070/$008D/$01FA in a VS match state (gate design).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 5 then
    local function r(a) return emu.read(a, emu.memType.snesWorkRam) end
    local __f = io.open(TRACE .. "p11_vs70.txt", "w") if not __f then print("probe_p11_vs70.lua: cannot open " .. (TRACE .. "p11_vs70.txt")) emu.stop(1) return end __f:write(string.format(
      "VS state: mode=%02X f0070=%02X f01FA=%02X\n", r(0x8D), r(0x70), r(0x1FA))):close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("probe_p11_vs70 loaded")
