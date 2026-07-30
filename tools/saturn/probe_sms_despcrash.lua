-- probe_sms_despcrash.lua — diagnose the low-HP desperation crash
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/despcrash.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local lastC1, lastEF, last80 = 0, 0, 0
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function(a) if t >= 145 then lastC1 = a end end,
  emu.callbackType.exec, 0xC10000, 0xC1FFFF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function(a) if t >= 145 then lastEF = a end end,
  emu.callbackType.exec, 0xEF0000, 0xEFFFFF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1000 + o, 0) end
    wr(0x1049, 0x10)
  end
  if t == 150 then wr(0x1051, 0x06) end
  if t >= 150 and t <= 175 then
    local ok, st = pcall(emu.getState)
    local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
    local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
    log(string.format("t=%03d p1 act=%02X pose=%02X req=%02X PC=%02X:%04X lastC1=%04X lastEF=%04X",
      t, ram(0x1001), ram(0x1005), ram(0x1051), k, pc, lastC1 % 0x10000, lastEF % 0x10000))
  end
  if t == 176 then log("DONE"); emu.stop(0) end
end, emu.eventType.endFrame)
print("despcrash loaded")
