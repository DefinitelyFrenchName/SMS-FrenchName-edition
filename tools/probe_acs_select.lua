-- probe_acs_select.lua — does SELECT still open the ACS screen from the VS
-- button-config screen?
--
-- Patch 15 makes that screen's モード row inert (three edits inside the row's
-- own handler, `$C3:A849`, which is entry 0 of the row-dispatch table at
-- `$C3:A839`). The screen also advertises `PRESS "SELECT" TO ACS` along its top,
-- and the question is whether removing AUTO took ACS with it. Reasoning says no
-- — the edits are inside one row handler and ACS is a screen-level transition —
-- but "says no" is not a measurement, so this presses the button.
--
-- Verdict is the screen ITSELF: `$008A` is the menu-state byte the config screen
-- hands to whatever comes next, and a screenshot is saved so the ACS page can be
-- recognised by eye rather than by a number whose meaning is assumed.
--
--   ROM=<rom> TAG=clean tools/run.sh tools/probe_acs_select.lua 400
--   ROM=<rom> TAG=p15   tools/run.sh tools/probe_acs_select.lua 400
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram = PL.ram
local TAG = os.getenv("TAG") or "acs"
local LOG = assert(io.open(ENV.TRACE .. "acs_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end
local function w16(a) return ram(a) | (ram(a + 1) << 8) end

local frames, step, sf = 0, 1, 0
local pulse = {}
local function beat(on) return (frames % 7) < 3 and on or {} end

-- PRECONDITION: the stage row's `sta $1C1C` ($C3:AA38) only runs on the config
-- screen, so it proves we got there before SELECT was pressed at all.
local onscreen = 0
emu.addMemoryCallback(function() onscreen = onscreen + 1 end,
  emu.callbackType.exec, 0x83AA38, 0x83AA38, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)

-- WHO makes the jump? $008A is the menu-state byte; log the PC of every write
-- to it once we are on the config screen, so the SELECT->ACS transition names
-- its own address instead of being hunted for. Increment before the call that
-- can throw (emu.getState raises inside a memory callback here).
local writes, wn = {}, 0
local function st() local ok, v = pcall(emu.getState); return ok and v or nil end
emu.addMemoryCallback(function(_, v)
  if onscreen == 0 then return end
  wn = wn + 1
  local s = st(); if not s then return end
  local pc = ((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)
  writes[string.format("$8A <- $%02X  from PC $%06X", v or 0, pc)] = true
end, emu.callbackType.write, 0x008A, 0x008A, emu.cpuType.snes, emu.memType.snesWorkRam)

local ctx = {}
local STEPS = {
  function() return frames >= 900 end,
  -- MENU selects the title entry: 1 = 1P vs 2P (mode $8D=1), 2 = 1P vs Com
  -- ($8D=2). Patch 18 blocks ACS in the first and must leave the second alone,
  -- so the vs-COM run is the control that proves SELECT itself still works.
  function() pulse[0] = beat({ down = true })
             return ram(0x1B10) == (tonumber(os.getenv("MENU") or "1")) end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 150 end,
  function() pulse[0] = {}; return sf > 20 end,
  -- who confirms the SECOND character depends on the mode: in 2P VS it is P2's
  -- pad, in 1P-vs-COM P1 picks the opponent too (P2's pad is inert there — the
  -- same trap that stalls probe_p11_nav at Practice char-select).
  function()
    if (tonumber(os.getenv("MENU") or "1")) == 1 then
      pulse[1] = beat({ a = true }); return ram(0x1B82) == 1 or sf > 150
    end
    pulse[0] = beat({ a = true }); return sf > 150
  end,
  function() pulse[0] = {}; pulse[1] = {}; return sf > 200 end,
  function()   -- settle on the config screen and record what it looks like
    if onscreen == 0 and sf < 900 then
      pulse[0] = (sf % 24 < 3) and { down = true } or {}
      return false
    end
    if onscreen == 0 then
      log(string.format("VOID: never reached the config screen — says nothing "
        .. "about ACS. state: $1B10=%d $8A=%02X $8D=%02X $1B42=%d $1B82=%d "
        .. "$0070=%d $01FA=%02X", ram(0x1B10), ram(0x8A), ram(0x8D),
        ram(0x1B42), ram(0x1B82), ram(0x70), ram(0x1FA)))
      local f = io.open(ENV.TRACE .. "acs_" .. TAG .. "_void.png", "wb")
      if f then f:write(emu.takeScreenshot()); f:close() end
      LOG:close(); emu.stop(2)
    end
    ctx.before = { menu = ram(0x8A), mode = ram(0x8D), row = w16(0x1B00) }
    local f = io.open(ENV.TRACE .. "acs_" .. TAG .. "_before.png", "wb")
    if f then f:write(emu.takeScreenshot()); f:close() end
    return sf > 40
  end,
  function() pulse[0] = beat({ select = true }); return sf > 40 end,   -- press SELECT
  function() pulse[0] = {}; return sf > 180 end,                        -- let it transition
  function()
    local after = { menu = ram(0x8A), mode = ram(0x8D), row = w16(0x1B00) }
    local f = io.open(ENV.TRACE .. "acs_" .. TAG .. "_after.png", "wb")
    if f then f:write(emu.takeScreenshot()); f:close() end
    log(string.format("ACS tag=%s  before: $8A=%02X $8D=%02X $1B00=%04X   "
      .. "after: $8A=%02X $8D=%02X $1B00=%04X   changed=%s",
      TAG, ctx.before.menu, ctx.before.mode, ctx.before.row,
      after.menu, after.mode, after.row,
      tostring(after.menu ~= ctx.before.menu or after.row ~= ctx.before.row)))
    log("screenshots -> traces/acs_" .. TAG .. "_{before,after}.png (gitignored)")
    local ks = {}
    for k in pairs(writes) do ks[#ks + 1] = k end
    table.sort(ks)
    log(string.format("  menu-state writes seen on this screen: %d", wn))
    for _, k in ipairs(ks) do log("    " .. k) end
    LOG:close(); emu.stop(0)
    return true
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then LOG:close(); emu.stop(0) end
  if frames > 6000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
