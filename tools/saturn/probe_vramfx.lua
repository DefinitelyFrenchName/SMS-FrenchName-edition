
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then wr(0x1F60, 1); wr(0x1F62, 1) end
  if t == 200 then
    local f = assert(io.open(ENV.TRACE .. "saturn/vram_fx.bin", "wb"))
    local b = {}
    for i = 0, 0x103F do b[#b+1] = string.char(emu.read(0x6A00*2 + i, emu.memType.snesVideoRam)) end
    f:write(table.concat(b)); f:close()
    print("vram dumped")
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("loaded")
