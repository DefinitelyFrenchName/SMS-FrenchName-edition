local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE=ENV.TRACE
local frames=0
emu.addEventCallback(function()
  frames=frames+1
  if frames==1200 then local f = assert(io.open(TRACE.."allpatches_title.png","wb"), "probe_title.lua: cannot open " .. (TRACE.."allpatches_title.png")); f:write(emu.takeScreenshot()); f:close(); emu.stop(0) end
end, emu.eventType.endFrame)
print("title loaded")
