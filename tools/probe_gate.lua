local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE=ENV.TRACE
local WRAM=emu.memType.snesWorkRam
local t,needLoad=-1,true
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."uranus_vs_jupiter_v07.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then return end
  if t>=10 then emu.write(0x08B0,5,WRAM); emu.write(0x08B2,90,WRAM); emu.write(0x08B3,0xFF,WRAM)
    emu.write(0x8D,2,WRAM) end  -- disallowed mode
  if t==40 then io.open(TRACE.."cc_gate.txt","w"):write(string.format("stgL dirty=%02X tt=%02X%02X hits=%02X\n",
    emu.read(0x08D0,WRAM),emu.read(0x08D2,WRAM),emu.read(0x08D1,WRAM),emu.read(0x08B0,WRAM))):close(); emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("gate loaded")
