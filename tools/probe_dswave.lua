-- whiff (no target), trace BOTH projectile slots for 300 frames; flag if +0x40 ever uses 6/7/8
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE=ENV.TRACE
local WRAM=emu.memType.snesWorkRam
local FALSE={a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false}
local t,needLoad=-1,true
local log=io.open(TRACE.."probe_dswave.txt","w")
local sawTall=false
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."neptune_vs_jupiter.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then emu.setInput(FALSE,0,0);emu.setInput(FALSE,0,1);return end
  local p1={}; for k,v in pairs(FALSE) do p1[k]=v end
  if t==60 then p1.down=true elseif t==63 then p1.down=true;p1.left=true
  elseif t==66 then p1.left=true elseif t==68 then p1.left=true;p1.y=true elseif t==70 then p1.y=true end
  emu.setInput(FALSE,0,1); emu.setInput(p1,0,0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t<0 then return end
  if t>=1 and t<300 then emu.write(0x10A1,0x30,WRAM) end  -- keep P2 far right (whiff)
  for slot,base in ipairs({0x1100,0x1180}) do
    local pid=emu.read(base,WRAM)
    if pid~=0 and pid<0x80 and t>=76 then
      local hb=emu.read(base+0x40,WRAM)
      if hb>=6 and hb<=8 then sawTall=true end
      log:write(string.format("t=%d slot%d obj=%02X act=%02X hb=%02X hub=%02X x=%02X y=%02X\n",
        t,slot,pid,emu.read(base+0x01,WRAM),hb,emu.read(base+0x41,WRAM),emu.read(base+0x21,WRAM),emu.read(base+0x25,WRAM)))
    end
  end
  if t==300 then log:write("saw tall box (6-8) as +0x40: "..tostring(sawTall).."\n"); log:close(); emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("dswave loaded")
