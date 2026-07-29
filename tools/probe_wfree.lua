-- watch reads+writes to 0x0900-0x09FF over a match with action; report any access
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE=ENV.TRACE
local WRAM=emu.memType.snesWorkRam
local FALSE={a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false}
local t,needLoad=-1,true
local touched={}
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."uranus_vs_jupiter_v07.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
for _,cb in ipairs({emu.callbackType.read, emu.callbackType.write}) do
  emu.addMemoryCallback(function(addr) if t>=0 then touched[addr]=true end end,
    cb, 0x0900, 0x09FF, emu.cpuType.snes, emu.memType.snesWorkRam)
end
emu.addEventCallback(function()
  if t<0 then emu.setInput(FALSE,0,0); emu.setInput(FALSE,0,1); return end
  local p1={}; for k,v in pairs(FALSE) do p1[k]=v end
  if t%20<3 then p1.down=true; p1.y=true elseif t%20<6 then p1.right=true; p1.x=true end
  emu.setInput(FALSE,0,1); emu.setInput(p1,0,0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t<0 then return end
  if t==400 then local n=0; local lo,hi=0x1000,0
    for a in pairs(touched) do n=n+1; if a<lo then lo=a end; if a>hi then hi=a end end
    io.open(TRACE.."probe_wfree.txt","w"):write(string.format("0x0900-0x09FF: %d addrs touched (range %04X-%04X)\n",n,lo,hi)):close()
    emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("wfree loaded")
