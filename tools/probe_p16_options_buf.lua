-- probe_p16_options_buf.lua — patch 16 step 2 diagnostic, v2.
--
-- v1 (this file's first run, log preserved in the finding) answered the
-- handoff's question and raised the real one: the staging buffer $7E:C000 IS
-- fully staged (glyphs at +$3800 present, written f641-643) and the extended
-- transfer (vram $4000 len $4000 src $7E:C000) runs at MAIN MENU entry (f672),
-- not on the Options transition — Options entry runs six uploads, none covering
-- VRAM words $5C00-$5FFF, and yet the settled Options screen has 0/64 glyph
-- tiles. So the glyphs' fate is decided by something the v1 filter (asset
-- uploader PC + len>$400) never saw.
--
-- v2 instruments for that:
--   1. per-frame VRAM census of tiles $5C0-$5FF — logs every change, so the
--      frame the region fills or blanks is read off directly;
--   2. EVERY $420B kick (any PC): decodes the enabled channels' DMA registers
--      and logs each transfer whose B-bus target is VRAM ($18/$19), fixed-
--      source fills included, with the current VMADD (tracked via $2116/17);
--   3. the asset-uploader view and the $7E:F800-$FFFF staging write-watch
--      from v1, unchanged, so the two runs correlate.
--
--   ROM=build/sms_p16.sfc tools/run.sh tools/probe_p16_options_buf.lua 400
-- Output: traces/p16_options_buf.txt (+ p16optbuf_final.bin, options PNG)
-- NB trap 12: nothing in a memory callback may throw — getState is pcall'd,
-- file I/O stays in endFrame.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram = PL.ram
local MEM = emu.memType.snesMemory
local WRAM = emu.memType.snesWorkRam
local VRAM = emu.memType.snesVideoRam
local LOG = assert(io.open(ENV.TRACE .. "p16_options_buf.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local frames, step, sf = 0, 1, 0
local pulse = {}
local caps, written = {}, 0
local function beat(on) return (frames % 7) < 3 and on or {} end
local function st() local ok, s = pcall(emu.getState); return ok and s or nil end

-- (2a) VMADD tracking: latest $2116/$2117 writes (word address)
local vmadd = 0
for b = 0x00, 0xBF do
  if b <= 0x3F or b >= 0x80 then
    local base = b << 16
    emu.addMemoryCallback(function(_, v)
      vmadd = (vmadd & 0xFF00) | (v or 0)
    end, emu.callbackType.write, base | 0x2116, base | 0x2116, emu.cpuType.snes, MEM)
    emu.addMemoryCallback(function(_, v)
      vmadd = (vmadd & 0x00FF) | ((v or 0) << 8)
    end, emu.callbackType.write, base | 0x2117, base | 0x2117, emu.cpuType.snes, MEM)
  end
end

-- (2b) every DMA kick, decoded from the channel registers — PC-independent
local msgs = {}                       -- log lines queued out of the callback
for b = 0x00, 0xBF do
  if b <= 0x3F or b >= 0x80 then
    local a = (b << 16) | 0x420B
    emu.addMemoryCallback(function(_, v)
      v = v or 0
      if v == 0 then return end
      local s = st()
      local pc = s and (((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)) or -1
      for ch = 0, 7 do
        if (v & (1 << ch)) ~= 0 then
          local r = 0x004300 | (ch << 4)
          local dmap = emu.read(r, MEM) or 0
          local bbad = emu.read(r + 1, MEM) or 0
          if bbad == 0x18 or bbad == 0x19 then
            local a1 = (emu.read(r + 2, MEM) or 0) | ((emu.read(r + 3, MEM) or 0) << 8)
            local ab = emu.read(r + 4, MEM) or 0
            local das = (emu.read(r + 5, MEM) or 0) | ((emu.read(r + 6, MEM) or 0) << 8)
            msgs[#msgs + 1] = string.format(
              "f%d step%d DMA ch%d pc=$%06X vmadd=$%04X len=$%04X src=$%02X:%04X dmap=$%02X%s",
              frames, step, ch, pc, vmadd, das, ab, a1, dmap,
              (dmap & 0x08) ~= 0 and " FIXED" or "")
            -- the asset uploader's font transfer: snapshot the staging buffer
            -- NOW (endFrame is too late — later writes could repaint it)
            if pc == 0x8092D2 and vmadd == 0x4000 and das == 0x4000 and #caps < 4 then
              local buf = {}
              for i = 0, 0x3FFF do buf[i + 1] = string.char(emu.read(0xC000 + i, WRAM) or 0) end
              caps[#caps + 1] = { frame = frames, data = table.concat(buf) }
            end
          end
        end
      end
    end, emu.callbackType.write, a, a, emu.cpuType.snes, MEM)
  end
end

-- (3) who stages the glyph region of the buffer, and when
local wrByFrame, wrFirst = {}, nil
emu.addMemoryCallback(function()
  wrByFrame[frames] = (wrByFrame[frames] or 0) + 1
  if not wrFirst then
    local s = st()
    wrFirst = { frame = frames,
                pc = s and (((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)) or -1 }
  end
end, emu.callbackType.write, 0x7EF800, 0x7EFFFF, emu.cpuType.snes, MEM)

emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)

-- (1) per-frame VRAM glyph census
local GLYPH_LO = 0x5C0 * 32
local function vram_glyphs()
  local c = 0
  for t = 0, 63 do
    for b = 0, 31 do
      if (emu.read(GLYPH_LO + t * 32 + b, VRAM) or 0) ~= 0 then c = c + 1; break end
    end
  end
  return c
end

local function summarize(tag, data)
  local function get(o) return data:byte(o + 1) or 0 end
  local whole, glyph = 0, 0
  for t = 0, 511 do
    for b = 0, 31 do
      if get(t * 32 + b) ~= 0 then
        whole = whole + 1
        if t >= 0x1C0 then glyph = glyph + 1 end
        break
      end
    end
  end
  log(string.format("BUFFER %s: nonblank tiles whole=%d/512 glyphs($3800-$3FFF)=%d/64",
    tag, whole, glyph))
end

local function finale()
  if wrFirst then
    log(string.format("GLYPHWRITES first f%d pc=$%06X", wrFirst.frame, wrFirst.pc))
    local fs = {}
    for f in pairs(wrByFrame) do fs[#fs + 1] = f end
    table.sort(fs)
    local parts = {}
    for _, f in ipairs(fs) do parts[#parts + 1] = string.format("f%d:%d", f, wrByFrame[f]) end
    log("GLYPHWRITES frames " .. table.concat(parts, " "))
  else
    log("GLYPHWRITES none — the glyph region of the buffer is NEVER written")
  end
  log(string.format("VRAM glyphs $5C0-$5FF nonblank=%d/64 (settled, f%d)", vram_glyphs(), frames))
  local buf = {}
  for i = 0, 0x3FFF do buf[i + 1] = string.char(emu.read(0xC000 + i, WRAM) or 0) end
  local data = table.concat(buf)
  summarize("final", data)
  local f = assert(io.open(ENV.TRACE .. "p16optbuf_final.bin", "wb"))
  f:write(data); f:close()
  local shot = io.open(ENV.TRACE .. "p16_options_screen.png", "wb")
  if shot then shot:write(emu.takeScreenshot()); shot:close() end
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true });  return ram(0x1B10) == 2 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 5 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 300 end,
  function() finale(); return true end,
}
local lastCensus = -1
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  while #msgs > 0 do log(table.remove(msgs, 1)) end
  local g = vram_glyphs()
  if g ~= lastCensus then
    log(string.format("f%d step%d GLYPHS-IN-VRAM %d/64", frames, step, g))
    lastCensus = g
  end
  while written < #caps do
    written = written + 1
    local c = caps[written]
    summarize(string.format("at-transfer #%d f%d", written, c.frame), c.data)
    local f = assert(io.open(string.format("%sp16optbuf_%d_f%d.bin", ENV.TRACE, written, c.frame), "wb"))
    f:write(c.data); f:close()
  end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then LOG:close(); emu.stop(0) end
  if frames > 6000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
