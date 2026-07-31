
-- probe_sms_wramfree.lua — empirical free-WRAM census: watch writes across
-- $7F:F000-$7F:F0FF (patch 11's proven block) during a FULL vanilla session
-- (boot -> charselect -> config -> match -> KO -> win screen).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/wramfree.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local hits = {}
local function beat(on) return (frames % 10) < 2 and on or {} end
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function(addr, value)
  local off = addr % 0x100
  if not hits[off] then
    hits[off] = frames
    log(string.format("f=%d first write 7FF0%02X <= %02X", frames, off, value or -1))
  end
end, emu.callbackType.write, 0x7FF000, 0x7FF0FF, emu.cpuType.snes, emu.memType.snesMemory)
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() return sf>300 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>120 end,
  function() pulse[1]=beat({a=true}); return ram(0x1B82)==1 or sf>120 end,
  function() return sf>600 end,                          -- config screen
  function() pulse[0]=beat({start=true}); pulse[1]=beat({start=true})
             return (ram(0x70)==4 and ram(0x1000)~=0) or sf>900 end,
  function() return sf>120 end,
  function() wr(0x10C9, 1); pulse[0]=beat({y=true}); return ram(0x10C9)==0 or sf>240 end,
  function() pulse[0]={}; return sf>700 end,             -- win sequence
  function() log("session complete"); return true end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    local n = 0
    for _ in pairs(hits) do n = n + 1 end
    log(string.format("TOTAL touched bytes in $7F:F000-F0FF: %d/256", n))
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT (session too slow)"); emu.stop(1) end
end, emu.eventType.endFrame)
print("wramfree loaded")
