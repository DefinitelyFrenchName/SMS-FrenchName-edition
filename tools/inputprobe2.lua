-- inputprobe2: hold start+down on all ports; peek $4218-421B each frame at menu
local frames = 0

emu.addEventCallback(function()
  for p = 0, 4 do
    pcall(function() emu.setInput({ start = true, down = true }, p) end)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frames = frames + 1
  if frames >= 900 and frames <= 910 then
    print(string.format("f=%d 4218=%02X 4219=%02X 421A=%02X 421B=%02X 4212=%02X",
      frames,
      emu.read(0x4218, emu.memType.snesMemory),
      emu.read(0x4219, emu.memType.snesMemory),
      emu.read(0x421A, emu.memType.snesMemory),
      emu.read(0x421B, emu.memType.snesMemory),
      emu.read(0x4212, emu.memType.snesMemory)))
  end
  if frames > 910 then emu.stop(0) end
end, emu.eventType.endFrame)

print("inputprobe2 loaded")
