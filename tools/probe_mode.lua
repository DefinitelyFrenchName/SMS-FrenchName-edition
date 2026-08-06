local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
pcall(dofile, ENV.TOOLS .. "probe_mode_cfg.lua")  -- optional STATE override (issue #49)
local st = STATE or "uranus_vs_jupiter_v07.mss"
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE..st,"rb"); if not f then print("probe_mode.lua: cannot open "..TRACE..st); emu.stop(1); return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if t==5 then
    local __f = io.open(TRACE.."probe_mode.txt","a") if not __f then print("probe_mode.lua: cannot open " .. (TRACE.."probe_mode.txt")) emu.stop(1) return end __f:write(string.format("%s: game_mode=%02X\n", st, emu.read(0x8D, emu.memType.snesWorkRam))):close()
    emu.stop(0)
  end
  if t>=0 then t=t+1 end
end, emu.eventType.endFrame)
print("probe_mode loaded")
