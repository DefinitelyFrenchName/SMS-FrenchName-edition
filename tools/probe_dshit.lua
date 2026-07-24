local TRACE="/Users/koneko/Developer/SailorMoonS/tools/../traces/"
local WRAM=emu.memType.snesWorkRam
local FALSE={a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false}
local t,needLoad=-1,true
local log=io.open(TRACE.."probe_dshit.txt","w")
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
  -- keep P2 parked at the fireball's landing X (~0xEF) so descent+transition both overlap it
  if t>=1 and t<95 then emu.write(0x10A1,0xEF,WRAM); emu.write(0x10A2,0x00,WRAM) end
  local pid=emu.read(0x1100,WRAM)
  if pid==0x18 then
    log:write(string.format("t=%d act=%02X hb=%02X hub=%02X fx=%02X p2x=%02X p2hp=%02X p2act=%02X\n",
      t, emu.read(0x1101,WRAM), emu.read(0x1140,WRAM), emu.read(0x1141,WRAM),
      emu.read(0x1121,WRAM), emu.read(0x10A1,WRAM), emu.read(0x10C9,WRAM), emu.read(0x1081,WRAM)))
  end
  if t==115 then log:close(); emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("dshit loaded")
