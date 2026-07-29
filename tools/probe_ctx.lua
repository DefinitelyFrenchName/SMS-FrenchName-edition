local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local log = io.open(TRACE .. "probe_ctx.txt", "w")
local t, needLoad = -1, true
local prodFrames, uplFrames = {}, {}
local function sl() local ok,st=pcall(emu.getState); return ok and (st["ppu.scanline"] or -1) or -1 end
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."venus_vs_jupiter_clean.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
-- producer entry (via $80 mirror)
emu.addMemoryCallback(function()
  if t>=0 and t<200 then prodFrames[t]=(prodFrames[t] or 0)+1; if not prodFrames.sl then prodFrames.sl=sl() end end
end, emu.callbackType.exec, 0x80D5E8, 0x80D5E8, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function()
  if t>=0 and t<200 then uplFrames[t]=(uplFrames[t] or 0)+1; if not uplFrames.sl then uplFrames.sl=sl() end end
end, emu.callbackType.exec, 0x80D56F, 0x80D56F, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then return end
  if t==200 then
    local pmiss, umiss, pmulti, umulti = 0,0,0,0
    for f=0,199 do
      if not prodFrames[f] then pmiss=pmiss+1 elseif prodFrames[f]>1 then pmulti=pmulti+1 end
      if not uplFrames[f] then umiss=umiss+1 elseif uplFrames[f]>1 then umulti=umulti+1 end
    end
    log:write(string.format("producer: scanline=%s, frames-missing=%d frames-multi=%d\n", tostring(prodFrames.sl), pmiss, pmulti))
    log:write(string.format("uploader: scanline=%s, frames-missing=%d frames-multi=%d\n", tostring(uplFrames.sl), umiss, umulti))
    log:close(); emu.stop(0)
  end
  t=t+1
end, emu.eventType.endFrame)
print("probe_ctx loaded")
