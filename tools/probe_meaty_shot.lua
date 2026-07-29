local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local ROOT=ENV.TOOLS; local TRACE=ROOT.."../traces/"
local C0=dofile(ROOT.."training/const.lua"); local FALSE=C0.FALSE_PAD
local WRAM=emu.memType.snesWorkRam; local FV=115
local function pl1(t) local kf={{10,{down=true}},{60,{down=true,y=true}},{62,{down=true}},{77,{down=true,x=true}},{80,{down=true}},{95,{}},{97,{right=true}},{98,{}},{99,{right=true}},{101,{}},{FV,{down=true,y=true}},{FV+2,{down=true}}}
  local b={}; for _,e in ipairs(kf) do if e[1]<=t then b=e[2] end end
  local o={}; for k,v in pairs(FALSE) do o[k]=v end; for k,v in pairs(b) do o[k]=v end; return o end
local t,needLoad=-1,true
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."uranus_vs_jupiter_v07.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
emu.addEventCallback(function() if t<0 then emu.setInput(FALSE,0,0);emu.setInput(FALSE,0,1);return end
  emu.setInput(FALSE,0,1); emu.setInput(pl1(t),0,0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t<0 then return end
  if t==5 then emu.write(0x1021,0xE8,WRAM) end
  if t==125 then local f=io.open(TRACE.."cc_meaty_shot.png","wb"); f:write(emu.takeScreenshot()); f:close() end
  if t==140 then emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("meaty_shot loaded")
