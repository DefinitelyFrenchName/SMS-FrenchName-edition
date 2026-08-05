-- probe_menu_vram.lua — dump the menu screen's font VRAM region so the tiles the
-- font upload actually delivers can be compared build-to-build, offline.
--
-- Patch 16's blocker was that the transfer covering the font region has a fixed
-- length ($3480 bytes, from the asset-table field at $C3:BF18) which stops at
-- tile $5A4 — short of the free tiles at $5C0-$5FF where the half-width glyphs
-- go. Extending that field is only believable if the bytes are then SEEN in
-- VRAM, so this dumps the region rather than trusting the DMA parameters.
--
--   TAG=clean ROM=<rom> tools/run.sh tools/probe_menu_vram.lua 400
-- Output: traces/menuvram_<TAG>.bin  (VRAM bytes $8000-$C000 = words $4000-$6000
--         = tiles $400-$5FF) and a short per-tile summary in menuvram_<TAG>.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram = PL.ram
local VRAM = emu.memType.snesVideoRam
local TAG = os.getenv("TAG") or "menuvram"
local LOG = assert(io.open(ENV.TRACE .. "menuvram_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local LO, HI = 0x4000 * 2, 0x6000 * 2      -- tiles $400 .. $5FF
local frames, step, sf = 0, 1, 0
local pulse, done = {}, false
local function beat(on) return (frames % 7) < 3 and on or {} end

-- Dump ON the font transfer, not at the end of the run. The region is reused:
-- a dump taken on the final screen showed data stopping at tile $45D on BOTH a
-- clean ROM and one with the length field raised, because by then a later,
-- smaller upload had overwritten it. The transfer we care about
-- (vram $4000, src $7E:C000) happens earlier in the navigation.
local MEM = emu.memType.snesMemory
-- TRIG selects which upload to dump after. $4000 is the config screen's own
-- font sheet; $5000 is the kanji block, which is where patch 16 puts the
-- half-width glyphs (block tiles $3C0+ -> VRAM $5C0+).
local TRIG = tonumber(os.getenv("TRIG") or "0x4000")
local armed = false
local function st() local ok, s = pcall(emu.getState); return ok and s or nil end
for b = 0x00, 0xBF do
  if b <= 0x3F or b >= 0x80 then
    local a = (b << 16) | 0x420B
    emu.addMemoryCallback(function(_, v)
      if (v or 0) == 0 or done or armed then return end
      local s = st(); if not s then return end
      local dp = s["cpu.d"] or 0
      local pc = ((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)
      if pc ~= 0x8092D2 then return end
      local function w(o)
        return (emu.read(dp + o, MEM) or 0) | ((emu.read(dp + o + 1, MEM) or 0) << 8)
      end
      local vad, len, src = w(0), w(2), w(4)
      local bank = emu.read(dp + 6, MEM) or 0
      if vad == TRIG then
        armed = true
        log(string.format("font transfer seen: vram=$%04X len=$%04X src=$%02X:%04X (frame %d)",
          vad, len, bank, src, frames))
      end
    end, emu.callbackType.write, a, a, emu.cpuType.snes, MEM)
  end
end

emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)

-- POSITIVE CONTROL. Comparing a clean ROM against one with only the LENGTH
-- raised proves nothing on its own: both source and destination are zero out
-- there, so the dumps come back identical whether or not the longer transfer
-- happened. So stamp a pattern into the source buffer PAST the clean transfer's
-- end ($7E:C000 + $3480) and see whether it lands in VRAM. It must appear only
-- when the length is raised.
local WRAM = emu.memType.snesWorkRam
local POKE = os.getenv("POKE") == "1"
local PAT_SRC = 0xF500                     -- $7E:F500 = source offset $3500
local function stamp()
  for i = 0, 0xFF do emu.write(PAT_SRC + i, 0xAA, WRAM) end
end

local function grab()
  done = true
  local f = assert(io.open(ENV.TRACE .. "menuvram_" .. TAG .. ".bin", "wb"))
  local chunk = {}
  for a = LO, HI - 1 do
    chunk[#chunk + 1] = string.char(emu.read(a, VRAM) or 0)
    if #chunk == 4096 then f:write(table.concat(chunk)); chunk = {} end
  end
  if #chunk > 0 then f:write(table.concat(chunk)) end
  f:close()
  -- summary: where does real data stop?
  local last, blank = -1, 0
  for t = 0, (HI - LO) // 32 - 1 do
    local any = false
    for b = 0, 31 do
      if (emu.read(LO + t * 32 + b, VRAM) or 0) ~= 0 then any = true; break end
    end
    if any then last = t else blank = blank + 1 end
  end
  log(string.format("MENUVRAM tag=%s tiles=$400..$5FF nonblank_last=$%03X blank=%d",
    TAG, 0x400 + last, blank))
  -- did the stamped pattern cross? source offset $3500 -> VRAM byte $3500 -> tile $5A8
  local n = 0
  for i = 0, 0xFF do if (emu.read(LO + 0x3500 + i, VRAM) or 0) == 0xAA then n = n + 1 end end
  log(string.format("PATTERN tag=%s bytes_of_$AA_at_tile_$5A8=%d/256", TAG, n))
  -- the half-width glyph region: VRAM tiles $5C0-$5FF
  local g = 0
  for t = 0x5C0, 0x5FF do
    for b = 0, 31 do
      if (emu.read(LO + (t - 0x400) * 32 + b, VRAM) or 0) ~= 0 then g = g + 1; break end
    end
  end
  log(string.format("GLYPHTILES tag=%s nonblank_in_$5C0..$5FF=%d/64", TAG, g))
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; if armed and not done then grab(); return true end
             if sf > 400 then log("FONT TRANSFER NEVER SEEN — probe problem, not a finding")
                             LOG:close(); emu.stop(1) end
             return false end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if POKE and not armed and frames > 600 then stamp() end
  if armed and not done then grab(); LOG:close(); emu.stop(0); return end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then LOG:close(); emu.stop(done and 0 or 1) end
  if frames > 6000 then log("TIMEOUT " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
