-- poke my combo state to a fixed hits value, screenshot to check the rendered glyph
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local WRAM = emu.memType.snesWorkRam
local t, needLoad = -1, true
local VAL = POKEVAL or 15
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."uranus_vs_jupiter_v07.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec, 0x808353,0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then return end
  -- every frame force hits=VAL, ttl high, shown!=VAL so it re-renders
  if t>=10 then
    emu.write(0x08B0, VAL, WRAM)     -- P2-defender hits
    emu.write(0x08B2, 90, WRAM)      -- ttl
    emu.write(0x08B3, 0xFF, WRAM)    -- shown (force dirty)
  end
  if t==40 then local f=io.open(TRACE.."cc_digit.png","wb"); f:write(emu.takeScreenshot()); f:close(); emu.stop(0) end
  t=t+1
end, emu.eventType.endFrame)
print("probe_digit loaded")
