local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE=ENV.TRACE
local WRAM=emu.memType.snesWorkRam; local BUS=emu.memType.snesMemory
local FALSE={a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false}
local t,needLoad=-1,true
local log=io.open(TRACE.."probe_ds2.txt","w")
-- Neptune hit table for obj 0x18: $8A:FD51. box entry = 8 bytes; y_off at +4, h at +5.
local function boxyoff(idx) if idx==0 then return "--","--" end
  local a=0xAFD51+idx*8
  local yo=emu.read(0x8A0000+idx*8+0xFD51, BUS); -- careful addressing
  return idx, "?" end
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."neptune_vs_jupiter.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then emu.setInput(FALSE,0,0);emu.setInput(FALSE,0,1);return end
  local p1={}; for k,v in pairs(FALSE) do p1[k]=v end
  if t==60 then p1.down=true elseif t==63 then p1.down=true;p1.left=true
  elseif t==66 then p1.left=true elseif t==68 then p1.left=true;p1.x=true elseif t==70 then p1.x=true end
  emu.setInput(FALSE,0,1); emu.setInput(p1,0,0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t<0 then return end
  if t>=76 and t<=260 then
    local pid=emu.read(0x1100,WRAM)
    if pid~=0 and pid<0x80 then
      log:write(string.format("t=%d act=%02X hb=%02X hub=%02X x=%02X%02X y=%02X\n",
        t, emu.read(0x1101,WRAM), emu.read(0x1140,WRAM), emu.read(0x1141,WRAM),
        emu.read(0x1122,WRAM), emu.read(0x1121,WRAM), emu.read(0x1125,WRAM)))
    else log:write(string.format("t=%d (no projectile)\n",t)) end
  end
  if t==260 then log:close(); emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("ds2 loaded")
