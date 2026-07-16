-- probe_hudre.lua — patch-10 RE probes R1+R2: who READS the timer BCD ($7E:0802) and who
-- WRITES the displayed-HP latches ($7E:0800/0801) during a match. Logs unique PCs with hit
-- counts. Scenario: Venus 5LP hits Jupiter at t=64 (established oracle), timer ticking.
-- Also confirms game_mode ($7E:008D) of the savestate.
-- USE: ROM=<clean> tools/run.sh tools/probe_hudre.lua 90 → traces/probe_hudre.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local log = io.open(TRACE .. "probe_hudre.txt", "w")
local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local t, needLoad = -1, true
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

local readers, writers = {}, {}
local function pc()
  local ok, st = pcall(emu.getState)
  if not ok then return "?" end
  return string.format("%02X:%04X", st["cpu.k"] or 0, st["cpu.pc"] or 0)
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = io.open(TRACE .. "venus_vs_jupiter_clean.mss", "rb")
    if not f then return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr, value)
  if t < 0 then return end
  local k = pc()
  readers[k] = (readers[k] or 0) + 1
end, emu.callbackType.read, 0x0802, 0x0802, emu.cpuType.snes, emu.memType.snesWorkRam)

emu.addMemoryCallback(function(addr, value)
  if t < 0 then return end
  local k = pc() .. string.format(" [%04X<=%02X]", addr, value or 255)
  writers[k] = (writers[k] or 0) + 1
end, emu.callbackType.write, 0x0800, 0x0801, emu.cpuType.snes, emu.memType.snesWorkRam)

emu.addEventCallback(function()
  if t < 0 then emu.setInput(FALSE,0,0); emu.setInput(FALSE,0,1); return end
  local p1 = {}
  for k, v in pairs(FALSE) do p1[k] = v end
  if t >= 60 and t < 63 then p1.y = true end
  emu.setInput(FALSE, 0, 1); emu.setInput(p1, 0, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  if t == 1 then log:write(string.format("game_mode $008D = %02X\n", r(0x8D))) end
  if t == 5 then emu.write(0x1021, 0xE8, WRAM) end
  if t == 240 then
    log:write("== readers of $0802 (timer BCD) ==\n")
    for k, n in pairs(readers) do log:write(string.format("  %s x%d\n", k, n)) end
    log:write("== writers of $0800/0801 (HP bar latches) ==\n")
    for k, n in pairs(writers) do log:write(string.format("  %s x%d\n", k, n)) end
    log:close()
    emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_hudre loaded")
