local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE=ENV.TRACE
pcall(dofile,ENV.TOOLS .. "probe_soak_cfg.lua")
local WRAM=emu.memType.snesWorkRam
local FALSE={a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false}
local t,needLoad=-1,true
local sig=0
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."uranus_vs_jupiter_v07.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then emu.setInput(FALSE,0,0);emu.setInput(FALSE,0,1);return end
  local p1={}; for k,v in pairs(FALSE) do p1[k]=v end
  if t%30<3 then p1.down=true;p1.y=true elseif t%30<6 then p1.down=true;p1.x=true elseif t%30<9 then p1.right=true end
  emu.setInput(FALSE,0,1); emu.setInput(p1,0,0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t<0 then return end
  -- accumulate a rolling signature of gameplay state each frame
  for a=0x1000,0x10FF do sig=(sig*31 + emu.read(a,WRAM))%2147483647 end
  if t==1500 then io.open(TRACE..(SOAKOUT or "soak.txt"),"w"):write("sig="..sig.."\n"):close(); emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("soak loaded")
