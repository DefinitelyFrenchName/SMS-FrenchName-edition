-- probe_supers_stagejump.lua — what does SUPER S do to this stage's layers
-- during a jump? The SMS twin (probe_sms_stagejump.lua) answered it for our
-- port; this is the reference measurement it has to match.
--
-- Field report on the ported stage (#43, second round): our palace moves with
-- the ground, while Super S's palace moves only a fraction as far — the crescent
-- on the central dome comes into view and a band of the palace shows above the
-- ground line. The engine's scroll routines only ever divide by 4, so "about
-- half" by eye is worth measuring rather than guessing.
--
-- Navigation is lifted from probe_supers_stagepal.lua (the working Super S VS
-- flow, scene forced at $80:8530). Measurement is lifted from the SMS twin:
-- camera at $0A00/$0A02 and the four per-plane (h,v) pairs at $0A18..$0A27.
--
-- usage: STAGE=1 ROM=<Super S> tools/run.sh tools/saturn/probe_supers_stagejump.lua 400
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local STAGE = tonumber(os.getenv("STAGE") or "1")
local CHAR = tonumber(os.getenv("CHAR") or "6")
local CHAR2 = tonumber(os.getenv("CHAR2") or "4")
local TAG = os.getenv("TAG") or ("sup" .. STAGE)
local LOG = assert(io.open(ENV.TRACE .. "saturn/supersjump_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local function scrolls()
  local ok, s = pcall(emu.getState)
  if not ok or not s then return nil end
  local t = {}
  for i = 0, 3 do
    t[i] = { h = s[string.format("ppu.layers[%d].hscroll", i)] or -1,
             v = s[string.format("ppu.layers[%d].vscroll", i)] or -1 }
  end
  return t
end

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local forced, shots = 0, 0
emu.addMemoryCallback(function()
  forced = forced + 1
  wr(0x8E, STAGE * 2)
end, emu.callbackType.exec, 0x808530, 0x808530, emu.cpuType.snes, emu.memType.snesMemory)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function() wr(0x1B40, CHAR); wr(0x1B80, CHAR2); return sf > 20 end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = beat({ a = true }); return sf > 60 end,
  function() return sf > 240 end,
  function()
    pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
    return (ram(0x1000) == CHAR and ram(0x1080) ~= 0) or sf > 600
  end,
  -- same two waits as the SMS twin: live round AND neutral, then well past the
  -- "GO!" banner before the pad does anything
  function() return ram(0x01FA) == 0x80 and ram(0x1001) == 0x00 and sf > 30 end,
  function()
    if sf == 1 then
      log(string.format("=== Super S: P1 char %d, scene $%02X (id %d, forced %d) ===",
        ram(0x1000), ram(0x008E), ram(0x008E) // 2, forced))
      local ok, st = pcall(emu.getState)
      local b = {}
      for i = 0, 3 do
        b[#b + 1] = string.format("BG%d map=%04X chr=%04X", i + 1,
          ok and st[string.format("ppu.layers[%d].tilemapAddress", i)] or 0,
          ok and st[string.format("ppu.layers[%d].chrAddress", i)] or 0)
      end
      log("  planes: " .. table.concat(b, "  "))
      local vb = {}
      for a = 0, 0xFFFF do vb[#vb + 1] = string.char(emu.read(a, emu.memType.snesVideoRam) or 0) end
      local vf = io.open(ENV.TRACE .. "saturn/supersjump_" .. TAG .. "_vram.bin", "wb")
      vf:write(table.concat(vb)); vf:close()
      log("  frame act  y  | BG1 h,v  BG2 h,v  BG3 h,v  BG4 h,v | cam x,y | block $0A18..$0A27")
    end
    if sf >= 120 and sf <= 150 then pulse[0] = { up = true } else pulse[0] = {} end
    if sf >= 110 and sf <= 200 then
      local sc = scrolls()
      local function w(a) return ram(a) + 256 * ram(a + 1) end
      local blk = {}
      for _, a in ipairs({ 0x0A18, 0x0A1A, 0x0A1C, 0x0A1E, 0x0A20, 0x0A22, 0x0A24, 0x0A26 }) do
        blk[#blk + 1] = string.format("%04X", w(a))
      end
      -- HDMA: if a single plane shows the palace moving while the ground does
      -- not, the split is per-SCANLINE, not per-plane. $420C = HDMAEN, and each
      -- channel's $43x1 names the register it feeds ($0E = BG1VOFS, $12 = BG2VOFS)
      local hd = {}
      local en = emu.read(0x80420C, emu.memType.snesMemory) or 0
      for ch = 0, 7 do
        if (en >> ch) & 1 == 1 then
          hd[#hd + 1] = string.format("ch%d->21%02X tbl=%02X:%02X%02X", ch,
            emu.read(0x804301 + ch * 16, emu.memType.snesMemory) or 0,
            emu.read(0x804304 + ch * 16, emu.memType.snesMemory) or 0,
            emu.read(0x804303 + ch * 16, emu.memType.snesMemory) or 0,
            emu.read(0x804302 + ch * 16, emu.memType.snesMemory) or 0)
        end
      end
      if sf == 118 or sf == 145 then
        log(string.format("  HDMAEN=%02X %s", en, table.concat(hd, " ")))
      end
      log(string.format("  %4d %02X %02X | %4d,%-4d %4d,%-4d %4d,%-4d %4d,%-4d | %04X,%04X | %s",
        sf, ram(0x1001), ram(0x1025),
        sc and sc[0].h or -1, sc and sc[0].v or -1, sc and sc[1].h or -1, sc and sc[1].v or -1,
        sc and sc[2].h or -1, sc and sc[2].v or -1, sc and sc[3].h or -1, sc and sc[3].v or -1,
        w(0x0A00), w(0x0A02), table.concat(blk, " ")))
    end
    if (sf == 118 or sf == 145) and shots < 2 then
      shots = shots + 1
      local f = io.open(ENV.TRACE .. "saturn/supersjump_" .. TAG .. "_" .. sf .. ".png", "wb")
      f:write(emu.takeScreenshot()); f:close()
      -- CGRAM too: colour 0 is the BACKDROP, which no palette record carries and
      -- which a stage's sky may well be showing through transparent tiles
      local cg = {}
      for a = 0, 0x1FF do cg[#cg + 1] = string.char(emu.read(a, emu.memType.snesCgRam) or 0) end
      local cf = io.open(ENV.TRACE .. "saturn/supersjump_" .. TAG .. "_cgram" .. sf .. ".bin", "wb")
      cf:write(table.concat(cg)); cf:close()
    end
    return sf > 205
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_supers_stagejump loaded")
