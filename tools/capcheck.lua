-- capability check: io, getState keys (PC), exec callback + savestate, setInput
print("capcheck: start, io=" .. tostring(io) .. " os=" .. tostring(os))
local f = nil
if io and io.open then
  local ok, res = pcall(io.open, "/Users/koneko/Developer/SailorMoonS/traces/capcheck.txt", "w")
  if ok then f = res end
end
print("IO: " .. (f and "OK" or "FAIL"))

local function w(s)
  if f then f:write(s .. "\n"); f:flush() end
  print(s)
end

-- dump getState keys containing cpu/pc
local st = emu.getState()
local keys = {}
for k, _ in pairs(st) do keys[#keys+1] = k end
table.sort(keys)
local n = 0
for _, k in ipairs(keys) do
  if k:find("cpu") == 1 or k == "frameCount" or k == "masterClock" then
    n = n + 1
    if n <= 40 then w("KEY " .. k .. " = " .. tostring(st[k])) end
  end
end
w("total cpu keys: " .. n)

-- exec callback + savestate test: hook the reset vector region / any exec.
-- Use a broad exec range in bank $C0 to catch something quickly.
local stateSaved = false
local execCb
execCb = emu.addMemoryCallback(function(addr, value)
  if not stateSaved then
    stateSaved = true
    local okS, ss = pcall(emu.createSavestate)
    if okS and ss then
      w("SAVESTATE: OK len=" .. #ss)
      local f2 = io.open("/Users/koneko/Developer/SailorMoonS/traces/capcheck.mss", "wb")
      if f2 then f2:write(ss); f2:close(); w("SAVESTATE FILE: OK") end
    else
      w("SAVESTATE: FAIL " .. tostring(ss))
    end
    emu.removeMemoryCallback(execCb, emu.callbackType.exec, 0x8000, 0xFFFF, emu.cpuType.snes, emu.memType.snesMemory)
  end
end, emu.callbackType.exec, 0x8000, 0xFFFF, emu.cpuType.snes, emu.memType.snesMemory)

-- input test: hold Start pressed via inputPolled, check readback
local frames = 0
emu.addEventCallback(function()
  emu.setInput({ start = true }, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frames = frames + 1
  if frames == 60 then
    local inp = emu.getInput(0)
    local s = "INPUT readback:"
    for k, v in pairs(inp) do s = s .. " " .. k .. "=" .. tostring(v) end
    w(s)
  end
  if frames == 90 then
    if f then f:close() end
    emu.stop(0)
  end
end, emu.eventType.endFrame)

print("capcheck loaded")
