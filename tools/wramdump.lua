-- wramdump.lua: load a savestate, dump a WRAM range to traces/<OUT>. Cfg: wramdump_cfg.lua
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
pcall(dofile, "/Users/koneko/Developer/SailorMoonS/tools/wramdump_cfg.lua")
STATE = STATE or "venus_vs_jupiter_clean.mss"
LO = LO or 0x6A00
HI = HI or 0x7200
OUT = OUT or "wramdump.txt"
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = io.open(TRACE .. STATE, "rb"); if not f then return end
    local ss = f:read("*a"); f:close(); emu.loadSavestate(ss)
    needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if t < 0 then return end
  if t == 3 then
    local f = io.open(TRACE .. OUT, "w")
    for a = LO, HI, 16 do
      local row = {}
      for i = 0, 15 do row[#row+1] = string.format("%02X", emu.read(a+i, emu.memType.snesWorkRam)) end
      f:write(string.format("%04X: %s\n", a, table.concat(row, " ")))
    end
    f:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)
print("wramdump loaded")
