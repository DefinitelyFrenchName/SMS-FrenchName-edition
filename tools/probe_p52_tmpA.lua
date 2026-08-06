-- TEMP (#52): does scriptTimeout bound a single Lua entry's execution?
local t0 = os.clock()
while os.clock() - t0 < 8 do end
print("A-SURVIVED busy 8s in one entry")
emu.addEventCallback(function() emu.stop(0) end, emu.eventType.endFrame)
