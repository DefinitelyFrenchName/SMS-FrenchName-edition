-- smoke test: boot ROM, run 120 frames, read some WRAM, exit with code 42
local frames = 0

emu.addEventCallback(function()
  frames = frames + 1
  if frames == 120 then
    local p1char = emu.read(0x1000, emu.memType.snesWorkRam)
    print(string.format("SMOKE frames=%d p1char=%02X", frames, p1char))
    emu.log(string.format("SMOKE-LOG frames=%d p1char=%02X", frames, p1char))
    emu.stop(42)
  end
end, emu.eventType.endFrame)

print("SMOKE loaded")
