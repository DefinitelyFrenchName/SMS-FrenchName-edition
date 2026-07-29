-- probe_p11_nav.lua (patch 11, P0): boot -> title menu -> Practice (cursor $1B10==4)
-- -> char select autopilot -> in-match. Logs $008D/$1B10/$1B40/$1B42/$1B80/$1000/$1080
-- every 20f + on step transitions to traces/p11_nav.txt; saves traces/training_p11.mss
-- + screenshot when a training match is live. Run on the CLEAN ROM via tools/run.sh.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p11_nav.txt", "w"))
local frames, step, sf = 0, 1, 0
local pulse = {}
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local function snap(tag)
  log(string.format("%s f=%d step=%d mode=%02X 1B10=%02X 1B40=%02X 1B42=%02X 1B80=%02X p1=%02X p2=%02X p1act=%02X hp=%02X/%02X",
    tag, frames, step, ram(0x8D), ram(0x1B10), ram(0x1B40), ram(0x1B42), ram(0x1B80),
    ram(0x1000), ram(0x1080), ram(0x1001), ram(0x1049), ram(0x10C9)))
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k,v in pairs(b) do base[k]=v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local function beat(on) return (frames % 7) < 3 and on or {} end
local function slowbeat(on) return (frames % 16) < 4 and on or {} end
local prev1B10 = -1

local STEPS = {
  function() return frames >= 900 end,                                   -- boot/attract settle
  function() pulse[0]=slowbeat({down=true}); return ram(0x1B10)==1 end,  -- row 2 (left col)
  function() pulse[0]=slowbeat({right=true}); return ram(0x1B10)==4 end, -- col 2 = Practice
  function() pulse[0]={}; return sf>10 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,              -- confirm Practice
  function() pulse[0]={}; return sf>240 end,                             -- settle (log watches what screen)
  function() emu.write(0x1B40, 6, emu.memType.snesWorkRam)               -- P1 = Uranus
             emu.write(0x1B80, 4, emu.memType.snesWorkRam)               -- P2 = Jupiter (if applicable)
             return sf>20 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>90 end,-- P1 confirm
  function() pulse[0]={}; return sf>30 end,
  function() pulse[1]=beat({a=true}); return sf>60 end,                  -- P2 confirm (may be n/a)
  function() return sf>240 end,
  function() pulse[0]=beat({start=true}); pulse[1]=beat({start=true})    -- through config screens
             return (ram(0x1000)==6 and ram(0x1001)==0 and ram(0x1080)~=0) or sf>600 end,
  function() return sf>120 end,                                          -- settle in-match
}

local save = false
emu.addMemoryCallback(function()
  if save then
    local ss = emu.createSavestate()
    local so = io.open(TRACE .. "training_p11.mss", "wb"); so:write(ss); so:close()
    local sp = io.open(TRACE .. "p11_nav.png", "wb"); sp:write(emu.takeScreenshot()); sp:close()
    snap("SAVED")
    log(string.format("savestate len=%d", #ss))
    emu.stop(0)
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local c = ram(0x1B10)
  if c ~= prev1B10 then log(string.format("cursor f=%d step=%d 1B10 %02X->%02X", frames, step, prev1B10, c)); prev1B10 = c end
  if frames % 20 == 0 then snap("tick") end
  local fn = STEPS[step]
  if fn and fn() then snap("STEP->" .. (step+1)); step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then save = true end
  if frames > 4500 then snap("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_p11_nav loaded")
