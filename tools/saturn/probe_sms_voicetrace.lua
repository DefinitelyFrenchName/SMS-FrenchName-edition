-- probe_sms_voicetrace.lua — per-frame DSP trace of a single forced voice
-- request, to explain the P2 anomaly seen by probe_sms_voiceid.lua (some ids
-- resolved to the $B700 half of the record even though the NMI put bit 7 on the
-- port). Dumps every voice's SRCN/ENVX for a window around the request.
--
-- usage: CHARA=6 CHAR2=6 PLAYER=1 ID=77 TAG=t77 ROM=<rom> tools/run.sh \
--            tools/saturn/probe_sms_voicetrace.lua 900
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHARA = tonumber(os.getenv("CHARA") or "6")
local CHAR2 = tonumber(os.getenv("CHAR2") or "6")
local PLAYER = tonumber(os.getenv("PLAYER") or "1")
local IDS = {}
for s in (os.getenv("IDS") or "74,75,76,77"):gmatch("%d+") do IDS[#IDS + 1] = tonumber(s) end
local TAG = os.getenv("TAG") or "x"
local LOG = assert(io.open(ENV.TRACE .. "saturn/voicetrace_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram
local DSP = emu.memType.spcDspRegisters
local function dsp(r) return emu.read(r, DSP) end

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function()
    emu.write(0x1B40, CHARA, emu.memType.snesWorkRam)
    emu.write(0x1B80, CHAR2, emu.memType.snesWorkRam)
    return sf > 20
  end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = beat({ a = true }); return sf > 60 end,
  function() return sf > 240 end,
  function()
    pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
    return ram(0x1000) == CHARA or sf > 600
  end,
  function() return ram(0x1000) == CHARA and ram(0x1080) ~= 0 end,
  function() return sf > 90 end,
}

local ports = {}
for port = 0, 2 do
  for _, b in ipairs({ 0x002140 + port, 0x802140 + port }) do
    emu.addMemoryCallback(function(_, value)
      if (value or 0) ~= 0 then ports[#ports + 1] = string.format("p%d<=$%02X", port, value) end
    end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
  end
end

local inmatch, k, t = false, 1, 0
local WIN = 24
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if not inmatch then
    local fn = STEPS[step]
    if fn and fn() then step = step + 1; sf = 0; pulse = {} end
    if not STEPS[step] then
      inmatch = true
      log(string.format("=== P1 char %d P2 char %d, firing on %s ===",
        CHARA, CHAR2, PLAYER == 0 and "P1 $1078" or "P2 $10F8"))
    end
    return
  end
  if k > #IDS then log("done"); emu.stop(0); return end
  if t == 0 then
    ports = {}
    emu.write(PLAYER == 0 and 0x1078 or 0x10F8, IDS[k], emu.memType.snesWorkRam)
    log(string.format("--- id %d ($%02X) ---", IDS[k], IDS[k]))
  end
  local row = {}
  for v = 0, 7 do
    local s, e = dsp(v * 0x10 + 4), dsp(v * 0x10 + 8)
    if e > 0 then row[#row + 1] = string.format("v%d:%d/%d", v, s, e) end
  end
  log(string.format("  +%-2d %-56s %s", t, table.concat(row, " "), table.concat(ports, " ")))
  ports = {}
  t = t + 1
  if t > WIN then t = 0; k = k + 1 end
  if frames > 6000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_sms_voicetrace loaded")
