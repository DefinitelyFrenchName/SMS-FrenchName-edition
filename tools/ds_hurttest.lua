local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE=ENV.TRACE
local WRAM=emu.memType.snesWorkRam
local loaded,t=false,-1
local function ram(a) return emu.read(a,WRAM) end
local log=io.open(TRACE.."ds_hurttest.txt","w")
local P1={[8]={down=true},[11]={down=true,left=true},[14]={left=true,y=true},[17]={}}
local cur,applied={},-1
local last_alive=-1
emu.addMemoryCallback(function()
  if not loaded then local f=io.open(TRACE.."neptune_vs_jupiter.mss","rb");local ss=f:read("*a");f:close();emu.loadSavestate(ss);loaded=true;t=0 end
end,emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
emu.addEventCallback(function()
  if t>=0 then for k,v in pairs(P1) do if k<=t and k>applied then cur=v;applied=k end end end
  local base={a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false}
  local i1={};for k,v in pairs(base) do i1[k]=v end;for k,v in pairs(cur) do i1[k]=v end
  local i2={};for k,v in pairs(base) do i2[k]=v end
  if t>=18 then i2.x=((t%6)<3) end   -- P2 mashes 5HP into the fireball path
  emu.setInput(i2,0,1);emu.setInput(i1,0,0)
end,emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t<0 then return end
  local pid=ram(0x1100);local alive=(pid~=0 and pid<0x80)
  if alive then last_alive=t end
  if t<=75 then
    log:write(string.format("t=%03d Nep[act=%02X] proj=%s id=%02X X=%04X  P2[act=%02X hb=%02X hp=%02X]\n",
      t, ram(0x1001), alive and "LIVE" or "----", pid, ram(0x1121)+256*ram(0x1122), ram(0x1081), ram(0x10C0), ram(0x10C9)))
  end
  if t==75 then log:write("first spawn..last alive: see LIVE lines; last_alive="..last_alive.."\n");log:close();emu.stop(0) end
  t=t+1
end,emu.eventType.endFrame)
print("loaded")
