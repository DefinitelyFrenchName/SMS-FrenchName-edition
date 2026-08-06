-- probe_title_shot.lua — boot to the title screen and save screenshots.
-- ROM=<build> tools/run.sh tools/probe_title_shot.lua 60
-- Taps Start a few times to skip intros; saves traces/title_<t>.png at intervals.

local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local t = 0
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }
local SHOTS = { [420]=true, [700]=true, [1000]=true, [1300]=true }

emu.addEventCallback(function()
  local b = {}
  for k, v in pairs(FALSE) do b[k] = v end
  -- periodic Start tap (2f) to advance logos; long gaps so title demo isn't skipped early
  if (t % 260) >= 160 and (t % 260) <= 161 then b.start = true end
  emu.setInput(b, 0, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  t = t + 1
  if SHOTS[t] then
    local png = emu.takeScreenshot()
    local f = assert(io.open(ENV.TRACE .. "title_" .. t .. ".png", "wb"), "probe_title_shot.lua: cannot open " .. (ENV.TRACE .. "title_" .. t .. ".png"))
    f:write(png); f:close()
  end
  if t > 1350 then emu.stop(0) end
end, emu.eventType.endFrame)

print("probe_title_shot.lua loaded")
