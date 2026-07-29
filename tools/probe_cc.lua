local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local t, needLoad = -1, true
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
local log = io.open(TRACE.."probe_cc.txt","w")
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."venus_vs_jupiter_clean.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then emu.setInput(FALSE,0,0); emu.setInput(FALSE,0,1); return end
  local p1={}; for k,v in pairs(FALSE) do p1[k]=v end
  -- Venus 2LP (down+Y) then 2HP (down+X) chain
  if t>=60 and t<63 then p1.down=true; p1.y=true
  elseif t>=63 and t<77 then p1.down=true
  elseif t>=77 and t<80 then p1.down=true; p1.x=true
  elseif t>=80 and t<95 then p1.down=true end
  emu.setInput(FALSE,0,1); emu.setInput(p1,0,0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t<0 then return end
  if t==5 then emu.write(0x1021,0xE8,WRAM) end
  if t>=60 and t<=100 and t%4==0 then
    log:write(string.format("t=%d p2hp=%02X my_hits(P2def)=%d ttl=%d shown=%d\n",
      t, r(0x10C9), r(0x08B0), r(0x08B2), r(0x08B3))); log:flush()
  end
  if t==92 then local f=io.open(TRACE.."cc_full_shot.png","wb"); f:write(emu.takeScreenshot()); f:close() end
  if t==110 then log:close(); emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("probe_cc loaded")
