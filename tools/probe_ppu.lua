local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE=ENV.TRACE
local t,needLoad=-1,true
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."venus_vs_jupiter_clean.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then return end
  if t==30 then
    local st=emu.getState()
    local log=io.open(TRACE.."probe_ppu.txt","w")
    log:write("bgMode="..tostring(st["ppu.bgMode"]).."\n")
    for i=0,3 do
      log:write(string.format("BG%d chrAddr=%s tilemapAddr=%s\n", i+1,
        tostring(st["ppu.layers["..i.."].chrAddress"]), tostring(st["ppu.layers["..i.."].tilemapAddress"]))) end
    log:close(); emu.stop(0)
  end
  t=t+1
end, emu.eventType.endFrame)
print("ppu loaded")
