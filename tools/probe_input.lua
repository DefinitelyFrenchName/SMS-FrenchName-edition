-- probe_input.lua — does emu.getInput (called BEFORE setInput in inputPolled) return the
-- physical pad, or does a PREVIOUS frame's setInput stick? Headless: no physical input, so
-- inject y on frames 60-62 only, never touch port 0 after t=63, and log getInput(0) each
-- frame 59..70 taken at the TOP of inputPolled. Sticky => {y} persists past 63.
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local log = io.open(TRACE .. "probe_input.txt", "w")
local t, needLoad = -1, true
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

emu.addMemoryCallback(function()
  if needLoad then
    local f = io.open(TRACE .. "venus_vs_jupiter_clean.mss", "rb")
    if not f then return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  if t >= 59 and t <= 70 then
    local ok, g = pcall(emu.getInput, 0)
    local on = {}
    if ok and type(g) == "table" then for k, v in pairs(g) do if v then on[#on+1] = k end end end
    log:write(string.format("t=%03d getInput(0) pre-set: {%s}\n", t, table.concat(on, ",")))
    log:flush()
  end
  if t >= 60 and t <= 62 then
    local p1 = {}; for k, v in pairs(FALSE) do p1[k] = v end
    p1.y = true
    emu.setInput(p1, 0, 0)
  end
  -- after t=62: never call setInput on port 0 again
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t == 72 then log:close(); emu.stop(0) end
  if t >= 0 then t = t + 1 end
  if t == 0 then t = 0 end
end, emu.eventType.endFrame)

-- keep t advancing even before load finishes
emu.addEventCallback(function() end, emu.eventType.startFrame)
print("probe_input loaded")
