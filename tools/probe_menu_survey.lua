-- probe_menu_survey.lua — enumerate the game's MENU SCREENS and the text on
-- them, as the groundwork for a translation patch (see docs/menu_text.md).
--
-- The translation is a standalone patch, not a Saturn feature, so this lives in
-- tools/ rather than tools/saturn/.
--
-- What it does: boots, taps Start (and optionally a scripted key sequence) to
-- walk the front-end, and at every capture point writes
--   traces/menu/<TAG>_<frame>.png    the screen
--   traces/menu/<TAG>_<frame>.map    BG1-BG4 tilemaps + CHR bases + BGMODE
-- so a string can be traced from a pixel back to the tile indices that drew it,
-- which is what decides whether a screen is FONT TILES (cheap to retranslate,
-- like the movelist) or BAKED ART (needs redrawn tiles).
--
-- usage: TAG=clean ROM=<rom> tools/run.sh tools/probe_menu_survey.lua 300
--        KEYS="start:200 down:260 a:300"   optional scripted presses (frame)
-- NB: flat tools/ scripts bootstrap with "/sms_env.lua"; only tools/saturn/
-- ones need the "/../" (this cost a silent load failure — no error, no print)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local TAG = os.getenv("TAG") or "clean"
local EVERY = tonumber(os.getenv("EVERY") or "60")
local UNTIL = tonumber(os.getenv("UNTIL") or "4000")
local DIR = ENV.TRACE .. "menu/"   -- create it from the shell; os.execute is not
                                   -- reliable inside the emulator sandbox
