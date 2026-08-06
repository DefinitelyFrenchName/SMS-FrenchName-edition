-- inputprobe.lua: at the menu (f>=900), hold start; log reads of $4016/17/4218-421B
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local log = assert(io.open(TRACE .. "inputprobe.txt", "w"), "inputprobe.lua: cannot open " .. (TRACE .. "inputprobe.txt"))
local frames = 0
local logging = false
local count = 0

emu.addEventCallback(function()
  emu.setInput({ start = true, down = true }, 0)
end, emu.eventType.inputPolled)

local function onRead(addr, value)
  if logging and count < 400 then
    count = count + 1
    -- emu.getState() THROWS inside a memory callback (HANDOFF trap #8) and the
    -- error is swallowed, killing the invocation — this probe logged nothing at
    -- all until #97. pcall keeps the log alive; pc is included when available.
    local pc = "??:????"
    local ok, st = pcall(emu.getState)
    if ok and st then pc = string.format("%02X:%04X", st["cpu.k"], st["cpu.pc"]) end
    log:write(string.format("f=%d read $%04X = %02X pc=%s\n", frames, addr, value, pc))
  end
end

-- one registration per BANK IMAGE of the window (#97): the old second range
-- $4218-$421B was a strict subset of $4000-$43FF and double-counted the cap.
-- The $80:xxxx image is required — this game runs from the FastROM mirror
-- (HANDOFF trap), and with only the bank-$00 range the probe logged nothing.
emu.addMemoryCallback(onRead, emu.callbackType.read, 0x004000, 0x0043FF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(onRead, emu.callbackType.read, 0x804000, 0x8043FF, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  frames = frames + 1
  if frames == 900 then logging = true end
  if frames >= 1000 then
    -- also dump the WRAM around $0000-00FF input mirrors for reference
    local s = "WRAM 00-1F:"
    for a = 0x00, 0x1F do s = s .. string.format(" %02X", emu.read(a, emu.memType.snesWorkRam)) end
    log:write(s .. "\n")
    log:write(string.format("reads logged: %d\n", count))
    log:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)

print("inputprobe loaded")
