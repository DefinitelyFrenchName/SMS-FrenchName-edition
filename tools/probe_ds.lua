local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE=ENV.TRACE
local WRAM=emu.memType.snesWorkRam
local FALSE={a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false}
local t,needLoad=-1,true
local log=io.open(TRACE.."probe_ds.txt","w")
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE..(DSSTATE or "neptune_vs_jupiter.mss"),"rb"); if not f then print("NOFILE"); emu.stop(1); return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then emu.setInput(FALSE,0,0);emu.setInput(FALSE,0,1);return end
  local p1={}; for k,v in pairs(FALSE) do p1[k]=v end
  -- 214 (down, down-back, back) + LP(Y). Neptune assumed P1 (left), back=left.
  if t==60 then p1.down=true
  elseif t==63 then p1.down=true; p1.left=true
  elseif t==66 then p1.left=true
  elseif t==68 then p1.left=true; p1.y=true
  elseif t==70 then p1.y=true end
  emu.setInput(FALSE,0,1); emu.setInput(p1,0,0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t<0 then return end
  if t==1 then log:write(string.format("mode=%02X p1char=%02X p2char=%02X p1x=%02X p2x=%02X\n",
    emu.read(0x8D,WRAM),emu.read(0x1000,WRAM),emu.read(0x1080,WRAM),emu.read(0x1021,WRAM),emu.read(0x10A1,WRAM))) end
  -- log projectile slot P1 ($1100): objid, hitbox, hurtbox, coll, y-pos
  if t>=60 and t<=200 then
    local pid=emu.read(0x1100,WRAM)
    if pid~=0 and pid<0x80 then
      log:write(string.format("t=%d objid=%02X hb=%02X hub=%02X cb=%02X ypix=%02X act=%02X\n",
        t, pid, emu.read(0x1140,WRAM), emu.read(0x1141,WRAM), emu.read(0x1142,WRAM),
        emu.read(0x1125,WRAM), emu.read(0x1101,WRAM)))
    end
  end
  if t==200 then log:close(); emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("ds loaded")
