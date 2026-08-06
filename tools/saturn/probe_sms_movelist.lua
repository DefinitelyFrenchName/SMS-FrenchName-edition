-- probe_sms_movelist.lua — where does the per-character MOVELIST come from?
-- (task #41: Saturn's list shows mostly the shell's and is incomplete.)
--
-- Known: in Practice the whole BG3 tilemap holds the pre-staged command list for
-- P1's character, invisible because TM = 0x13; Start flips it on ($01FA 0x80 ->
-- 0xE4) and RESTAGES the entire layer on every press. So the staging is a
-- routine that runs on demand, which makes it easy to catch in the act.
--
-- This reaches Practice, presses Start, and records:
--   * who writes $01FA (the open/close toggle) — the entry point to the flow;
--   * every VRAM DMA while the list is being staged, with its ROM source, and
--     every direct $2118/$2119 write burst with the PC that made it;
--   * the BG3 tilemap afterwards, dumped for offline diffing.
--
-- Run for two characters and diff the dumps and the sources: what changes is the
-- per-character movelist data, which is what Saturn needs her own of.
--
-- usage: CHAR=6 ROM=<rom> tools/run.sh tools/saturn/probe_sms_movelist.lua 600
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "6")
local DUMMY = tonumber(os.getenv("DUMMY") or "4")
local TAG = os.getenv("TAG") or ("ml" .. (os.getenv("CHAR") or "6"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/movelist_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local MEM = emu.memType.snesMemory
local WRAM = emu.memType.snesWorkRam
local VRAM = emu.memType.snesVideoRam
local function reg(a) return emu.read(0x800000 + a, MEM) end
local function pc()
  local ok, s = pcall(emu.getState)
  if not ok or not s then return 0, 0 end
  return (s["cpu.k"] or 0), (s["cpu.pc"] or 0)
end

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end
local function slowbeat(on) return (frames % 20) < 4 and on or {} end

local watching = false
local lastfa = -1

-- who toggles $01FA
for _, r in ipairs({ { 0x7E01FA, 0x7E01FA }, { 0x0001FA, 0x0001FA } }) do
  emu.addMemoryCallback(function(_, v)
    if not watching or (v or 0) == lastfa then return end
    lastfa = v or 0
    local k, p = pc()
    log(string.format("  f%-5d $01FA <= $%02X   from %02X:%04X", frames, v or 0, k, p))
  end, emu.callbackType.write, r[1], r[2], emu.cpuType.snes, MEM)
end

-- the asset loader itself: $C0:853D takes DP $00 = src, $02 = src bank,
-- $03 = VRAM word address, A = flag (docs/saturn/supers_assets.md). Catching it
-- names the exact asset RECORD the movelist stages, which is what a Saturn
-- override has to replace.
for _, a in ipairs({ 0x00853D, 0x80853D, 0xC0853D }) do
  emu.addMemoryCallback(function()
    if not watching then return end
    local k, p = pc()
    local function r(x) return emu.read(0x7E0000 + x, MEM) end
    log(string.format("  f%-5d ASSET LOAD src $%02X:%02X%02X -> VRAM $%02X%02X flag $%02X"
      .. "   caller %02X:%04X",
      frames, r(0x02), r(0x01), r(0x00), r(0x04), r(0x03),
      (select(2, pcall(emu.getState)) or {})["cpu.a"] and
        ((select(2, pcall(emu.getState))["cpu.a"]) & 0xFF) or 0, k, p))
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, MEM)
end

-- VRAM address latch + DMA
local vaddr = 0
for _, b in ipairs({ 0x002116, 0x802116 }) do
  emu.addMemoryCallback(function(_, v) vaddr = (vaddr & 0xFF00) | (v or 0) end,
    emu.callbackType.write, b, b, emu.cpuType.snes, MEM)
  emu.addMemoryCallback(function(_, v) vaddr = (vaddr & 0x00FF) | ((v or 0) << 8) end,
    emu.callbackType.write, b + 1, b + 1, emu.cpuType.snes, MEM)
end
local ndma = 0
for _, b in ipairs({ 0x00420B, 0x80420B }) do
  emu.addMemoryCallback(function(_, v)
    if not watching or (v or 0) == 0 or ndma > 40 then return end
    for ch = 0, 7 do
      if ((v >> ch) & 1) == 1 then
        local c = 0x4300 + ch * 0x10
        local bbus = reg(c + 1)
        if bbus == 0x18 or bbus == 0x19 then
          ndma = ndma + 1
          local k, p = pc()
          log(string.format("  f%-5d VRAM DMA $%04X <- $%02X:%02X%02X len $%02X%02X  @%02X:%04X",
            vaddr, reg(c + 4), reg(c + 3), reg(c + 2), reg(c + 6), reg(c + 5), k, p))
        end
      end
    end
  end, emu.callbackType.write, b, b, emu.cpuType.snes, MEM)
end
-- direct tilemap writes, aggregated by the writing PC
local wr2118 = {}
for _, b in ipairs({ 0x002118, 0x802118, 0x002119, 0x802119 }) do
  emu.addMemoryCallback(function()
    if not watching then return end
    local k, p = pc()
    local key = string.format("%02X:%04X", k, p)
    wr2118[key] = (wr2118[key] or 0) + 1
  end, emu.callbackType.write, b, b, emu.cpuType.snes, MEM)
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = slowbeat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = slowbeat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = {}; return sf > 10 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() wr(0x1B40, CHAR); wr(0x1B80, DUMMY); return sf > 20 end,
  function()   -- SAT=1 holds L+R at confirm to summon her
    local b = beat({ a = true })
    if (os.getenv("SAT") or "0") ~= "0" then b.l = true; b.r = true end
    pulse[0] = b
    return ram(0x1B42) == 1 or sf > 90
  end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    -- watch from the MATCH LOAD, not from the Start press: no asset-loader call
    -- happens at Start, so the movelist is pre-staged with the rest of the
    -- match's graphics and Start only flips the layer on
    if sf == 1 then
      watching = true
      log("=== watching from the match load ===")
    end
    wr(0x1B80, DUMMY)
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x1000) == CHAR and ram(0x1080) ~= 0 then return true end
    if sf > 900 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return sf > 180 and ram(0x1001) == 0 end,
  function()
    if sf == 1 then
      log(string.format("=== Practice, P1 char %d — pressing Start ===", ram(0x1000)))
      log(string.format("  $01FA = $%02X before", ram(0x01FA)))
    end
    if sf >= 5 and sf <= 8 then pulse[0] = { start = true } else pulse[0] = {} end
    return sf > 150
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("  $01FA = $%02X after", ram(0x01FA)))
    log("--- direct VRAM writers (PC -> count) ---")
    for k, n in pairs(wr2118) do log(string.format("  %s  x%d", k, n)) end
    -- BG3 tilemap: dump a generous window, plus the whole of VRAM for diffing
    local f = assert(io.open(ENV.TRACE .. "saturn/vram_" .. TAG .. ".bin", "wb"))
    local t = {}
    for a = 0, 0xFFFF do t[#t + 1] = string.char(emu.read(a, VRAM)) end
    f:write(table.concat(t)); f:close()
    local wf = assert(io.open(ENV.TRACE .. "saturn/wram_" .. TAG .. ".bin", "wb"))
    local wt = {}
    for x = 0, 0x1FFFF do wt[#wt + 1] = string.char(emu.read(x, WRAM)) end
    wf:write(table.concat(wt)); wf:close()
    local sfp = io.open(ENV.TRACE .. "saturn/movelist_" .. TAG .. ".png", "wb")
    if not sfp then print("probe_sms_movelist.lua: cannot open " .. (ENV.TRACE .. "saturn/movelist_" .. TAG .. ".png")) emu.stop(1) return end
    sfp:write(emu.takeScreenshot()); sfp:close()
    log("VRAM + screenshot dumped")
    log("done")
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_movelist loaded")
