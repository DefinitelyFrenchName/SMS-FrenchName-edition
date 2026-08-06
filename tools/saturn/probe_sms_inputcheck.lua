-- probe_sms_inputcheck.lua — after an L+R Saturn select, does she RESPOND to
-- inputs? (field bug: in 2P VS / 1P-vs-COM she appeared but inputs did nothing
-- until she was hit). MODE env (via lrmode_cfg written by the runner):
-- "practice" (menu row 4) or "vscpu" (menu row 0). Holds L+R from charselect
-- on; logs $8D/$0070/clock/$1E04/flag/p1 id+act through the load; then waits
-- for the round to go live, holds RIGHT 90f and verdicts INPUT OK / INPUT DEAD
-- plus LR PASS/FAIL on p1's id.
-- ROM=build/saturn/SailorMoonS_saturn_v0.8.0.sfc tools/run.sh tools/saturn/probe_sms_inputcheck.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = "practice"
pcall(function() MODE = dofile(ENV.TOOLS .. "saturn/lrmode_cfg.lua") end)
local LOG = assert(io.open(ENV.TRACE .. "saturn/inputcheck_" .. MODE .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local hold = false

local function beat(on) return (frames % 7) < 3 and on or {} end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if p == 0 and hold then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local x0 = 0
local STEPS = {
  function() return frames >= 900 end,
  function()  -- menu row: vscpu = row 0 (default), practice = down to 1 then right to 4
    if MODE == "vscpu" then return sf > 30 end
    pulse[0] = beat({down = true}); return ram(0x1B10) == 1
  end,
  function()
    if MODE == "vscpu" then return true end
    pulse[0] = beat({right = true}); return ram(0x1B10) == 4
  end,
  function() pulse[0] = beat({start = true}); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() wr(0x1B40, 6); if MODE ~= "vscpu" then wr(0x1B80, 4) end; hold = true; return sf > 20 end,
  function() pulse[0] = beat({a = true}); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()  -- mash A/Start until actually IN MATCH ($0070==4)
    if MODE == "practice" then wr(0x1B80, 4) end
    pulse[0] = (frames % 14 < 3) and {a = true}
      or ((frames % 14 >= 7 and frames % 14 < 10) and {start = true} or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  -- the field bug: in 2P VS / 1P-vs-COM she appeared but INPUTS DID NOTHING
  -- until she was hit. So: wait for the round to be live and the intro flag to
  -- clear, then hold RIGHT and see whether she actually walks.
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and ram(0x1E04) == 0 and sf > 60 end,
  function()
    if sf == 1 then
      x0 = ram(0x1021)
      log(string.format("CONTROL: id=%02X act=%02X x=%02X $1E04=%02X $01FA=%02X",
        ram(0x1000), ram(0x1001), x0, ram(0x1E04), ram(0x1FA)))
    end
    pulse[0] = { right = true }
    if sf % 6 == 0 and sf <= 60 then
      log(string.format("   +%2df act=%02X x=%02X", sf, ram(0x1001), ram(0x1021)))
    end
    if sf > 90 then
      local x1 = ram(0x1021)
      log(string.format("after 90f of RIGHT: x %02X -> %02X (moved %d)  act=%02X",
        x0, x1, (x1 - x0 + 256) % 256, ram(0x1001)))
      log(((x1 ~= x0) and "INPUT OK" or "INPUT DEAD — she does not respond"))
      return true
    end
    return false
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if hold and frames % 25 == 0 then
    log(string.format("f=%d mode8D=%02X in70=%02X clock=%02X%02X e04=%02X flag=%02X p1=%02X act=%02X",
      frames, ram(0x8D), ram(0x70), ram(0x804), ram(0x803), ram(0x1E04),
      emu.read(0x7FF100, emu.memType.snesMemory), ram(0x1000), ram(0x1001)))
  end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("FINAL: p1=%02X %s", ram(0x1000),
      ram(0x1000) == 0x1C and "LR PASS" or "LR FAIL"))
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_sms_lrmodes loaded: " .. MODE)
