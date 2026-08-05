-- menuscreen_probe.lua — for a given menu screen: which FONT SHEET it uploads to
-- the font region, and where its text rows come from. Patch 16 needs both: the
-- sheet says whether the half-width glyphs are present on that screen, the rows
-- say what a translation has to edit.
--
-- The font region (VRAM word $4000) is served by FIVE different sheets across
-- the game, so "the glyphs are installed" is a per-screen claim, not a global one.
--
--   SCREEN=options ROM=<rom> tools/run.sh tools/menuscreen_probe.lua 400
-- SCREEN = options | tournament | vs        ($7E:1B10 cursor: 5 / 3 / 1)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram = PL.ram
local MEM = emu.memType.snesMemory
local SCREEN = os.getenv("SCREEN") or "options"
local CURSOR = ({ options = 5, tournament = 3, vs = 1, vscom = 2, practice = 4 })[SCREEN]
      or error("SCREEN must be options|tournament|vs|vscom|practice")
local OUT = os.getenv("SHOTDIR") or ENV.TRACE
local LOG = assert(io.open(ENV.TRACE .. "menuscreen_" .. SCREEN .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end
local frames, step, sf = 0, 1, 0
local pulse, seen, rows = {}, {}, {}
local function beat(on) return (frames % 7) < 3 and on or {} end
local function st() local ok, s = pcall(emu.getState); return ok and s or nil end
for b = 0x00, 0xBF do
  if b <= 0x3F or b >= 0x80 then
    local a = (b << 16) | 0x420B
    emu.addMemoryCallback(function(_, v)
      if (v or 0) == 0 then return end
      local s = st(); if not s then return end
      local dp = s["cpu.d"] or 0
      if (((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)) ~= 0x8092D2 then return end
      local function w(o) return (emu.read(dp+o,MEM) or 0) | ((emu.read(dp+o+1,MEM) or 0) << 8) end
      local vad, len, src, bank = w(0), w(2), w(4), emu.read(dp+6,MEM) or 0
      if len == 0 then return end
      if len > 0x0400 then          -- a SHEET upload, not a tilemap row
        seen[string.format("vram=$%04X len=$%04X src=$%02X:%04X", vad, len, bank, src)] = true
      elseif vad < 0x1000 then      -- tilemap rows: 32 cells = $40 bytes
        rows[string.format("src=$%02X:%04X len=$%04X", bank, src, len)] = true
      end
    end, emu.callbackType.write, a, a, emu.cpuType.snes, MEM)
  end
end
local STEPS = {
  function() return frames >= 900 end,
  function()  -- left column down to 1/2, then right for 3/4/5
    local want = (CURSOR >= 3) and (CURSOR - 3) or CURSOR
    if ram(0x1B10) == want then return true end
    pulse[0] = beat({ down = true }); return false
  end,
  function()
    if CURSOR < 3 then return true end
    pulse[0] = beat({ right = true }); return ram(0x1B10) == CURSOR
  end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 300 end,
  function()
    local f = io.open(OUT .. "menuscreen_" .. SCREEN .. ".png", "wb")
    if f then f:write(emu.takeScreenshot()); f:close() end
    -- VRAM too: the cell budget for a translation is a property of the TILEMAP,
    -- and it has to be read rather than counted off a screenshot.
    local vf = io.open(OUT .. "menuscreen_" .. SCREEN .. ".vram", "wb")
    if vf then
      local c = {}
      for i = 0, 0xFFFF do
        c[#c + 1] = string.char(emu.read(i, emu.memType.snesVideoRam) or 0)
        if #c == 4096 then vf:write(table.concat(c)); c = {} end
      end
      if #c > 0 then vf:write(table.concat(c)) end
      vf:close()
    end
    log("SCREEN=" .. SCREEN .. " cursor=" .. ram(0x1B10))
    log("  sheet uploads (len > $400):")
    local k = {}; for s_ in pairs(seen) do k[#k+1] = s_ end; table.sort(k)
    for _, l in ipairs(k) do log("    " .. l) end
    log("  tilemap-row sources:")
    k = {}; for s_ in pairs(rows) do k[#k+1] = s_ end; table.sort(k)
    for _, l in ipairs(k) do log("    " .. l) end
    return true
  end,
}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then LOG:close(); emu.stop(0) end
  if frames > 4000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
