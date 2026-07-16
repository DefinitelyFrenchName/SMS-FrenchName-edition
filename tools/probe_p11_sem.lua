-- probe_p11_sem.lua (patch 11, P1/P2/P3/P6/P10): native training mode semantics.
-- Loads traces/training_p11.mss (mode 4, Uranus vs Jupiter, clean ROM) and measures:
--   A) exec liveness of HUD producer ($D5E8) / uploader ($D56F) / joy_read ($8353)
--   B) BG3 tilemap ($1000-$13FF) + CHR (digits 0x50-0x69, free window 0xC7-0xDF) census
--   C) timer $0802/03/04 behavior, $0070 / $01FA / $008D change log
--   D) damage: P2 pulled close, P1 jabs -> does P2 hp drop in mode 4?
--   E) Start press (movelist?), L / R / L+R presses, Select press (exit?) + screenshots
-- Output: traces/p11_sem.txt (+ p11_sem_*.png)
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p11_sem.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end
local function vram(b) return emu.read(b, emu.memType.snesVideoRam) end
local function shot(name)
  local f = io.open(TRACE .. "p11_sem_" .. name .. ".png", "wb"); f:write(emu.takeScreenshot()); f:close()
end

local t, needLoad = -1, true
local cnt = { prod80=0, prodC0=0, upl80=0, uplC0=0, joy=0 }
local function watch(addr, key)
  emu.addMemoryCallback(function() cnt[key] = cnt[key] + 1 end,
    emu.callbackType.exec, addr, addr, emu.cpuType.snes, emu.memType.snesMemory)
end
watch(0x80D5E8, "prod80"); watch(0xC0D5E8, "prodC0")
watch(0x80D56F, "upl80");  watch(0xC0D56F, "uplC0")

emu.addMemoryCallback(function()
  cnt.joy = cnt.joy + 1
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k,v in pairs(b) do base[k]=v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

-- change trackers
local prev = {}
local function trackByte(name, addr)
  local v = ram(addr)
  if prev[name] ~= v then
    log(string.format("chg t=%d %s %s->%02X", t, name, prev[name] and string.format("%02X", prev[name]) or "--", v))
    prev[name] = v
  end
end

local function tilemapCensus(tag)
  local words, blank0, blank20, other = {}, 0, 0, 0
  for w = 0x1000, 0x13FF do
    local lo, hi = vram(w * 2), vram(w * 2 + 1)
    local word = hi * 256 + lo
    if word == 0x0000 then blank0 = blank0 + 1
    elseif word == 0x2000 then blank20 = blank20 + 1
    else other = other + 1; words[word] = (words[word] or 0) + 1 end
  end
  log(string.format("bg3map %s t=%d zeros=%d blank2000=%d other=%d", tag, t, blank0, blank20, other))
  local n = 0
  for word, c in pairs(words) do
    log(string.format("  word %04X x%d", word, c)); n = n + 1
    if n >= 20 then log("  ..."); break end
  end
end

local function chrCensus(tag)
  local function tileNZ(tile)
    local base = 0xA000 + tile * 16
    for i = 0, 15 do if vram(base + i) ~= 0 then return true end end
    return false
  end
  local dig = 0
  for d = 0, 9 do
    if tileNZ(0x50 + d) then dig = dig + 1 end
    if tileNZ(0x60 + d) then dig = dig + 1 end
  end
  local free = 0
  for tl = 0xC7, 0xDF do if tileNZ(tl) then free = free + 1 end end
  log(string.format("chr %s t=%d digitTilesNZ=%d/20 freeWinNZ=%d/25", tag, tag == "init" and t or t, dig, free))
end

local prevCnt = {}
local function liveness(tag)
  log(string.format("live %s t=%d prod80=%d prodC0=%d upl80=%d uplC0=%d joy=%d",
    tag, t, cnt.prod80 - (prevCnt.prod80 or 0), cnt.prodC0 - (prevCnt.prodC0 or 0),
    cnt.upl80 - (prevCnt.upl80 or 0), cnt.uplC0 - (prevCnt.uplC0 or 0), cnt.joy - (prevCnt.joy or 0)))
  for k, v in pairs(cnt) do prevCnt[k] = v end
end

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  trackByte("mode", 0x8D); trackByte("f0070", 0x70); trackByte("f01FA", 0x1FA)
  trackByte("tmr02", 0x802); trackByte("tmr03", 0x803); trackByte("tmr04", 0x804)
  trackByte("p2hp", 0x10C9); trackByte("p2act", 0x1081); trackByte("p1act", 0x1001)

  if t == 30 then liveness("baseline30"); tilemapCensus("init"); chrCensus("init") end
  if t == 60 then
    emu.write(0x10A1, 0xE8, emu.memType.snesWorkRam)   -- pull P2 close (32px)
    emu.write(0x10A2, 0x00, emu.memType.snesWorkRam)
    log("poke t=60 P2 X -> 00E8")
  end
  if t >= 64 and t <= 65 then pulse[0] = { y = true } end
  if t == 66 then pulse[0] = nil end
  if t == 110 then
    log(string.format("dmg-verdict t=%d p2hp=%02X (was 60)", t, ram(0x10C9)))
    liveness("afterjab")
  end
  -- Start (movelist?)
  if t >= 130 and t <= 132 then pulse[0] = { start = true } end
  if t == 133 then pulse[0] = nil end
  if t == 170 then shot("start1"); liveness("startheld"); tilemapCensus("start") end
  if t >= 200 and t <= 202 then pulse[0] = { start = true } end
  if t == 203 then pulse[0] = nil end
  if t == 240 then shot("start2") end
  -- L, R, L+R
  if t >= 260 and t <= 269 then pulse[0] = { l = true } end
  if t >= 280 and t <= 289 then pulse[0] = { r = true } end
  if t >= 300 and t <= 309 then pulse[0] = { l = true, r = true } end
  if t == 310 then pulse[0] = nil; shot("lr"); liveness("afterLR") end
  -- Select (may exit -> do last)
  if t >= 330 and t <= 332 then pulse[0] = { select = true } end
  if t == 333 then pulse[0] = nil end
  if t == 360 then shot("select1") end
  if t == 420 then shot("select2"); liveness("afterselect"); tilemapCensus("final")
    log("done"); emu.stop(0)
  end
end, emu.eventType.endFrame)

print("probe_p11_sem loaded")
