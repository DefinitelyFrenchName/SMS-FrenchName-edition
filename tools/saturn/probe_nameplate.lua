-- probe_nameplate.lua — find the code that draws the in-match NAMEPLATE (the
-- character name under the health bar), which currently shows the SHELL's name
-- when Saturn is playing.
--
-- Known ground (docs/annotations.md, sms_engine_internals.md): the HUD is BG3,
-- tilemap base VRAM word $1000; row 5 holds the nameplates (cells around $10A2);
-- letter tile ids run A=$70 .. Z=$89, but the GLYPHS are matchup-loaded, not a
-- resident alphabet — "G" is in no character's name.
--
-- Method: shadow $2116/$2117 across every register mirror and log CPU writes to
-- $2118/$2119 whose VRAM address falls in the nameplate window. DMA does not
-- surface as a VRAM write callback, and the DMA registers are write-only, so the
-- port-write route is the one that works here (this cost four probes on the menu
-- font before it was believed).
--
-- INSTRUMENT CHECK FIRST: the probe reports the TOTAL number of port writes it
-- saw before any filtering, and the letter-range hit count. A zero in the window
-- with a zero total means the hook is dead, not that the game does not draw.
--
--   SHELL_ID=7 SATURN=1 ROM=<build> tools/run.sh tools/saturn/probe_nameplate.lua 700
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 7)
local SATURN = os.getenv("SATURN") ~= "0"
local TAG = os.getenv("TAG") or ("np_" .. (SATURN and "sat" or "van") .. SHELL)
local LOG = assert(io.open(ENV.TRACE .. "saturn/" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local MEM = emu.memType.snesMemory
local LO, HI = num("WLO", 0x1080), num("WHI", 0x10E0)
local vlo, vhi = 0, 0
local total, inwin = 0, 0
local seen, order = {}, {}
local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false

local function pcnow()
  local ok, s = pcall(emu.getState)
  if not (ok and s) then return -1 end
  return ((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)
end

for b = 0x00, 0xBF do
  if b <= 0x3F or b >= 0x80 then
    local a = (b << 16) | 0x2116
    emu.addMemoryCallback(function(_, v) vlo = v or 0 end,
      emu.callbackType.write, a, a, emu.cpuType.snes, MEM)
    a = (b << 16) | 0x2117
    emu.addMemoryCallback(function(_, v) vhi = v or 0 end,
      emu.callbackType.write, a, a, emu.cpuType.snes, MEM)
    for _, r in ipairs({ 0x2118, 0x2119 }) do
      a = (b << 16) | r
      emu.addMemoryCallback(function(_, v)
        total = total + 1
        local addr = vlo | (vhi << 8)
        if addr < LO or addr >= HI then return end
        inwin = inwin + 1
        local p = pcnow()
        local key = string.format("$%06X", p)
        if not seen[key] then seen[key] = { n = 0, sample = {} }; order[#order + 1] = key end
        local e = seen[key]
        e.n = e.n + 1
        if #e.sample < 14 then
          e.sample[#e.sample + 1] = string.format("[$%04X]=$%02X", addr, v or 0)
        end
      end, emu.callbackType.write, a, a, emu.cpuType.snes, MEM)
    end
  end
end

local function beat(on) return (frames % 7) < 3 and on or {} end
local function setchars() wr(0x1B40, SHELL); wr(0x1B80, 4) end
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and SATURN and p == 0 then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local STEPS = {
  function() return frames >= 900 end,
  -- ROW 2 = 1P-vs-COM. Practice (row 4) draws NO nameplates at all, so the
  -- earlier captures had no HUD in frame and could not answer anything.
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == num("ROW", 2) end,
  function() return true end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() setchars(); hold = true; return sf > 20 end,
  function() setchars(); pulse[0] = beat({ a = true })
             return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    setchars()
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function()
    pulse[0] = {}
    -- screenshot LATE: the earlier probes captured during the round intro, when
    -- the HUD is not drawn yet, so the nameplate was not in frame at all
    if sf == 380 then
      local f = io.open(ENV.TRACE .. "saturn/" .. TAG .. ".png", "wb")
      if f then f:write(emu.takeScreenshot()); f:close() end
    end
    return sf > 400
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("p1=%02X shell=%d saturn=%s", ram(0x1000), SHELL, tostring(SATURN)))
    log(string.format("TOTAL VRAM port writes: %d ; in nameplate window $%04X-$%04X: %d",
      total, LO, HI, inwin))
    if total == 0 then log("HOOK IS DEAD — not a finding") end
    for _, k in ipairs(order) do
      local e = seen[k]
      log(string.format("  by PC %s : %d writes   %s", k, e.n, table.concat(e.sample, " ")))
    end
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)
