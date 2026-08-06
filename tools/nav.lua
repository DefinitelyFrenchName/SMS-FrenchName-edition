-- nav.lua: schedule-driven menu navigation with dense screenshot dumps.
-- Edit SCHEDULE: list of {frame, buttons_table, hold_frames(default 3), port(default 0)}
-- Screenshots dumped every SHOT_EVERY frames between SHOT_FROM and SHOT_TO.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local log = assert(io.open(TRACE .. "nav.txt", "w"), "nav.lua: cannot open " .. (TRACE .. "nav.txt"))
local frames = 0

-- dofile the schedule so this harness stays fixed
dofile(ENV.TOOLS .. "nav_schedule.lua")

local function ram(addr) return emu.read(addr, emu.memType.snesWorkRam) end

local active = {}  -- port -> {buttons, until_frame}

emu.addEventCallback(function()
  for port = 0, 2 do
    local a = active[port]
    if a and frames < a.untilf then
      emu.setInput(a.btn, port)
    else
      emu.setInput({ a=false,b=false,x=false,y=false,l=false,r=false,
                     up=false,down=false,left=false,right=false,
                     start=false,select=false }, port)
    end
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frames = frames + 1
  for _, s in ipairs(SCHEDULE) do
    if s[1] == frames then
      local port = s.port or 1
      active[port] = { btn = s[2], untilf = frames + (s.hold or 3) }
    end
  end
  if frames >= SHOT_FROM and frames <= SHOT_TO and frames % SHOT_EVERY == 0 then
    local f = io.open(string.format("%snav_%05d.png", TRACE, frames), "wb")
    if f then f:write(emu.takeScreenshot()); f:close() end
    log:write(string.format("f=%d mode=%02X p1char=%02X p1act=%02X p2char=%02X p2act=%02X\n",
      frames, ram(0x8D), ram(0x1000), ram(0x1001), ram(0x1080), ram(0x1081)))
    -- hex dump of low WRAM for cursor hunting
    local hex = {}
    for a = 0x0000, 0x01FF do hex[#hex+1] = string.format("%02X", ram(a)) end
    log:write("W " .. frames .. " " .. table.concat(hex) .. "\n")
    log:flush()
  end
  if frames >= STOP_AT then
    log:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)

print("nav loaded")
