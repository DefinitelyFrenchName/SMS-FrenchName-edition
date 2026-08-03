-- probe_sms_lrmodes.lua — diagnose L+R Saturn-select, per game mode.
-- MODE from $MODE or lrmode_cfg.lua. MEASURED row->mode map (probe_sms_menurows):
--   story    = menu row 0 -> $8D=00   (Saturn is REFUSED here by design)
--   vscom    = menu row 2 -> $8D=02
--   practice = menu row 4 -> $8D=04
-- 2P VS (row 1) needs two pads confirming independently — use
-- probe_sms_shellguard.lua MODE=vs for that.
-- ⚠ The old name for row 0 was "vscpu", which was WRONG: row 0 is story. That
-- mislabel is the same one that hid field bug 2 for a week, and it made this
-- probe report a design-correct refusal as "LR FAIL" on v0.14.6+.
-- Holds L+R from charselect on; logs $8D/$0070/clock/$1E04/flag/p1 id+act.
-- ROM=build/saturn/SailorMoonS_saturn_v0.8.0.sfc tools/run.sh tools/saturn/probe_sms_lrmodes.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = os.getenv("MODE") or "practice"
-- NOTE: $SHELL is a standard shell variable (/bin/zsh), so a bare run inherits a
-- non-numeric value — prefer SHELL_ID, and fall back to 6 rather than to nil
-- (a nil here made wr() throw and the script die with no verdict at all).
local function shellid(default)
  return tonumber(os.getenv("SHELL_ID") or "") or tonumber(os.getenv("SHELL") or "") or default
end
local SHELL = shellid(6)                           -- which character to wear
if not os.getenv("MODE") then
  pcall(function() MODE = dofile(ENV.TOOLS .. "saturn/lrmode_cfg.lua") end)
end
local ROW = ({ story = 0, vscom = 2, practice = 4 })[MODE]
  or error("MODE must be story|vscom|practice (2P VS: use probe_sms_shellguard MODE=vs)")
-- Saturn is expected to arm everywhere EXCEPT story, and only on a 6/7/8 shell
local EXPECT_SATURN = (ROW ~= 0)
local LOG = assert(io.open(ENV.TRACE .. "saturn/lrmodes_" .. MODE .. ".txt", "w"))
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

local STEPS = {
  function() return frames >= 900 end,
  function()  -- column: story stays at 0; practice is one RIGHT off row 1
    if ROW == 0 then return sf > 30 end
    pulse[0] = beat({down = true}); return ram(0x1B10) == (ROW == 4 and 1 or ROW)
  end,
  function()
    if ROW ~= 4 then return true end
    pulse[0] = beat({right = true}); return ram(0x1B10) == 4
  end,
  function() pulse[0] = beat({start = true}); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() wr(0x1B40, SHELL); if MODE == "practice" then wr(0x1B80, 4) end
             hold = true; return sf > 20 end,
  function() pulse[0] = beat({a = true}); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()  -- mash A/Start until actually IN MATCH ($0070==4)
    -- Re-poke the cursor for the WHOLE load, not once at step 6: the A/Start
    -- mash walks through a second selection screen that reuses $1B40, so a
    -- one-shot poke is silently undone and the fight loads charID 1 (story) or
    -- 0 (practice). That artifact is what made SHELL_GUARD look like it blocked
    -- every shell on 2026-08-03 — see docs/saturn/BUILDS.md v0.14.5.
    wr(0x1B40, SHELL)
    if MODE == "practice" then wr(0x1B80, 4) end
    pulse[0] = (frames % 14 < 3) and {a = true}
      or ((frames % 14 >= 7 and frames % 14 < 10) and {start = true} or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return sf > 500 end,
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
    -- verdict is against what this MODE should do, not against "is she Saturn":
    -- story refusing her is the story lock working
    local isSat = ram(0x1000) == 0x1C
    log(string.format("FINAL: mode=%s $8D=%02X p1=%02X %s", MODE, ram(0x8D), ram(0x1000),
      (isSat == EXPECT_SATURN) and "LR PASS" or "LR FAIL"))
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_sms_lrmodes loaded: " .. MODE)
