-- probe_sms_stagejump.lua — reproduce and MEASURE the ported stage's vertical
-- slide (task #43).
--
-- Field report: on the ported stage only, during a jump the shadows and the
-- opponent slide toward the bottom of the screen and return on landing. Two
-- earlier probe attempts never got the character to jump at all (p1y never left
-- $00C0), so nothing about the vertical behaviour has ever been measured — the
-- first job is simply to make a jump happen and watch.
--
-- Logs, per frame across a jump: P1's Y, and all four BG layers' scroll
-- registers (write-only, so they are shadowed from writes). Run it on the stage
-- build and on a vanilla stage and diff: whatever tracks the camera on one and
-- not the other is the fault.
--
-- STAGE forces the scene id at $7E:008E just before the loader reads it
-- ($C0:8586), which is the documented way to summon a specific stage — stage
-- choice is NOT simply P1's character, and the first run of this probe measured
-- scene $00 while believing it had the ported one. STAGE=2 = Pluto's slot = the
-- ported stage on a stage build. The header line records the scene actually
-- loaded; check it before trusting anything below.
--
-- Also logs each layer's TILEMAP ADDRESS, because the question for #43 is which
-- PLANE holds the ground after the port's re-cut, not merely that some plane
-- fails to track.
--
-- usage: STAGE=2 CHAR=8 ROM=build/saturn/<rom> tools/run.sh \
--            tools/saturn/probe_sms_stagejump.lua 500
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "8")
local CHAR2 = tonumber(os.getenv("CHAR2") or "4")
local STAGE = tonumber(os.getenv("STAGE") or "") -- nil = whatever the game picks
local WALK = os.getenv("WALK") == "1"
local TAG = os.getenv("TAG") or ("jump" .. (os.getenv("CHAR") or "8"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/stagejump_" .. TAG .. ".txt", "w"))
local oamseq = assert(io.open(ENV.TRACE .. "saturn/stagejump_" .. TAG .. "_oamseq.bin", "wb"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local MEM = emu.memType.snesMemory

-- Mesen exposes the PPU's own scroll values, which is far better than shadowing
-- the write-only registers: an earlier version tracked $210D-$2114 writes and
-- captured nothing at all.
local function scrolls()
  local ok, s = pcall(emu.getState)
  if not ok or not s then return {} end
  local t = {}
  -- emu.getState() returns a FLAT table with dotted string keys, not nested
  -- tables: the fields are "ppu.layers[0].hscroll" and friends
  for i = 0, 3 do
    t[i] = { h = s[string.format("ppu.layers[%d].hscroll", i)] or -1,
             v = s[string.format("ppu.layers[%d].vscroll", i)] or -1 }
  end
  return t
end
local function sc4()
  local ok, t = pcall(scrolls)
  if not ok or not t or not t[0] then
    return { [0] = { h = -1, v = -1 }, [1] = { h = -1, v = -1 },
             [2] = { h = -1, v = -1 }, [3] = { h = -1, v = -1 } }
  end
  return t
end

-- which VRAM tilemap/CHR each BG plane is pointed at (the port SWAPs the two
-- stage maps between planes, so "BG1" alone does not say which art moved)
local function bases()
  local ok, s = pcall(emu.getState)
  if not ok or not s then return "?" end
  local t = {}
  for i = 0, 3 do
    t[#t + 1] = string.format("BG%d map=%04X chr=%04X", i + 1,
      s[string.format("ppu.layers[%d].tilemapAddress", i)] or 0xFFFF,
      s[string.format("ppu.layers[%d].chrAddress", i)] or 0xFFFF)
  end
  return table.concat(t, "  ")
end

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local watching, shots = false, 0
local basey
local forced = 0

-- Force the scene id every time the loader is about to read it. The write must
-- happen at $C0:8586 (the instruction before the read at $858C) — poking $8E
-- earlier is useless, the scene is re-derived per load.
if STAGE then
  emu.addMemoryCallback(function()
    forced = forced + 1
    wr(0x8E, STAGE * 2)
  end, emu.callbackType.exec, 0x808586, 0x808586, emu.cpuType.snes, emu.memType.snesMemory)
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function()
    emu.write(0x1B40, CHAR, emu.memType.snesWorkRam)
    emu.write(0x1B80, CHAR2, emu.memType.snesWorkRam)
    return sf > 20
  end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = beat({ a = true }); return sf > 60 end,
  function() return sf > 240 end,
  function()
    pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
    return ram(0x1000) == CHAR or sf > 600
  end,
  -- wait for the round to be actually RUNNING ($01FA == $80), not just loaded;
  -- during the intro the pads are ignored, which is why earlier attempts never
  -- got a jump
  -- and wait for NEUTRAL: $01FA == $80 only means the round is live, while the
  -- fighters may still be in their entrance (act $22). Pads are ignored there,
  -- which is why no earlier attempt ever produced a jump.
  function() return ram(0x01FA) == 0x80 and ram(0x1001) == 0x00 and sf > 30 end,
  function()
    if sf == 1 then
      watching = true
      log(string.format("=== running: P1 char %d, $01FA=$%02X, scene $%02X (id %d)%s ===",
        ram(0x1000), ram(0x01FA), ram(0x008E), ram(0x008E) // 2,
        STAGE and string.format(" [forced STAGE=%d, %d hits]", STAGE, forced) or ""))
      log("  planes: " .. bases())
      log("  frame act | +21..+28 (x/y candidates)      | BG1 h,v  BG2 h,v  BG3 h,v  BG4 h,v")
    end
    -- The "GO!" banner is still up for a while after $01FA turns $80 and the act
    -- reaches neutral, and the pads do nothing until it clears — so wait well
    -- past it before trying to jump.
    -- WALK=1 holds forward instead of jumping: the horizontal camera is the
    -- same question as the vertical one (does the ground plane track the
    -- fighters, or a fraction of them?), and only walking moves camera x.
    if WALK then
      pulse[0] = (sf >= 112 and sf <= 200) and { right = true } or {}
    elseif sf >= 120 and sf <= 150 then pulse[0] = { up = true } else pulse[0] = {} end
    if sf >= 110 and sf <= 200 then
      local sc = sc4()
      local st = {}
      for i = 0x21, 0x28 do st[#st + 1] = string.format("%02X", ram(0x1000 + i)) end
      -- also log what the GAME sees on the pad: $4218/9 is the autopoll result
      -- and $5C-$5F the engine's own held words, so a jump that never happens
      -- can be told apart from an input that never arrived
      local pad = emu.read(0x804218, MEM) + 256 * emu.read(0x804219, MEM)
      -- the scroll block: camera at $0A00 (x) / $0A02 (y), and the four
      -- per-plane (h,v) pairs the per-stage routines fill in at $0A18..$0A27.
      -- Logging it is what ties "which plane moved" to "what the stage's
      -- routine decided", which the PPU registers alone cannot say.
      local function w(a) return ram(a) + 256 * ram(a + 1) end
      local cam = {}
      for _, a in ipairs({ 0x0A00, 0x0A02, 0x0A18, 0x0A1A, 0x0A1C, 0x0A1E,
                           0x0A20, 0x0A22, 0x0A24, 0x0A26 }) do
        cam[#cam + 1] = string.format("%04X", w(a))
      end
      -- P2 stands still all run, so her sprites are the rigid marker for what
      -- the camera does to OBJECTS — but only between frames in the SAME idle
      -- pose, hence act/step/tick/frame here and a per-frame OAM dump below.
      -- HDMA: Super S splits this stage per SCANLINE, not per plane — during a
      -- jump it enables a channel feeding $210E (BG1VOFS) from a table, so the
      -- palace band and the ground band scroll by different amounts on ONE
      -- plane. Log the same thing here to see whether SMS does it at all.
      local en = emu.read(0x80420C, emu.memType.snesMemory) or 0
      local hd = {}
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
      log(string.format("  %4d %02X  | %s | %4d,%-4d %4d,%-4d %4d,%-4d %4d,%-4d | pad %04X held %02X%02X | cam %s | p2 %02X %02X %02X %02X y=%02X",
        sf, ram(0x1001), table.concat(st, " "),
        sc[0].h, sc[0].v, sc[1].h, sc[1].v, sc[2].h, sc[2].v, sc[3].h, sc[3].v,
        pad, ram(0x005D), ram(0x005C), table.concat(cam, " "),
        ram(0x1081), ram(0x1082), ram(0x1086), ram(0x1087), ram(0x10A5)))
      local ok, ob = pcall(function()
        local t = {}
        for a = 0, 0x21F do t[#t + 1] = string.char(emu.read(a, emu.memType.snesSpriteRam) or 0) end
        return table.concat(t)
      end)
      if ok then oamseq:write(string.char(sf % 256) .. ob) end
    end
    -- WRAM snapshots at rest and at the jump apex. Diffing the pair names the
    -- camera variables outright, which beats inferring them from the scroll
    -- registers: the registers say what MOVED, the diff says what DROVE it.
    -- Also dumps the OAM shadow so the sprites' real screen Y is measurable —
    -- a pixel correlation on the standing dummy cannot separate a camera pan
    -- from her idle bob.
    if sf == 118 or sf == 145 then
      local n = 0x2000
      local buf = {}
      for a = 0, n - 1 do buf[#buf + 1] = string.char(emu.read(a, emu.memType.snesWorkRam)) end
      local f = io.open(ENV.TRACE .. "saturn/stagejump_" .. TAG .. "_wram" .. sf .. ".bin", "wb")
      f:write(table.concat(buf)); f:close()
      -- and all of VRAM, so each PLANE can be rendered separately offline: which
      -- tilemap holds the palace and which the ground is not readable off the
      -- builder's source labels (they describe Super S's layers, before the
      -- re-cut and the swap), and it decides which plane needs which rate
      local vb = {}
      for a = 0, 0xFFFF do vb[#vb + 1] = string.char(emu.read(a, emu.memType.snesVideoRam) or 0) end
      local vf = io.open(ENV.TRACE .. "saturn/stagejump_" .. TAG .. "_vram" .. sf .. ".bin", "wb")
      vf:write(table.concat(vb)); vf:close()
      local ok, ob = pcall(function()
        local t = {}
        for a = 0, 0x21F do t[#t + 1] = string.char(emu.read(a, emu.memType.snesSpriteRam) or 0) end
        return table.concat(t)
      end)
      if ok then
        local g = io.open(ENV.TRACE .. "saturn/stagejump_" .. TAG .. "_oam" .. sf .. ".bin", "wb")
        g:write(ob); g:close()
      else
        log("  (OAM unavailable: " .. tostring(ob) .. ")")
      end
    end
    if (sf == 118 or sf == 132 or sf == 145 or sf == 175) and shots < 4 then
      shots = shots + 1
      local f = io.open(ENV.TRACE .. "saturn/stagejump_" .. TAG .. "_" .. sf .. ".png", "wb")
      f:write(emu.takeScreenshot()); f:close()
    end
    return sf > 205
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log("done"); emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_stagejump loaded")
