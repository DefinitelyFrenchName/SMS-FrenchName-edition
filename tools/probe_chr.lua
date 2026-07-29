local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE=ENV.TRACE
pcall(dofile,ENV.TOOLS .. "probe_chr_cfg.lua")
pcall(dofile,ENV.TOOLS .. "probe_chr_cfg.lua")
pcall(dofile,ENV.TOOLS .. "probe_chr_cfg.lua")
pcall(dofile,ENV.TOOLS .. "probe_chr_cfg.lua")
pcall(dofile,ENV.TOOLS .. "probe_chr_cfg.lua")
local ST=CHRSTATE or "venus_vs_jupiter_clean.mss"
local t,needLoad=-1,true
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE..ST,"rb"); if not f then print("NOFILE "..ST); emu.stop(1); return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then return end
  if t==30 then
    -- read BG3 CHR tiles 0xC7-0xD2 (word 0x5000+t*8), count nonzero bytes
    local nz=0
    for tile=0xC7,0xD2 do
      for w=0,7 do local wa=0x5000+tile*8+w
        local v=emu.read(wa*2, emu.memType.snesVideoRam)+emu.read(wa*2+1, emu.memType.snesVideoRam)*256
        if v~=0 then nz=nz+1 end end
    end
    io.open(TRACE.."probe_chr.txt","a"):write(string.format("%s: BG3 CHR 0xC7-0xD2 nonzero_words=%d\n",ST,nz)):close()
    emu.stop(0)
  end
  t=t+1
end, emu.eventType.endFrame)
print("chr loaded")
