-- probe_sms_stagebgm.lua — is the BGM chosen by STAGE?
--
-- The maintainer's read is that music is tied to stages rather than characters,
-- which matters for the stage ports: a ported stage should be able to name its
-- own track. Log every APU command written during a round load (port $2140-3,
-- which is how the engine asks the SPC for anything) with the scene id, and run
-- it on two stages: whatever differs with the scene IS the stage's music.
--
-- usage: STAGE=1 ROM=<rom> tools/run.sh tools/saturn/probe_sms_stagebgm.lua 200
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local STAGE = tonumber(os.getenv("STAGE") or "1")
local TAG = os.getenv("TAG") or ("bgm" .. STAGE)
local LOG = assert(io.open(ENV.TRACE .. "saturn/stagebgm_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf, n = 0, 1, 0, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

emu.addMemoryCallback(function()
  wr(0x8E, STAGE * 2)
end, emu.callbackType.exec, 0x808586, 0x808586, emu.cpuType.snes, emu.memType.snesMemory)

-- the APU ports: log writes with the PC, but only around the round load, or the
-- per-frame chatter buries the one command that matters
for a = 0x802140, 0x802143 do
  emu.addMemoryCallback(function(addr, value)
    -- the NMI writes 0 to $2140/$2142 every frame as a handshake; only the
    -- non-zero commands are requests
    -- gate on the SCENE being loaded, not a frame number: the sample upload at
    -- ~f1263 floods any fixed window and happens before the stage is even chosen
    if ram(0x008E) == 0 or n > 40 or (value or 0) == 0 then return end
    n = n + 1
    local ok, st = pcall(emu.getState)
    log(string.format("f=%d $%04X <= %02X @%02X:%04X  (scene $%02X)",
      frames, addr % 0x10000, value or 0,
      ok and (st["cpu.k"] or 0) or 0, ok and (st["cpu.pc"] or 0) or 0, ram(0x008E)))
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function() wr(0x1B40, 8); wr(0x1B80, 4); return sf > 20 end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = beat({ a = true }); return sf > 60 end,
  function() return sf > 240 end,
  function()
    pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
    return ram(0x1000) == 8 or sf > 600
  end,
  function() return sf > 120 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 4000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_stagebgm loaded")
