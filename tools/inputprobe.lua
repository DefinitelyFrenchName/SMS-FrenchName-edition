-- inputprobe.lua: at the menu (f>=900), hold start; log reads of $4016/17/4218-421B
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local log = io.open(TRACE .. "inputprobe.txt", "w")
local frames = 0
local logging = false
local count = 0

emu.addEventCallback(function()
  emu.setInput({ start = true, down = true }, 0)
end, emu.eventType.inputPolled)

local function onRead(addr, value)
  if logging and count < 400 then
    count = count + 1
    local st = emu.getState()
    log:write(string.format("f=%d read $%04X = %02X pc=%02X:%04X\n",
      frames, addr, value, st["cpu.k"], st["cpu.pc"]))
  end
end

emu.addMemoryCallback(onRead, emu.callbackType.read, 0x4000, 0x43FF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(onRead, emu.callbackType.read, 0x4218, 0x421B, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  frames = frames + 1
  if frames == 900 then logging = true end
  if frames >= 1000 then
    -- also dump the WRAM around $0000-00FF input mirrors for reference
    local s = "WRAM 00-1F:"
    for a = 0x00, 0x1F do s = s .. string.format(" %02X", emu.read(a, emu.memType.snesWorkRam)) end
    log:write(s .. "\n")
    log:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)

print("inputprobe loaded")
