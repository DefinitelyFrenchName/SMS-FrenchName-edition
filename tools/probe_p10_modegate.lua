-- probe_p10_modegate.lua — does patch 10b's LABEL pipeline respect --modes?
--
-- `--modes` restricts the combo HUD to a set of game modes. The excluded path
-- blanks the counters and jumps to `dorender`, but the label chain is
-- concatenated AFTER the render blocks, so it kept running in an excluded mode
-- (#86). Default `--modes` is 0,1,2,4,5 — so the mode this actually bites in is
-- **3, TOURNAMENT**.
--
-- Method: replay test_labels' PUNISH scenario (the one known to raise a label),
-- with `$008D` poked to the mode under test, and watch the two label cells in
-- VRAM for the whole window.
--
--   MODE=3 ROM=<10b build> tools/run.sh tools/probe_p10_modegate.lua 200   # excluded
--   MODE=1 ROM=<10b build> tools/run.sh tools/probe_p10_modegate.lua 200   # included
--
-- MODE=1 is the POSITIVE CONTROL and matters as much as the excluded run: it
-- proves the scenario still produces a label at all, so "blank" in the excluded
-- run means "gated", not "the probe drew nothing".
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local MODE = tonumber(os.getenv("MODE") or "3")
local TAG = os.getenv("TAG") or ("mode" .. MODE)
local LOG = assert(io.open(ENV.TRACE .. "p10_modegate_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local VRAM = emu.memType.snesVideoRam
local function vword(w) return emu.read(w * 2, VRAM) + 256 * emu.read(w * 2 + 1, VRAM) end
local LCELL = { [0] = 0x10E5, [1] = 0x10F2 }
local BLANK = 0x2000
local function anyDrawn()
  for p = 0, 1 do
    for k = 0, 7 do if vword(LCELL[p] + k) ~= BLANK then return true end end
  end
  return false
end

local t, loaded = -1, false
local drawn, idSeen = false, {}
emu.addMemoryCallback(function()
  if not loaded then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_v07.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = PL.pad()
    if p == 0 and t >= 60 and t < 63 then b.down = true; b.x = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not loaded then return end
  t = t + 1
  -- the PUNISH scenario, verbatim from tools/test_labels_cfg.lua
  if t == 5 then wr(0x1021, 0x40) end
  if t == 6 then wr(0x10A1, 0x60) end
  if t == 82 then wr(0x1049, 0x5E) end
  -- the mode under test, re-poked: the game rewrites $008D on some transitions
  if t >= 4 then wr(0x8D, MODE) end
  if t >= 82 and t <= 150 then
    if anyDrawn() then drawn = true end
    for p = 0, 1 do
      local id = ram(0x0900 + p * 8 + 5)
      if id > 0 then idSeen[id] = true end
    end
  end
  if t == 160 then
    local ids = {}
    for k in pairs(idSeen) do ids[#ids + 1] = k end
    table.sort(ids)
    log(string.format("MODEGATE mode=%d $008D=%d label_ids={%s} vram=%s",
      MODE, ram(0x8D), table.concat(ids, ","), drawn and "DRAWN" or "BLANK"))
    LOG:close(); emu.stop(0)
  end
  if t > 400 then log("TIMEOUT"); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
