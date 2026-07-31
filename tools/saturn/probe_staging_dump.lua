
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local grabbed = false
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn/saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 5 and not grabbed then
    grabbed = true
    local f = assert(io.open(ENV.TRACE .. "saturn/staging_7f.bin", "wb"))
    local bytes = {}
    for i = 0, 0x14A0 - 1 do
      bytes[#bytes+1] = string.char(emu.read(0x7F0000 + i, emu.memType.snesMemory))
    end
    f:write(table.concat(bytes)); f:close()
    print("dumped")
  end
  if t > 10 then emu.stop(0) end
end, emu.eventType.endFrame)
print("staging dump loaded")
