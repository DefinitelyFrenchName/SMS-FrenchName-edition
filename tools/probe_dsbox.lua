local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE=ENV.TRACE
local WRAM=emu.memType.snesWorkRam; local BUS=emu.memType.snesMemory
local FALSE={a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false}
local t,needLoad=-1,true
local function sg(b) return b>127 and b-256 or b end
local function drawbox(sx,sy,idx,col)
  if idx==0 then return end
  local a=0x8AFD51+idx*8
  local xr=sg(emu.read(a,BUS)); local wr=emu.read(a+1,BUS); local yo=sg(emu.read(a+4,BUS)); local h=emu.read(a+5,BUS)
  if h==0 or wr==0 then return end
  emu.drawRectangle(sx+xr, sy+yo, wr, h, 0xC0000000+col, true)
  emu.drawRectangle(sx+xr, sy+yo, wr, h, col, false)
end
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
  pcall(emu.selectDrawSurface, emu.drawSurface.consoleScreen)
  local pid=emu.read(0x1100,WRAM)
  if pid==0x18 then
    local camx=emu.read(0x0A00,WRAM)+emu.read(0x0A01,WRAM)*256
    local camy=emu.read(0x0A02,WRAM)+emu.read(0x0A03,WRAM)*256
    local x=emu.read(0x1121,WRAM)+emu.read(0x1122,WRAM)*256
    local y=emu.read(0x1125,WRAM)+emu.read(0x1126,WRAM)*256
    local sx,sy=(x-camx)%512,(y-camy)%512
    drawbox(sx,sy,emu.read(0x1141,WRAM),0x00FF00)
    drawbox(sx,sy,emu.read(0x1140,WRAM),0xFF0000)
    emu.drawString(4,20,string.format("t=%d hb=%d hub=%d sx=%d sy=%d",t,emu.read(0x1140,WRAM),emu.read(0x1141,WRAM),sx,sy),0xFFFF00,0x000000)
  end
  if t==90 then local f=io.open(TRACE.."dsbox_descend.png","wb"); f:write(emu.takeScreenshot()); f:close() end
  if t==100 then local f=io.open(TRACE.."dsbox_trans.png","wb"); f:write(emu.takeScreenshot()); f:close(); emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("dsbox loaded")
