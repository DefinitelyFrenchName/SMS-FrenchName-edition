-- nav_explore.lua: press start periodically, screenshot + RAM dump to see menu flow
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local log = io.open(TRACE .. "nav_explore.txt", "w")
local frames = 0

local function ram(addr) return emu.read(addr, emu.memType.snesWorkRam) end

emu.addEventCallback(function()
  -- press start for 5 frames every 40 frames
  local phase = frames % 40
  emu.setInput({ start = (phase < 5) }, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frames = frames + 1
  if frames % 300 == 0 then
    local shot = emu.takeScreenshot()
    local f = io.open(string.format("%snav_%05d.png", TRACE, frames), "wb")
    if f then f:write(shot); f:close() end
    log:write(string.format("f=%d mode=%02X p1char=%02X p1act=%02X p2char=%02X\n",
      frames, ram(0x8D), ram(0x1000), ram(0x1001), ram(0x1080)))
    log:flush()
  end
  if frames >= 6000 then
    log:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)

print("nav_explore loaded")
