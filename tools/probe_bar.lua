local TRACE="/Users/koneko/Developer/SailorMoonS/tools/../traces/"
local WRAM=emu.memType.snesWorkRam; local VRAM=emu.memType.snesVideoRam
local t,needLoad=-1,true
local function cw(w) return emu.read(w*2,VRAM)+emu.read(w*2+1,VRAM)*256 end
local function p2bar(lbl) local o={}; for i=18,29 do o[#o+1]=string.format("%04X",cw(0x1060+i)) end
  return lbl.." P2top: "..table.concat(o," ") end
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."uranus_vs_jupiter_v07.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then return end
  local log=io.open(TRACE.."probe_bar.txt","a")
  if t==30 then emu.write(0x10C9,0x26,WRAM) end   -- struct only -> producer drains bar
  if t==75 then log:write(p2bar("DAMAGED(0x26) disp="..string.format("%02X",emu.read(0x0801,WRAM))).."\n") end
  if t==80 then emu.write(0x10C9,0x60,WRAM); emu.write(0x0801,0x60,WRAM) end   -- value-only heal (current regen)
  if t==110 then log:write(p2bar("HEALED-valueonly disp="..string.format("%02X",emu.read(0x0801,WRAM))).."\n")
    local f=io.open(TRACE.."bar_healed.png","wb"); f:write(emu.takeScreenshot()); f:close(); log:close(); emu.stop(0) end
  log:close(); t=t+1
end, emu.eventType.endFrame)
print("bar loaded")