local LOG = assert(io.open(DIR .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram
local MEMT = emu.memType.snesMemory

-- scripted presses: "start:200 down:260" = tap start at frame 200, down at 260
local KEYS = {}
for k, f in (os.getenv("KEYS") or ""):gmatch("(%a+):(%d+)") do
  KEYS[tonumber(f)] = k
end

local frames = 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)

local function ppu()
  local ok, s = pcall(emu.getState)
  if not ok or not s then return nil end
  return s
end

local function dump_maps(f)
  local s = ppu()
  local out = assert(io.open(string.format("%s%s_%04d.map", DIR, TAG, f), "wb"))
  local hdr = {}
  for i = 0, 3 do
    hdr[#hdr + 1] = string.format("BG%d map=%04X chr=%04X size=%s", i + 1,
      s and s[string.format("ppu.layers[%d].tilemapAddress", i)] or 0,
      s and s[string.format("ppu.layers[%d].chrAddress", i)] or 0,
      tostring(s and s[string.format("ppu.layers[%d].doubleWidth", i)]))
  end
  out:write("# " .. table.concat(hdr, " | ") .. "\n")
  out:write(string.format("# mode=%s mainScreen=%s frame=%d\n",
    tostring(s and s["ppu.bgMode"]), tostring(s and s["ppu.mainScreenLayers"]), f))
  -- the four 2 KB tilemap windows the front-end actually uses
  for _, base in ipairs({ 0x0000, 0x0800, 0x1000, 0x1800 }) do
    local t = {}
    for a = base, base + 0x7FF do
      t[#t + 1] = string.char(emu.read(a, emu.memType.snesVideoRam) or 0)
    end
    out:write(table.concat(t))
  end
  -- and the CHR the text is drawn from: whether the menu font already has a
  -- full Latin alphabet decides whether a translation is a tilemap edit or a
  -- glyph-authoring job
  local chr = assert(io.open(string.format("%s%s_%04d.chr", DIR, TAG, f), "wb"))
  -- the WHOLE of VRAM: the CHR base the PPU reports is a word address, so the
  -- tiles a menu uses can sit anywhere (the config screen's reach past $9000)
  local c = {}
  for a = 0x0000, 0xFFFF do c[#c + 1] = string.char(emu.read(a, emu.memType.snesVideoRam) or 0) end
  chr:write(table.concat(c)); chr:close()
  out:close()
end

-- Every asset the front-end loads. Hook the DECOMPRESSOR ENTRY $C0:916B, not
-- the asset-record loader's tail at $C0:8561 (which the stage port hooks): the
-- front-end reaches $916B from other call sites, so $8561 sees almost nothing
-- here -- 3 loads across the whole boot-to-menu walk, and none of the menu
-- text. On entry DP $00-$02 hold the 24-bit source and $03/$04 the VRAM
-- destination. This turns "this screen shows Japanese text" into "that text is
-- at this ROM address", which is the whole point of the survey.
-- Who WRITES the menu text? The strings are not in ROM in any obvious encoding
-- (searched the config screen's own glyph codes as words, low bytes, tile>>1,
-- tile-0x100), so find the code that puts them in VRAM and work back from it.
-- Track the VRAM ADDRESS register too: $2116/$2117 are write-only, so the only
-- way to know where a DMA lands is to shadow the writes that set it.
local vaddr = 0
for _, a in ipairs({ 0x802116, 0x802117 }) do
  emu.addMemoryCallback(function(addr, value)
    if (addr % 0x10000) == 0x2116 then vaddr = (vaddr & 0xFF00) | (value or 0)
    else vaddr = (vaddr & 0x00FF) | ((value or 0) << 8) end
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end

-- ...and it is not CPU writes to $2118 either (none fire), so the screen is
-- DMA'd in. Log every VRAM DMA with its SOURCE and the VRAM address it targets.
local vw = 0
emu.addMemoryCallback(function(_ad, value)
  if frames < 1140 or frames > 1280 or vw > 30 then return end
  for ch = 0, 7 do
    if ((value or 0) >> ch) & 1 == 1 then
      local b = emu.read(0x804301 + ch * 16, MEMT) or 0
      if b == 0x18 or b == 0x19 then
        vw = vw + 1
        local ok, st = pcall(emu.getState)
        local sb = emu.read(0x804304 + ch * 16, MEMT) or 0
        local sa = ((emu.read(0x804303 + ch * 16, MEMT) or 0) << 8)
                 | (emu.read(0x804302 + ch * 16, MEMT) or 0)
        local bytes = {}
        for k = 0, 3 do
          bytes[#bytes + 1] = string.format("%02X", emu.read(sb * 0x10000 + sa + k, MEMT) or 0)
        end
        log(string.format("  VRAMDMA f=%d ch%d src=$%02X:%04X [%s] len=%04X vram=$%04X (map r%d c%d) @%02X:%04X",
          frames, ch, sb, sa, table.concat(bytes, " "),
          ((emu.read(0x804306 + ch * 16, MEMT) or 0) << 8) | (emu.read(0x804305 + ch * 16, MEMT) or 0),
          vaddr, (vaddr % 0x400) // 32, (vaddr % 0x400) % 32,
          ok and (st["cpu.k"] or 0) or 0, ok and (st["cpu.pc"] or 0) or 0))
      end
    end
  end
end, emu.callbackType.write, 0x80420B, 0x80420B, emu.cpuType.snes, emu.memType.snesMemory)

-- $83:1906 is not ROM: banks $80-$BF mirror WRAM at $0000-$1FFF, so the glyph
-- rows are DMA'd from a WRAM staging buffer at $7E:1900+. Watch who fills it.
local sw, swseen = 0, {}
for _, a in ipairs({ 0x7E1906, 0x001906, 0x7E190E, 0x00190E }) do
  emu.addMemoryCallback(function(_ad, value)
    if frames < 1140 or frames > 1280 or sw > 12 then return end
    local ok, st = pcall(emu.getState)
    local pc = string.format("%02X:%04X", ok and (st["cpu.k"] or 0) or 0, ok and (st["cpu.pc"] or 0) or 0)
    if swseen[pc] then return end
    swseen[pc] = true; sw = sw + 1
    log(string.format("  STAGE-BUF f=%d $%06X <= %02X @%s A=%04X X=%04X Y=%04X DB=%02X", frames,
      _ad, value or 0, pc, ok and (st["cpu.a"] or 0) or 0, ok and (st["cpu.x"] or 0) or 0,
      ok and (st["cpu.y"] or 0) or 0, ok and (st["cpu.db"] or 0) or 0))
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end

local loads = {}
emu.addMemoryCallback(function()
  local src = ram(0x00) + 256 * ram(0x01) + 65536 * ram(0x02)
  local vram = ram(0x03) + 256 * ram(0x04)
  local key = string.format("%06X->%04X", src, vram)
  if not loads[key] then
    loads[key] = frames
    log(string.format("  LOAD f=%4d src=$%02X:%04X -> VRAM %04X",
      frames, src >> 16, src & 0xFFFF, vram))
  end
end, emu.callbackType.exec, 0x80916B, 0x80916B, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  frames = frames + 1
  pulse[0] = {}
  if KEYS[frames] then pulse[0] = { [KEYS[frames]] = true }
  elseif frames % 90 < 3 then pulse[0] = { start = true } end   -- keep it moving
  if frames % EVERY == 0 then
    local f = io.open(string.format("%s%s_%04d.png", DIR, TAG, frames), "wb")
    f:write(emu.takeScreenshot()); f:close()
    dump_maps(frames)
    local s = ppu()
    log(string.format("f=%4d mode=$%02X $01FA=$%02X bgmode=%s main=%s",
      frames, ram(0x008D), ram(0x01FA),
      tostring(s and s["ppu.bgMode"]), tostring(s and s["ppu.mainScreenLayers"])))
  end
  if frames >= UNTIL then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)

print("probe_menu_survey loaded")
