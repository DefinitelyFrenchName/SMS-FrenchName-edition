-- probe_supers_animload.lua — locate Super S's per-character animation payload.
-- The manifest's anim field is repurposed (all chars -> shared $E0:F328), so we watch
-- WRAM $7E:6A00+ (the SMS expansion target; WRAM layout is game-identical) during
-- Saturn's character load and log the WRITER's PC + registers. Nav = same autopilot
-- as probe_supers_saturn (P1=Saturn, P2=Uranus).
-- ROM=<Super S> tools/run.sh tools/saturn/probe_supers_animload.lua 120 -> traces/saturn/supers_animload.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/supers_animload.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local events, armed = 0, false

emu.addEventCallback(function()
  for p = 0, 1 do
    emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p)
  end
end, emu.eventType.inputPolled)

local function beat(on) return (frames % 7) < 3 and on or {} end

-- write-watch on the expansion buffer (first 64 bytes is plenty to catch the writer)
emu.addMemoryCallback(function(addr, value)
  if not armed or events >= 24 then return end
  events = events + 1
  local st = emu.getState()
  log(string.format("W $%04X=%02X  PC=%02X:%04X A=%04X X=%04X Y=%04X D=%04X DB=%02X  f=%d step=%d",
    addr, value, st["cpu.k"], st["cpu.pc"], st["cpu.a"], st["cpu.x"], st["cpu.y"],
    st["cpu.d"], st["cpu.db"], frames, step))
end, emu.callbackType.write, 0x6A00, 0x6A3F, emu.cpuType.snes, emu.memType.snesWorkRam)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() return sf>240 end,
  function() wr(0x1B40, 10); wr(0x1B80, 6); armed = true; return sf>20 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>90 end,
  function() pulse[0]={}; return sf>30 end,
  function() pulse[1]=beat({a=true}); return sf>60 end,
  function() return sf>240 end,
  function() pulse[0]=beat({start=true}); pulse[1]=beat({start=true})
             return (ram(0x1000)==10 and ram(0x1080)~=0) or sf>600 end,
  function() return sf>60 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("DONE events=%d  6A00 head: %02X %02X %02X %02X %02X %02X %02X %02X",
      events, ram(0x6A00), ram(0x6A01), ram(0x6A02), ram(0x6A03), ram(0x6A04), ram(0x6A05), ram(0x6A06), ram(0x6A07)))
    emu.stop(0)
  end
  if frames > 4500 then log("TIMEOUT events=" .. events); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_supers_animload loaded")
