-- replicate hud_boxes.lua projectile drawing EXACTLY; BEFORE=draw garbage hurt, AFTER=skip.
pcall(dofile,"/Users/koneko/Developer/SailorMoonS/tools/probe_vfix_cfg.lua")
local TRACE="/Users/koneko/Developer/SailorMoonS/tools/../traces/"
local WRAM=emu.memType.snesWorkRam; local BUS=emu.memType.snesMemory
local FALSE={a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false}
local t,needLoad=-1,true
local function r8(a) return emu.read(a,BUS) end
local function r16(a) return r8(a)+256*r8(a+1) end
local function sg(v) return v>127 and v-256 or v end
local PT_HIT,PT_HURT=0x8AC1F1,0x8AC229
local function drawbox(sx,sy,addr,col)
  local xo,w=sg(r8(addr)),r8(addr+1); local yo,h=sg(r8(addr+4)),r8(addr+5)
  if h==0 or w==0 then return end
  emu.drawRectangle(sx+xo,sy+yo,w,h,0xC8000000+col,true); emu.drawRectangle(sx+xo,sy+yo,w,h,col,false)
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
  if t>=1 and t<95 then emu.write(0x10A1,0x30,WRAM) end
  pcall(emu.selectDrawSurface, emu.drawSurface.consoleScreen)
  local pid=emu.read(0x1100,WRAM)
  if pid==0x18 then
    local camx=r16(0x7E0A00)%65536; -- read WRAM cam via bus mirror? use WRAM
    camx=emu.read(0x0A00,WRAM)+emu.read(0x0A01,WRAM)*256
    local camy=emu.read(0x0A02,WRAM)+emu.read(0x0A03,WRAM)*256
    local x=emu.read(0x1121,WRAM)+emu.read(0x1122,WRAM)*256
    local y=emu.read(0x1125,WRAM)+emu.read(0x1126,WRAM)*256
    local sx,sy=(x-camx)%512,(y-camy)%512
    local hit=0x8A0000+r16(PT_HIT+0x18*2)
    local hurt=0x8A0000+r16(PT_HURT+0x18*2)  -- GARBAGE for obj 0x18
    local hb,hub=emu.read(0x1140,WRAM),emu.read(0x1141,WRAM)
    if BEFORE and hub~=0 then drawbox(sx,sy,hurt+hub*16,0x40C040); drawbox(sx,sy,hurt+hub*16+8,0xC0FF00) end
    if hb~=0 then drawbox(sx,sy,hit+hb*8,0xE03028) end
    emu.drawString(4,20,string.format("%s t=%d hb=%d hub=%d",BEFORE and "BEFORE(garbage hurt)" or "AFTER(fix)",t,hb,hub),0xFFFF00,0)
  end
  if t==100 then local f=io.open(TRACE..(VOUT or "vfix.png"),"wb"); f:write(emu.takeScreenshot()); f:close(); emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("vfix loaded")
