local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
pcall(dofile, ENV.TOOLS .. "probe_shot_cfg.lua")
local STATE = SHOTSTATE or "venus_vs_jupiter_clean.mss"
local OUT = SHOTOUT or "cc_shot"
local AT = SHOTAT or 40
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then local f = io.open(TRACE..STATE,"rb") if not f then print("probe_shot.lua: cannot open " .. (TRACE..STATE)) emu.stop(1) return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then return end
  if t==AT then
    local f = io.open(TRACE..OUT..".png","wb")
    if not f then print("probe_shot.lua: cannot open " .. (TRACE..OUT..".png")) emu.stop(1) return end
    f:write(emu.takeScreenshot()); f:close()
    emu.stop(0)
  end
  t=t+1
end, emu.eventType.endFrame)
print("probe_shot loaded")
