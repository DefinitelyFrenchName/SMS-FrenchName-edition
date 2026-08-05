-- probe_saturn_fxvram.lua — dump the RAW state behind Saturn's 214P projectile
-- (VRAM + OAM + CGRAM) so the analysis can happen offline, in Python, against
-- her decompressed effect sheet.
--
-- WHY THIS EXISTS. The earlier "root signature" measurement
-- (probe_saturn_projtiles.lua) resolved a sprite's tile data as `tile * 32`,
-- i.e. it assumed the OBJ name base is VRAM 0. The project's own notes say her
-- effect tiles live at VRAM word $6A00 with tile base $A0, which means an OBJ
-- name base of word $6000 — so `tile * 32` reads a completely different part of
-- VRAM and "blank" said nothing about her tiles. This probe therefore asserts
-- NOTHING about where things live: it dumps all of VRAM and lets the analyzer
-- FIND her sheet by content. If the sheet is present, the analyzer says where
-- and how much; if it is truncated, it says exactly where it stops.
--
-- The instrument is validated by the control, not by hope: run it with
-- SATURN=0 to capture the plain shell in the same scripted moment. The shell's
-- own effect sheet is known-good by construction (vanilla), so a run that
-- cannot locate an intact effect sheet in the CONTROL dump is a broken probe,
-- not a finding.
--
--   SHELL_ID=6 TAG=v149 ROM=<build> tools/run.sh tools/saturn/probe_saturn_fxvram.lua 700
--   SHELL_ID=6 TAG=ctl SATURN=0 ROM=<build> tools/run.sh tools/saturn/probe_saturn_fxvram.lua 700
--
-- Outputs (traces/saturn/): fxvram_<TAG>.bin (64K VRAM), fxoam_<TAG>.bin (544B),
-- fxcgram_<TAG>.bin (512B), fxvram_<TAG>.txt (log + PPU/slot context).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
local SATURN = os.getenv("SATURN") ~= "0"
local TAG = os.getenv("TAG") or "fxvram"
local OUT = ENV.TRACE .. "saturn/"
local LOG = assert(io.open(OUT .. "fxvram_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local OAM, VRAM, CG = emu.memType.snesSpriteRam, emu.memType.snesVideoRam, emu.memType.snesCgRam
local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local captured = false

local function beat(on) return (frames % 7) < 3 and on or {} end
local function setchars() wr(0x1B40, SHELL); wr(0x1B80, 4) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and SATURN and p == 0 then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local function dump(name, mt, len)
  local f = assert(io.open(OUT .. name .. "_" .. TAG .. ".bin", "wb"))
  local chunk = {}
  for i = 0, len - 1 do
    chunk[#chunk + 1] = string.char(emu.read(i, mt) or 0)
    if #chunk == 4096 then f:write(table.concat(chunk)); chunk = {} end
  end
  if #chunk > 0 then f:write(table.concat(chunk)) end
  f:close()
  log(string.format("dumped %s_%s.bin (%d bytes)", name, TAG, len))
end

local function capture(why)
  captured = true
  log("=== " .. why .. " (frame " .. frames .. ") ===")
  log(string.format("saturn=%s shell=%d", tostring(SATURN), SHELL))
  log(string.format("proj slots: $1100 id=%02X  $1180 id=%02X", ram(0x1100), ram(0x1180)))
  log(string.format("p1 char=%02X act=%02X   proj +08=%02X",
    ram(0x1000), ram(0x1001), ram(0x1108)))
  -- Every live OAM entry, verbatim. Which of them are hers is an offline
  -- question -- resolving it here is what went wrong last time.
  local n = 0
  for i = 0, 127 do
    if (emu.read(i * 4 + 1, OAM) or 0xE0) < 0xE0 then n = n + 1 end
  end
  log(string.format("live OAM entries: %d", n))
  dump("fxvram", VRAM, 0x10000)
  dump("fxoam", OAM, 0x220)
  dump("fxcgram", CG, 0x200)
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
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
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 150 end,
  function()
    -- 214+LP on a loop. The CONTROL (SATURN=0) has no such move, so it captures
    -- on a timer instead -- the effect sheet is in VRAM either way, and the
    -- point of the control is the SHEET, not the projectile.
    local m = sf % 60
    if m < 6 then pulse[0] = { down = true }
    elseif m < 12 then pulse[0] = { down = true, left = true }
    elseif m < 18 then pulse[0] = { left = true }
    elseif m < 22 then pulse[0] = { y = true }
    else pulse[0] = {} end
    if not captured then
      if SATURN then
        -- Capture on a frame that ACTUALLY HOLDS her sprites. The sprite list
        -- is emitted on alternate frames, so a "+20 frames after the slot
        -- populates" trigger lands on an empty frame half the time -- which is
        -- how an earlier capture came back with zero palette-7 entries and
        -- three unrelated sprites that looked like the projectile.
        local n7 = 0
        for i = 0, 127 do
          if (emu.read(i * 4 + 1, OAM) or 0xE0) < 0xE0
             and ((emu.read(i * 4 + 3, OAM) or 0) >> 1) % 8 == 7 then n7 = n7 + 1 end
        end
        if n7 >= 8 then capture("projectile drawn: " .. n7 .. " palette-7 sprites") end
      elseif sf > 120 then
        capture("control, no projectile needed")
      end
    end
    return captured and sf > 0 or sf > 900
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    if not captured then log("NO CAPTURE — harness problem, not a finding") end
    emu.stop(captured and 0 or 1)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)
