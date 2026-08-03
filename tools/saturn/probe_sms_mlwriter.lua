-- probe_sms_mlwriter.lua — WHO writes the per-character movelist text?
--
-- Established by probe_sms_movelist.lua: the movelist lives in BG3, is staged
-- during the MATCH LOAD (not at the Start press — Start only flips the layer
-- on), and the three compressed assets loaded then are IDENTICAL for every
-- character ($E2:0F70 -> WRAM, $E0:695F -> VRAM word $6000, $E0:6D09 -> VRAM
-- word $1000). So those are the frame and the font, and the per-character text
-- is drawn afterwards, as font tile indices, straight into the tilemap — the
-- indices appear nowhere in ROM verbatim (a whole-ROM delta search, which is
-- immune to a constant offset, found nothing) and nowhere in WRAM either.
--
-- This watches the VRAM address latch and records every $2118/$2119 write made
-- while the latch is inside the movelist tilemap window, with the PC that made
-- it — which names the renderer, the thing that knows where the text comes from.
--
-- usage: CHAR=6 ROM=<rom> tools/run.sh tools/saturn/probe_sms_mlwriter.lua 400
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "6")
local DUMMY = tonumber(os.getenv("DUMMY") or "4")
local TAG = os.getenv("TAG") or ("w" .. (os.getenv("CHAR") or "6"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/mlwriter_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local MEM = emu.memType.snesMemory
-- the movelist tilemap, as WORD addresses (VRAM byte $2000-$2800)
local LO, HI = 0x1000, 0x1400

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end
local function slowbeat(on) return (frames % 20) < 4 and on or {} end

local watching = false
local vaddr, inwin = 0, false
local writers, nlog = {}, 0
local sample = {}

local function pc()
  local ok, s = pcall(emu.getState)
  if not ok or not s then return 0, 0 end
  return (s["cpu.k"] or 0), (s["cpu.pc"] or 0)
end

for _, b in ipairs({ 0x002116, 0x802116 }) do
  emu.addMemoryCallback(function(_, v) vaddr = (vaddr & 0xFF00) | (v or 0) end,
    emu.callbackType.write, b, b, emu.cpuType.snes, MEM)
  emu.addMemoryCallback(function(_, v)
    vaddr = (vaddr & 0x00FF) | ((v or 0) << 8)
    local was = inwin
    inwin = (vaddr >= LO and vaddr < HI)
    if watching and inwin and not was and nlog < 60 then
      local k, p = pc()
      nlog = nlog + 1
      log(string.format("  f%-5d latch VRAM word $%04X   from %02X:%04X", frames, vaddr, k, p))
    end
  end, emu.callbackType.write, b + 1, b + 1, emu.cpuType.snes, MEM)
end
-- Two VRAM-DMA helpers exist; the movelist uses the DP $30 one ($C0:9287 —
-- $30 = VRAM word address, $32 = length, $34/$36 = source address/bank), which
-- the latch PC ($C0:9295) identifies. Catching it at the $420B kick gives the
-- real source of the tilemap: for a flag-2 asset that is the staging buffer
-- AFTER whatever wrote the per-character text into it.
local dumped = 0
for _, a in ipairs({ 0x0092A9, 0x8092A9, 0xC092A9 }) do
  emu.addMemoryCallback(function()
    if not watching then return end
    local function r16(x) return emu.read(0x7E0000 + x, MEM) + 256 * emu.read(0x7E0001 + x, MEM) end
    local dest, len, src, bank = r16(0x30), r16(0x32), r16(0x34), emu.read(0x7E0036, MEM)
    if dest < LO or dest >= HI then return end
    log(string.format("  f%-5d DMA VRAM word $%04X <- $%02X:%04X len $%04X",
      frames, dest, bank, src, len))
    if dumped < 6 then
      dumped = dumped + 1
      local f = assert(io.open(ENV.TRACE .. "saturn/mlsrc_" .. TAG .. "_" .. dumped .. ".bin", "wb"))
      local t = {}
      for x = 0, len - 1 do t[#t + 1] = string.char(emu.read(bank * 0x10000 + src + x, MEM)) end
      f:write(table.concat(t)); f:close()
      log(string.format("      dumped %d bytes of the source", len))
    end
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, MEM)
end

-- The text is built in the staging buffer $7F:0000 and carried by the SECOND
-- DMA (the first is the blank template). Watching the name row inside that
-- buffer names the RENDERER — the thing that knows where the text comes from.
-- ($7F:0000 is work-RAM offset $10000, so the name row is $10146.)
local vhits = 0
emu.addMemoryCallback(function(addr, v)
  -- only the pass that carries the TEXT: the first fills the blank template
  -- the buffer is reused by every decompression, so pin the ONE write that puts
  -- the name's first tile ($B0 = 'S') at its row offset — that is the renderer
  if not watching or vhits > 16 then return end
  if (v or 0) ~= 0xB0 then return end
  vhits = vhits + 1
  local k, p = pc()
  log(string.format("  f%-5d $7F:%04X <= $%02X   from %02X:%04X",
    frames, addr - 0x10000, v or 0, k, p))
end, emu.callbackType.write, 0x10146, 0x10147, emu.cpuType.snes, emu.memType.snesWorkRam)

-- $C0:916B is the generic "expand this manifest entry" codec (the char loader
-- calls it directly, outside the $C0:853D asset-record path). DP $00/$02 hold
-- the source pointer. The name tile lands via its output loop, so the call that
-- precedes it carries the per-character movelist source.
for _, a in ipairs({ 0x00916B, 0x80916B, 0xC0916B }) do
  emu.addMemoryCallback(function()
    if not watching then return end
    local function r(x) return emu.read(0x7E0000 + x, MEM) end
    log(string.format("  f%-5d EXPAND src $%02X:%02X%02X  dst $%02X%02X/$%02X%02X",
      frames, r(0x02), r(0x01), r(0x00), r(0x04), r(0x03), r(0x06), r(0x05)))
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, MEM)
end

for _, b in ipairs({ 0x002118, 0x802118, 0x002119, 0x802119 }) do
  emu.addMemoryCallback(function(_, v)
    if not watching or not inwin then return end
    local k, p = pc()
    local key = string.format("%02X:%04X", k, p)
    writers[key] = (writers[key] or 0) + 1
    if #sample < 48 then sample[#sample + 1] = string.format("%02X", v or 0) end
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
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    if sf == 1 then watching = true; log("=== watching from the match load ===") end
    wr(0x1B80, DUMMY)
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x1000) == CHAR and ram(0x1080) ~= 0 then return true end
    if sf > 900 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return sf > 120 and ram(0x1001) == 0 end,
  -- and now the Start press: the earlier probe saw no ASSET LOAD there, but the
  -- asset loader is not the only path into this DMA helper
  function()
    if sf == 1 then log("=== pressing Start ===") end
    if sf >= 5 and sf <= 8 then pulse[0] = { start = true } else pulse[0] = {} end
    return sf > 150
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log("--- writers into the movelist tilemap window ---")
    for k, n in pairs(writers) do log(string.format("  %s  x%d", k, n)) end
    log("first values written: " .. table.concat(sample, " "))
    log("done"); emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_mlwriter loaded")
