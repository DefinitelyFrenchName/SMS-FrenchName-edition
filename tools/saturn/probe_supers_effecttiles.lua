-- probe_supers_effecttiles.lua — dump the OBJ effects VRAM region (tiles 0xA0-0xFF,
-- VRAM words $6A00-$6FFF) from the Super S Saturn fixture, so the fireball tiles'
-- ROM source can be located by byte search. Writes traces/saturn/supers_effecttiles.bin
-- ROM=<Super S> tools/run.sh tools/saturn/probe_supers_effecttiles.lua 60
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local t, needLoad = -1, true

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
  if t == 30 then
    local out = assert(io.open(ENV.TRACE .. "saturn/supers_effecttiles.bin", "wb"))
    local V = emu.memType.snesVideoRam
    for a = 0x6A00 * 2, 0x7000 * 2 - 1 do   -- VRAM is word-addressed; byte dump
      out:write(string.char(emu.read(a, V)))
    end
    out:close()
    print("dumped 3KB effects region")
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("probe_supers_effecttiles loaded")
