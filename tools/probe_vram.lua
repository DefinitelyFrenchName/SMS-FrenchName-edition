-- probe_vram.lua — patch-10 R4: dump in-match VRAM + CGRAM + the HUD tilemap region.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = io.open(TRACE .. "venus_vs_jupiter_clean.mss", "rb")
    if not f then return end
    local ss = f:read("*a"); f:close(); emu.loadSavestate(ss)
    needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if t < 0 then return end
  if t == 30 then
    local f = io.open(TRACE .. "vram_match.bin", "wb")
    local buf = {}
    for a = 0, 0xFFFF do buf[#buf+1] = string.char(emu.read(a, emu.memType.snesVideoRam)) end
    f:write(table.concat(buf)); f:close()
    f = io.open(TRACE .. "cgram_match.bin", "wb")
    buf = {}
    for a = 0, 0x1FF do buf[#buf+1] = string.char(emu.read(a, emu.memType.snesCgRam)) end
    f:write(table.concat(buf)); f:close()
    local shot = emu.takeScreenshot()
    f = io.open(TRACE .. "vram_match.png", "wb"); f:write(shot); f:close()
    emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)
print("probe_vram loaded")
