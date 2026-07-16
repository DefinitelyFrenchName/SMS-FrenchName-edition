-- probe_p11_wmdata.lua (patch 11, P6): does the game touch the WMDATA port $2180-$2183
-- during a training match (incl. movelist + fighting)? Recording ring depends on it.
-- Output: traces/p11_wmdata.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p11_wmdata.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local t, needLoad = -1, true
local hits = 0
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
for _, cb in ipairs({ emu.callbackType.read, emu.callbackType.write }) do
  emu.addMemoryCallback(function(addr, value)
    if t >= 0 and hits < 20 then
      hits = hits + 1
      log(string.format("hit t=%d addr=%04X val=%02X pc=%06X", t, addr, value, emu.getState()["cpu.pc"]))
    end
  end, cb, 0x2180, 0x2183, emu.cpuType.snes, emu.memType.snesMemory)
end

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t % 20 < 3 then pulse[0] = { down = true, y = true }
  elseif t % 20 < 6 then pulse[0] = { right = true, x = true } else pulse[0] = nil end
  if t >= 200 and t <= 202 then pulse[0] = { start = true } end
  if t >= 280 and t <= 282 then pulse[0] = { start = true } end
  if t == 400 then log(string.format("total WMDATA hits=%d over 400f (fighting+movelist)", hits)); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_p11_wmdata loaded")
