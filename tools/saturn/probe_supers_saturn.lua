-- probe_supers_saturn.lua — Super S recon: reach a VS match with P1 = SATURN (charID
-- 10, poked at char select) vs P2 = Uranus (6); verify the WRAM-identity claims
-- (player structs / mode vars, per docs/saturn/supers_map.md); dump a savestate
-- fixture + screenshot. ROM=<Super S> tools/run.sh tools/saturn/probe_supers_saturn.lua 120
-- Output: traces/saturn/supers_saturn.txt, traces/saturn/saturn_vs_uranus_supers.{mss,png}
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/supers_saturn.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local function beat(on) return (frames % 7) < 3 and on or {} end

local function snap(tag)
  log(string.format("%s f=%d step=%d 8D=%02X 70=%02X 1B10=%02X 1B40=%02X 1B42=%02X 1B80=%02X p1=%02X p2=%02X a1=%02X a2=%02X",
    tag, frames, step, ram(0x8D), ram(0x70), ram(0x1B10), ram(0x1B40), ram(0x1B42), ram(0x1B80),
    ram(0x1000), ram(0x1080), ram(0x1001), ram(0x1081)))
end

local STEPS = {
  function() return frames >= 900 end,                                   -- boot/attract
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,      -- menu row (same var as SMS?)
  function() pulse[0]=beat({start=true}); return sf>40 end,              -- confirm 1P vs 2P
  function() return sf>240 end,                                          -- settle at char select
  function() wr(0x1B40, 10); wr(0x1B80, 6); return sf>20 end,            -- P1=Saturn, P2=Uranus
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>90 end,
  function() pulse[0]={}; return sf>30 end,
  function() pulse[1]=beat({a=true}); return sf>60 end,
  function() return sf>240 end,
  function() pulse[0]=beat({start=true}); pulse[1]=beat({start=true})
             return (ram(0x1000)==10 and ram(0x1080)~=0) or sf>600 end,  -- through config to match
  function() return sf>150 end,                                          -- settle in-match
}

local save = false
emu.addMemoryCallback(function()
  if save then
    -- the WRAM-identity report
    log("=== IN-MATCH WRAM REPORT ===")
    for i, base in ipairs({0x1000, 0x1080}) do
      log(string.format("P%d: charID=%02X act=%02X step=%02X posx=%04X posy=%04X hb=%02X hub=%02X coll=%02X hp=%02X maxhp=%02X acs=%02X %02X %02X %02X %02X %02X",
        i, ram(base), ram(base+1), ram(base+2),
        ram(base+0x21)+256*ram(base+0x22), ram(base+0x25)+256*ram(base+0x26),
        ram(base+0x40), ram(base+0x41), ram(base+0x42), ram(base+0x49), ram(base+0x4A),
        ram(base+0x70), ram(base+0x71), ram(base+0x72), ram(base+0x73), ram(base+0x74), ram(base+0x75)))
    end
    log(string.format("mode 8D=%02X inmatch 70=%02X clock=%02X%02X frame=%02X", ram(0x8D), ram(0x70), ram(0x804), ram(0x803), ram(0x802)))
    local ss = emu.createSavestate()
    local so = io.open(ENV.TRACE .. "saturn/saturn_vs_uranus_supers.mss", "wb")
    if not so then print("probe_supers_saturn.lua: cannot open " .. (ENV.TRACE .. "saturn/saturn_vs_uranus_supers.mss")) emu.stop(1) return end
    so:write(ss); so:close()
    local sp = io.open(ENV.TRACE .. "saturn/saturn_vs_uranus_supers.png", "wb")
    if not sp then print("probe_supers_saturn.lua: cannot open " .. (ENV.TRACE .. "saturn/saturn_vs_uranus_supers.png")) emu.stop(1) return end
    sp:write(emu.takeScreenshot()); sp:close()
    log("savestate len=" .. #ss)
    emu.stop(0)
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if frames % 40 == 0 then snap("tick") end
  local fn = STEPS[step]
  if fn and fn() then snap("STEP->" .. (step + 1)); step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then save = true end
  if frames > 4500 then snap("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_supers_saturn loaded")
