-- probe_p16_screens.lua — patch 16 screen census: reach the Win / ACS /
-- Tournament screens and record how each is composed, so the font install and
-- text edits can be planned per screen (each screen CLEARS ALL VRAM on entry
-- and re-runs its own asset list — the Options finding, 2026-08-06).
--
-- What it logs (traces/p16_screens_<ROUTE>.txt):
--   * every WRAM $1C18 write with writer PC — identifies which loader cluster
--     ($C3:xxxx straight-line code) a screen runs, and which record indices;
--   * every asset-uploader DMA ($80:92D2) with vram/len/src, and every
--     fixed-source full-VRAM clear ($80:8191);
--   * every $70 / $8D transition (screen/mode ids), with a screenshot ~45
--     frames after each transition (traces/p16scr_<ROUTE>_<n>_f<frame>.png);
--   * the VRAM glyph census ($5C0-$5FF) at each transition, so "does this
--     screen keep the half-width font" is answered per screen.
--
-- Routes (ROUTE env):
--   win        1P-vs-COM (menu cursor 2), fight with pinned HP until the
--              MATCH is won (best-of-3 — two KOs), then keep logging through
--              whatever follows (the Win screen and onward).
--   acs        vs-COM char select, then SELECT to open the A.C.S. screen.
--   tournament menu cursor 3, enter, settle.
--
--   ROUTE=win ROM=build/sms_p16.sfc tools/run.sh tools/probe_p16_screens.lua 700
-- NB trap 12: nothing in a memory callback may throw; file I/O in endFrame.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local MEM = emu.memType.snesMemory
local VRAM = emu.memType.snesVideoRam
local ROUTE = os.getenv("ROUTE") or "win"
local LOG = assert(io.open(ENV.TRACE .. "p16_screens_" .. ROUTE .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local frames, step, sf = 0, 1, 0
local pulse, msgs = {}, {}
local function beat(on) return (frames % 7) < 3 and on or {} end
local function st() local ok, s = pcall(emu.getState); return ok and s or nil end

-- loader-cluster identity: every write to WRAM $1C18 with its PC. Watch the
-- WRAM MEMTYPE, not bus address $7E1C18 — the menu clusters execute from the
-- $03 mirror and write $03:1C18, which a single-bus-address watch misses
-- (this probe's first run logged only the $80:8DB8 resets and no clusters).
local WRAM = emu.memType.snesWorkRam
emu.addMemoryCallback(function(_, v)
  local s = st()
  local pc = s and (((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)) or -1
  msgs[#msgs + 1] = string.format("f%d $1C18=%02X pc=$%06X", frames, v or 0, pc)
end, emu.callbackType.write, 0x1C18, 0x1C18, emu.cpuType.snes, WRAM)

-- uploader DMAs + full-VRAM clears (all banks' $420B). FULLDMA=1 decodes
-- EVERY VRAM-targeting channel from the DMA registers instead (PC-agnostic —
-- needed for the bank-$DF screen system, which has its own upload path).
local FULLDMA = os.getenv("FULLDMA") == "1"
local vmadd = 0
if FULLDMA then
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
end
for b = 0x00, 0xBF do
  if b <= 0x3F or b >= 0x80 then
    local a = (b << 16) | 0x420B
    emu.addMemoryCallback(function(_, v)
      if (v or 0) == 0 then return end
      local s = st(); if not s then return end
      local pc = ((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)
      if FULLDMA then
        -- skip in-match sprite spam, but keep the report card's load, which
        -- happens inside step 8's tail once $70 leaves the match
        if ROUTE == "win" and (step < 8 or (step == 8 and ram(0x70) == 4)) then return end
        for ch = 0, 7 do
          if (v & (1 << ch)) ~= 0 then
            local r = 0x004300 | (ch << 4)
            local bbad = emu.read(r + 1, MEM) or 0
            if bbad == 0x18 or bbad == 0x19 then
              local dmap = emu.read(r, MEM) or 0
              local a1 = (emu.read(r + 2, MEM) or 0) | ((emu.read(r + 3, MEM) or 0) << 8)
              local ab = emu.read(r + 4, MEM) or 0
              local das = (emu.read(r + 5, MEM) or 0) | ((emu.read(r + 6, MEM) or 0) << 8)
              msgs[#msgs + 1] = string.format(
                "f%d DMA pc=$%06X vmadd=$%04X len=$%04X src=$%02X:%04X%s",
                frames, pc, vmadd, das, ab, a1, (dmap & 0x08) ~= 0 and " FIXED" or "")
            end
          end
        end
        return
      end
      if pc == 0x8092D2 then
        local dp = s["cpu.d"] or 0
        local function w(o) return (emu.read(dp+o,MEM) or 0) | ((emu.read(dp+o+1,MEM) or 0) << 8) end
        msgs[#msgs + 1] = string.format("f%d upload vram=$%04X len=$%04X src=$%02X:%04X",
          frames, w(0), w(2), emu.read(dp + 6, MEM) or 0, w(4))
      elseif pc == 0x808193 or pc == 0x808191 then
        msgs[#msgs + 1] = string.format("f%d FULL VRAM CLEAR (pc=$%06X)", frames, pc)
      end
    end, emu.callbackType.write, a, a, emu.cpuType.snes, MEM)
  end
end

-- ROWWATCH=1: log the first writes to the $DF system's staged row records
-- ($7F:8000-$83FF) with writer PC — names the text-builder code directly
if os.getenv("ROWWATCH") == "1" then
  local seen, n = {}, 0
  emu.addMemoryCallback(function(addr, v)
    if n >= 400 then return end
    local s = st()
    local pc = s and (((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)) or -1
    local key = pc
    seen[key] = (seen[key] or 0) + 1
    if seen[key] <= 6 then
      n = n + 1
      msgs[#msgs + 1] = string.format("f%d ROW $%06X=%02X pc=$%06X",
        frames, addr or 0, v or 0, pc)
    end
  end, emu.callbackType.write, 0x7F8000, 0x7F83FF, emu.cpuType.snes, MEM)
end

emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)

local function glyphs()
  local c = 0
  for t = 0x5C0, 0x5FF do
    for b = 0, 31 do
      if (emu.read(t * 32 + b, VRAM) or 0) ~= 0 then c = c + 1; break end
    end
  end
  return c
end

-- DUMP7F: write the $DF system's staging areas — the sheet at $7F:0000 and
-- the row records at $7F:8000 — so text blocks can be rendered offline
local function dump7f(tag)
  local f = assert(io.open(string.format("%sp16_7f_%s_%s.bin", ENV.TRACE, ROUTE, tag), "wb"))
  local chunk = {}
  for i = 0, 0x5FFF do
    chunk[#chunk + 1] = string.char(emu.read(0x10000 + i, emu.memType.snesWorkRam) or 0)
    if #chunk == 4096 then f:write(table.concat(chunk)); chunk = {} end
  end
  f:write(table.concat(chunk)); f:close()
  f = assert(io.open(string.format("%sp16_7frec_%s_%s.bin", ENV.TRACE, ROUTE, tag), "wb"))
  chunk = {}
  for i = 0x8000, 0x8BFF do
    chunk[#chunk + 1] = string.char(emu.read(0x10000 + i, emu.memType.snesWorkRam) or 0)
  end
  f:write(table.concat(chunk)); f:close()
  log(string.format("f%d DUMP7F %s", frames, tag))
end

-- screen-transition tracker + screenshots
local last70, last8D, shots, shootAt = -1, -1, 0, nil
local function track()
  local s70, s8D = ram(0x70), ram(0x8D)
  if s70 ~= last70 or s8D ~= last8D then
    log(string.format("f%d step%d SCREEN $70=%d $8D=%d glyphs=%d/64",
      frames, step, s70, s8D, glyphs()))
    last70, last8D = s70, s8D
    shootAt = frames + 45
  end
  if shootAt and frames >= shootAt then
    shootAt = nil
    shots = shots + 1
    local f = io.open(string.format("%sp16scr_%s_%d_f%d.png", ENV.TRACE, ROUTE, shots, frames), "wb")
    if f then f:write(emu.takeScreenshot()); f:close() end
  end
end

local fought, done, lastsig = 0, false, nil
-- the VS config screen's mode-row handler: executing = the screen is up
local moderow = 0
emu.addMemoryCallback(function() moderow = moderow + 1 end,
  emu.callbackType.exec, 0x83A849, 0x83A849, emu.cpuType.snes, MEM)
local ROUTES = {
  win = {
    function() return frames >= 900 end,
    function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 2 end,
    function() pulse[0] = beat({ start = true }); return sf > 40 end,
    function() pulse[0] = {}; return sf > 240 end,
    function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
    function()  -- through stage/handicap screens into the match
      pulse[0] = (frames % 14 < 3) and { a = true }
        or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
      if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
      if sf > 1500 then log("MATCH-LOAD-FAIL"); done = true; return true end
      return false
    end,
    function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 150 end,
    function()  -- win the MATCH by round timeouts: P1 HP pinned high, P2 low,
                -- clock forced to 0:02 whenever it reads higher (COM blocks
                -- too well to KO reliably — the first run fought 23k frames)
      if ram(0x70) == 4 then
        -- Throws beat the COM's guard (jabs were blocked for 23k frames; no
        -- round clock in vs-COM either — it displays 00 and never ticks).
        -- Poke ONLY while the round is live and P2 is up; the moment P2 is
        -- down, hands off everything so the round/match sequencer can run.
        local p2hp, p2act = ram(0x10C9), ram(0x1081)
        local live = ram(0x1FA) == 0x80 and p2act ~= 0x1F and p2hp > 0
        if live then
          -- pin P1 to its OWN max ($104A — HP is per-A.C.S., a fixed $50 pin
          -- was found LOWERING P1); pin P2 to 2 so any landed STRIKE
          -- underflow-kills. Throws cannot finish (their ticks are chip-class
          -- and chip never kills — measured: P2 lay at 0 HP forever), so fish
          -- for counter-hits with the 4f jab while the COM attacks.
          wr(0x1049, ram(0x104A))
          if p2hp > 2 then wr(0x10C9, 2) end
          local m = sf % 10
          if m == 0 then
            local ax = ram(0x1021) + 256 * ram(0x1022)
            local dx = (ax + 32) % 65536
            wr(0x10A1, dx % 256); wr(0x10A2, math.floor(dx / 256))
          end
          pulse[0] = (m >= 2 and m < 6) and { y = true } or {}
        else
          pulse[0] = {}
        end
        -- change-triggered telemetry: the sequencer's exact path
        local sig = string.format("hp=%02X/%02X disp=%02X/%02X $1FA=%02X acts=%02X/%02X clk=%d%d",
          ram(0x1049), p2hp, ram(0x800), ram(0x801), ram(0x1FA),
          ram(0x1001), p2act, ram(0x804), ram(0x803))
        if sig ~= lastsig then log(string.format("f%d fight %s", frames, sig)); lastsig = sig end
        if sf % 1200 == 0 then
          local f = io.open(string.format("%sp16scr_%s_fight_f%d.png", ENV.TRACE, ROUTE, frames), "wb")
          if f then f:write(emu.takeScreenshot()); f:close() end
        end
        if sf > 8000 then log("FIGHT-STUCK"); done = true; return true end
        fought = sf
        return false
      end
      pulse[0] = {}
      -- out of the match context for 300 straight frames = the match is over
      return sf - fought > 300
    end,
    function()  -- the Win screen(s): shoot through the whole window
      pulse[0] = {}
      if sf % 90 == 0 then
        local f = io.open(string.format("%sp16scr_%s_post_f%d.png", ENV.TRACE, ROUTE, frames), "wb")
        if f then f:write(emu.takeScreenshot()); f:close() end
      end
      if sf == 600 then dump7f("report") end
      return sf > 900
    end,
    function()
      pulse[0] = beat({ start = true })
      if sf % 90 == 0 then
        local f = io.open(string.format("%sp16scr_%s_post_f%d.png", ENV.TRACE, ROUTE, frames), "wb")
        if f then f:write(emu.takeScreenshot()); f:close() end
      end
      return sf > 400
    end,
  },
  acs = {  -- the ACS door is the VS config screen's SELECT (mkpatch18's map);
           -- vs-COM keeps it open. Navigation mirrors probe_acs_select MENU=2:
           -- P1 confirms own char AND the opponent (P2's pad is inert here).
    function() return frames >= 900 end,
    function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 2 end,
    function() pulse[0] = beat({ start = true }); return sf > 40 end,
    function() pulse[0] = {}; return sf > 240 end,
    function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 150 end,
    function() pulse[0] = {}; return sf > 20 end,
    function() pulse[0] = beat({ a = true }); return sf > 150 end,
    -- wait for the config screen PROVEN up (its mode-row handler executing —
    -- probe_acs_select's precondition), then SELECT transitions by itself
    function() pulse[0] = {}; return moderow > 0 and sf > 30 end,
    function() pulse[0] = beat({ select = true }); return sf > 40 end,
    function() pulse[0] = {}; return sf > 180 end,
    function()
      pulse[0] = {}
      if sf % 120 == 0 then
        local f = io.open(string.format("%sp16scr_%s_post_f%d.png", ENV.TRACE, ROUTE, frames), "wb")
        if f then f:write(emu.takeScreenshot()); f:close() end
      end
      return sf > 500
    end,
  },
  tournament = {
    function() return frames >= 900 end,
    function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 0 end,
    function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 3 end,
    function() pulse[0] = beat({ start = true }); return sf > 40 end,
    function()
      pulse[0] = {}
      if sf % 120 == 0 then
        local f = io.open(string.format("%sp16scr_%s_post_f%d.png", ENV.TRACE, ROUTE, frames), "wb")
        if f then f:write(emu.takeScreenshot()); f:close() end
      end
      if sf == 490 then dump7f("select") end
      return sf > 500
    end,
    function() pulse[0] = beat({ start = true }); return sf > 60 end,
    function()
      pulse[0] = {}
      if sf % 120 == 0 then
        local f = io.open(string.format("%sp16scr_%s_post_f%d.png", ENV.TRACE, ROUTE, frames), "wb")
        if f then f:write(emu.takeScreenshot()); f:close() end
      end
      if sf == 390 then dump7f("bracket") end
      return sf > 400
    end,
  },
}
local STEPS = ROUTES[ROUTE] or error("ROUTE must be win|acs|tournament")

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  while #msgs > 0 do log(table.remove(msgs, 1)) end
  track()
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("DONE route=%s frames=%d shots=%d glyphs=%d/64",
      ROUTE, frames, shots, glyphs()))
    LOG:close(); emu.stop(done and 1 or 0)
  end
  if frames > 25000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
