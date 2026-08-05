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

-- Which ROW handler is live? The config screen dispatches the handler for the
-- CURRENT row each frame (table $C3:A839), so an exec hook on the モード row's
-- handler is the precondition for testing patch 15 the same way $AA38 is for the
-- stage row.
local moderow = 0
emu.addMemoryCallback(function() moderow = moderow + 1 end,
  emu.callbackType.exec, 0x83A849, 0x83A849, emu.cpuType.snes, emu.memType.snesMemory)

-- Savestates must be taken from a CPU-exec context: emu.createSavestate() THROWS
-- inside an endFrame callback (measured — it returned an error and left a
-- 0-byte file). $80:8353 is the input-poll site, which is both a valid context
-- and the exact point test_regression.lua loads states from, so a state taken
-- here is one that suite can restore.
local wantSave = false
emu.addMemoryCallback(function()
  if not wantSave then return end
  wantSave = false
  local ss = emu.createSavestate()
  local f = assert(io.open(ENV.TRACE .. os.getenv("SAVE"), "wb"))
  f:write(ss); f:close()
  log(string.format("saved traces/%s  len=%d  $8D=%d P1row=%d",
    os.getenv("SAVE"), #ss, ram(0x8D), ram(0x1800) | (ram(0x1801) << 8)))
  LOG:close(); emu.stop(0)
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

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
    -- Detect the screen by its MODE row handler, which runs as soon as the
    -- screen is up (both columns start on row 0). The stage-row hook would work
    -- too but only after walking the cursor down, which is the wrong place to
    -- leave it: patch 15's test needs P1 on row 0 and a savestate taken here is
    -- the fixture for both config-screen tests.
    if moderow == 0 and sf < 900 then
      pulse[0] = {}
      return false
    end
    if moderow == 0 then
      log(string.format("VOID: never reached the config screen — says nothing "
        .. "about ACS. state: $1B10=%d $8A=%02X $8D=%02X $1B42=%d $1B82=%d "
        .. "$0070=%d $01FA=%02X", ram(0x1B10), ram(0x8A), ram(0x8D),
        ram(0x1B42), ram(0x1B82), ram(0x70), ram(0x1FA)))
      local f = io.open(ENV.TRACE .. "acs_" .. TAG .. "_void.png", "wb")
      if f then f:write(emu.takeScreenshot()); f:close() end
      LOG:close(); emu.stop(2)
    end
    -- SAVE=<name>: write a savestate here, on the config screen with the cursor
    -- at its default row — the fixture the regression suite needs for the two
    -- config-screen patches (15 and 18). Made on the CLEAN ROM so it loads for
    -- every build; the headless runner is permissive about the ROM tag.
    if os.getenv("SAVE") then
      if sf < 30 then return false end        -- let the screen settle first
      wantSave = true                          -- the exec hook does the writing
      return false
    end
    -- MODEROW=1: mash RIGHT on the モード row instead of pressing SELECT, and
    -- report the per-column mode cells so patch 15 has a testable observable.
    if os.getenv("MODEROW") == "1" then
      -- snapshot the whole menu block rather than the two cells the disassembly
      -- suggests: "which byte is the mode" is exactly the kind of guess that
      -- turns a green test into a meaningless one
      ctx.m0 = {}
      for a = 0x1800, 0x18FF do ctx.m0[a] = ram(a) end
    end
    ctx.before = { menu = ram(0x8A), mode = ram(0x8D), row = w16(0x1B00) }
    local f = io.open(ENV.TRACE .. "acs_" .. TAG .. "_before.png", "wb")
    if f then f:write(emu.takeScreenshot()); f:close() end
    return sf > 40
  end,
  function()
    if os.getenv("MODEROW") == "1" then
      -- the nav walks DOWN to find the screen, so the cursor sits on the stage
      -- row; climb back to row 0 (モード) before pressing RIGHT, or this
      -- measures the stage list instead
      -- Each COLUMN has its own cursor: $1800 is P1's row index, $1880 is P2's
      -- (dispatch at $C3:A7F7, `ldx $1B00 / lda $0000,x / jmp ($A839,x)`), and
      -- the mode-row handler fires for whichever column sits on row 0. So the
      -- handler running proves nothing about P1 — climb until P1's OWN row is 0.
      if w16(0x1800) ~= 0 then
        pulse[0] = (sf % 12 < 3) and { up = true } or {}
        return false
      end
      -- arrived on row 0: snapshot again (the climb itself moved things) and
      -- then give RIGHT a real window
      if not ctx.arrived then
        ctx.arrived = sf
        for a = 0x1800, 0x18FF do ctx.m0[a] = ram(a) end
      end
      -- ONE press. The row has two values (マニュアル / オート), so mashing
      -- lands on either depending on parity — an even count reads exactly like
      -- "the row is inert", which is the thing under test.
      local n = sf - ctx.arrived
      pulse[0] = (n >= 20 and n < 24) and { right = true } or {}
      return n > 90
    end
    pulse[0] = beat({ select = true }); return sf > 40                  -- press SELECT
  end,
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
    if ctx.m0 then
      local ch = {}
      for a = 0x1800, 0x18FF do
        if ram(a) ~= ctx.m0[a] then
          ch[#ch + 1] = string.format("$%04X %d->%d", a, ctx.m0[a], ram(a))
        end
      end
      log(string.format("MODEROW tag=%s handler_hits=%d changed=%d  %s", TAG,
        moderow, #ch, table.concat(ch, " ")))
    end
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
