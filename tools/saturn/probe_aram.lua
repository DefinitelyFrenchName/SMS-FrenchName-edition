
-- probe_cardportrait.lua — VS flow, P1 selects CHAR (poked at select), KO P2
-- twice, dump VRAM + screenshot at the report card. Run with two CHARs and
-- diff to locate the portrait tiles.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "6")
local TAG = os.getenv("TAG") or "x"
local LOG = assert(io.open(ENV.TRACE .. "saturn/cardsat_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local function beat(on) return (frames % 10) < 2 and on or {} end
local code = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if code[p] then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)
local watching = false
local vaddr = 0
for _, b in ipairs({0x002116, 0x802116}) do
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0xFF00) | (v or 0) end,
    emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0x00FF) | ((v or 0) << 8) end,
    emu.callbackType.write, b + 1, b + 1, emu.cpuType.snes, emu.memType.snesMemory)
end
local REG = emu.memType.snesMemory
local function reg(a) return emu.read(0x800000 + a, REG) end
for _, b in ipairs({0x00420B, 0x80420B}) do
  emu.addMemoryCallback(function(addr, value)
    if not watching or (value or 0) == 0 then return end
    for ch = 0, 7 do
      if ((value >> ch) & 1) == 1 then
        local c = 0x4300 + ch * 0x10
        if reg(c + 1) == 0x18 or reg(c + 1) == 0x19 then
          local ok, st = pcall(emu.getState)
          log(string.format("DMA VRAM %04X <- %02X:%04X len %04X @ %02X:%04X dp30=%02X%02X dp36=%02X",
            vaddr, reg(c+4), reg(c+2) + 256*reg(c+3), reg(c+5) + 256*reg(c+6),
            st and (st["cpu.k"] or st["snes.cpu.k"]) or -1,
            st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1,
            ram(0x31), ram(0x30), ram(0x36)))
        end
      end
    end
  end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end
local vw = {}
for _, b in ipairs({0x002118, 0x802118, 0x002119, 0x802119}) do
  emu.addMemoryCallback(function(addr, value)
    if not watching then return end
    local ok, st = pcall(emu.getState)
    local pc = (st and (st["cpu.k"] or 0) or 0) * 0x10000 + (st and (st["cpu.pc"] or 0) or 0)
    vw[pc] = (vw[pc] or 0) + 1
  end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end
local hooks = 0
local oamw, oamlog = 0, {}
local cardnow = false
local emit, emitlog = 0, {}
local lw, lwlog = 0, {}
-- who writes the CGRAM shadow row 8 ($7E:0600) during the card?
local pw, pwlog = 0, {}
for _, r in ipairs({{0x7E0600, 0x7E060F}, {0x000600, 0x00060F}}) do
  emu.addMemoryCallback(function(addr, value)
    if not cardnow or pw > 24 then return end
    local ok, st = pcall(emu.getState)
    local k = st and (st["cpu.k"] or 0) or 0
    if k == 0xEE then return end          -- ignore our own palette copier
    pw = pw + 1
    pwlog[#pwlog+1] = string.format("%04X<=%02X @%02X:%04X", addr % 0x10000, value or 0,
      k, st and (st["cpu.pc"] or 0) or 0)
  end, emu.callbackType.write, r[1], r[2], emu.cpuType.snes, emu.memType.snesMemory)
end
-- (a) who CALLS the sprite emitter: read the return address off the stack
local callers, ncall = {}, 0
for _, a in ipairs({0x809B17, 0x809BCB}) do
  emu.addMemoryCallback(function()
    if not cardnow or ncall > 6 then return end
    ncall = ncall + 1
    local ok, st = pcall(emu.getState)
    local sp = st and (st["cpu.sp"] or st["snes.cpu.sp"]) or 0
    local lo = emu.read(sp + 1, emu.memType.snesMemory)
    local hi = emu.read(sp + 2, emu.memType.snesMemory)
    local bk = emu.read(sp + 3, emu.memType.snesMemory)
    callers[#callers+1] = string.format("ret=%02X:%04X list=%02X:%02X%02X cnt=%02X",
      bk, (hi * 256 + lo), ram(0x14), ram(0x13), ram(0x12), ram(0x00))
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
-- (b) CGRAM transfers (B-bus $22) — the earlier watcher only looked at VRAM
local cgdma, cgn = {}, 0
for _, b in ipairs({0x00420B, 0x80420B}) do
  emu.addMemoryCallback(function(addr, value)
    if (value or 0) == 0 or cgn > 8 then return end
    for ch = 0, 7 do
      if ((value >> ch) & 1) == 1 then
        local c = 0x4300 + ch * 0x10
        local bbus = emu.read(0x800000 + c + 1, emu.memType.snesMemory)
        if bbus == 0x22 and (not cardnow or cgn < 14) then
          cgn = cgn + 1
          local ok, st = pcall(emu.getState)
          cgdma[#cgdma+1] = string.format("CGDMA <- %02X:%02X%02X len %02X%02X cgadd=? @%02X:%04X %s",
            emu.read(0x800000 + c + 4, emu.memType.snesMemory),
            emu.read(0x800000 + c + 3, emu.memType.snesMemory),
            emu.read(0x800000 + c + 2, emu.memType.snesMemory),
            emu.read(0x800000 + c + 6, emu.memType.snesMemory),
            emu.read(0x800000 + c + 5, emu.memType.snesMemory),
            st and (st["cpu.k"] or 0) or 0, st and (st["cpu.pc"] or 0) or 0,
            cardnow and "(card)" or "(pre-card)")
        end
      end
    end
  end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end
-- (c) direct CGDATA writes
local cgw, cgwn = {}, 0
for _, a in ipairs({0x002122, 0x802122}) do
  emu.addMemoryCallback(function(addr, value)
    if not cardnow or cgwn > 6 then return end
    cgwn = cgwn + 1
    local ok, st = pcall(emu.getState)
    cgw[#cgw+1] = string.format("$2122<=%02X @%02X:%04X", value or 0,
      st and (st["cpu.k"] or 0) or 0, st and (st["cpu.pc"] or 0) or 0)
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
for _, a in ipairs({0x7E0012, 0x000012}) do
  emu.addMemoryCallback(function(addr, value)
    if not cardnow or lw > 8 then return end
    lw = lw + 1
    local ok, st = pcall(emu.getState)
    lwlog[#lwlog+1] = string.format("$12<=%02X @%02X:%04X (A=%04X X=%04X Y=%04X)", value or 0,
      st and (st["cpu.k"] or 0) or 0, st and (st["cpu.pc"] or 0) or 0,
      st and (st["cpu.a"] or 0) or 0, st and (st["cpu.x"] or 0) or 0, st and (st["cpu.y"] or 0) or 0)
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
for _, a in ipairs({0x809B17, 0x809BCB}) do
  emu.addMemoryCallback(function(addr)
    if not cardnow or emit > 10 or ram(0x00) < 4 then return end
    emit = emit + 1
    local ok, st = pcall(emu.getState)
    emitlog[#emitlog+1] = string.format("%06X list=%02X:%02X%02X cnt=%02X x=%02X%02X y=%02X%02X DB=%02X",
      addr, ram(0x14), ram(0x13), ram(0x12), ram(0x00),
      ram(0x02), ram(0x01), ram(0x04), ram(0x03),
      st and (st["cpu.db"] or 0) or 0)
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
for _, r in ipairs({{0x7E0200, 0x7E027F}, {0x000200, 0x00027F}}) do
  emu.addMemoryCallback(function(addr, value)
    local v = value or 0
    if oamw > 20 or v == 0xE0 or v == 0x00 then return end
    if (addr % 4) ~= 2 then return end          -- tile-number byte only
    oamw = oamw + 1
    local ok, st = pcall(emu.getState)
    oamlog[#oamlog+1] = string.format("%04X<=%02X @%02X:%04X", addr % 0x10000, value or 0,
      st and (st["cpu.k"] or 0) or 0, st and (st["cpu.pc"] or 0) or 0)
  end, emu.callbackType.write, r[1], r[2], emu.cpuType.snes, emu.memType.snesMemory)
end
local ppu = {}
for reg = 0x2105, 0x210C do
  for _, b in ipairs({reg, 0x800000 + reg}) do
    emu.addMemoryCallback(function(addr, value)
      ppu[reg] = value
    end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
  end
end
for _, spec in ipairs({{0xEEC932, "blit-label"}, {0xEEC97D, "dma-kick"}, {0xEEC918, "p1-branch"}}) do
  emu.addMemoryCallback(function()
    log("REACHED " .. spec[2])
  end, emu.callbackType.exec, spec[1], spec[1], emu.cpuType.snes, emu.memType.snesMemory)
end
local vad, ourdma = 0, 0
for _, b in ipairs({0x002116, 0x802116}) do
  emu.addMemoryCallback(function(a, v) vad = (vad & 0xFF00) | (v or 0) end,
    emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(a, v) vad = (vad & 0x00FF) | ((v or 0) << 8) end,
    emu.callbackType.write, b + 1, b + 1, emu.cpuType.snes, emu.memType.snesMemory)
end
local REG2 = emu.memType.snesMemory
for _, b in ipairs({0x00420B, 0x80420B}) do
  emu.addMemoryCallback(function(addr, value)
    if (value or 0) == 0 then return end
    local bank = emu.read(0x800000 + 0x4304, REG2)
    local len = emu.read(0x800000 + 0x4305, REG2) + 256 * emu.read(0x800000 + 0x4306, REG2)
    if bank == 0xEE then
      ourdma = ourdma + 1
      log(string.format("OUR DMA fired: VRAM %04X <- EE:%02X%02X len %04X",
        vad, emu.read(0x800000 + 0x4303, REG2), emu.read(0x800000 + 0x4302, REG2), len))
    end
  end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addMemoryCallback(function()
  hooks = hooks + 1
  if hooks <= 6 then
    log(string.format("CARDPORT stub #%d: dp03=%02X%02X flagP1=%02X flagP2=%02X",
      hooks, ram(0x04), ram(0x03),
      emu.read(0x7FF100, emu.memType.snesMemory),
      emu.read(0x7FF101, emu.memType.snesMemory)))
  end
end, emu.callbackType.exec, 0xEEC900, 0xEEC900, emu.cpuType.snes, emu.memType.snesMemory)
local function dumpvram(tag)
  local V = emu.memType.snesVideoRam
  local f = assert(io.open(ENV.TRACE .. "saturn/vramcardsat_" .. tag .. ".bin", "wb"))
  local b = {}
  for i = 0, 0xFFFF do b[#b+1] = string.char(emu.read(i, V)) end
  f:write(table.concat(b)); f:close()
  local png = emu.takeScreenshot()
  local g = assert(io.open(ENV.TRACE .. "saturn/card_" .. tag .. ".png", "wb"))
  g:write(png); g:close()
  local rows = {}
  for pc, n in pairs(vw) do rows[#rows+1] = {n, pc} end
  table.sort(rows, function(x, y) return x[1] > y[1] end)
  for i = 1, math.min(#rows, 8) do
    log(string.format("VRAM-write PC %06X: %d writes", rows[i][2], rows[i][1]))
  end
  log(string.format("stub hits=%d  flags P1=%02X P2=%02X  p1id=%02X", hooks,
    emu.read(0x7FF100, emu.memType.snesMemory),
    emu.read(0x7FF101, emu.memType.snesMemory), ram(0x1000)))
  log("our DMAs: " .. ourdma)
  local cg = {}
  for i = 0, 511 do cg[#cg+1] = string.char(emu.read(i, emu.memType.snesCgRam)) end
  local cf = assert(io.open(ENV.TRACE .. "saturn/cgcard_" .. tag .. ".bin", "wb"))
  cf:write(table.concat(cg)); cf:close()
  local sh = {}
  for i = 0x0500, 0x06FF do sh[#sh+1] = string.char(ram(i)) end
  local sf2 = assert(io.open(ENV.TRACE .. "saturn/cgshadow_" .. tag .. ".bin", "wb"))
  sf2:write(table.concat(sh)); sf2:close()
  local wb = {}
  for i = 0, 0x1FFF do wb[#wb+1] = string.char(ram(i)) end
  local wf = assert(io.open(ENV.TRACE .. "saturn/wram_" .. tag .. ".bin", "wb"))
  wf:write(table.concat(wb)); wf:close()
  local parts = {}
  for r = 0x2105, 0x210C do parts[#parts+1] = string.format("%04X=%02X", r, ppu[r] or 0xFF) end
  log("PPU " .. table.concat(parts, " "))
  local o = {}
  for i = 0, 543 do o[#o+1] = string.char(emu.read(i, emu.memType.snesSpriteRam)) end
  local of = assert(io.open(ENV.TRACE .. "saturn/oamcard_" .. tag .. ".bin", "wb"))
  of:write(table.concat(o)); of:close()
  -- find the object slot whose +0x64 holds the portrait list pointer
  local found = {}
  for base = 0x1000, 0x1F80, 0x80 do
    local lo, hi = ram(base + 0x64), ram(base + 0x65)
    if lo ~= 0 or hi ~= 0 then
      found[#found+1] = string.format("obj $%04X: +64=%02X%02X +66=%02X id=%02X",
        base, hi, lo, ram(base + 0x66), ram(base))
    end
  end
  log("OBJECTS with a sprite list: " .. table.concat(found, " | "))
  log("SHADOW row8 writers: " .. table.concat(pwlog, " | "))
  log("EMITTER CALLERS: " .. table.concat(callers, " | "))
  log("CGRAM DMAs: " .. table.concat(cgdma, " | "))
  log("CGDATA writes: " .. table.concat(cgw, " | "))
  log("LIST-PTR writers: " .. table.concat(lwlog, " | "))
  log("EMITTER calls: " .. table.concat(emitlog, " | "))
  log("OAM-shadow writers: " .. table.concat(oamlog, " "))
  log("dumped " .. tag)
end
-- STAGEFORCE: different stage => different music => different echo content
local forced = false
if os.getenv("STAGE") then
  emu.addMemoryCallback(function()
    if forced or frames < 1700 then return end
    forced = true
    wr(0x8E, tonumber(os.getenv("STAGE")) * 2)
  end, emu.callbackType.exec, 0x808586, 0x808586, emu.cpuType.snes, emu.memType.snesMemory)
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() return sf>300 end,
  function() wr(0x1B40, CHAR); wr(0x1B80, tonumber(os.getenv("CHAR2") or "6")); return sf>20 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>150 end,
  function() pulse[1]=beat({a=true}); return ram(0x1B82)==1 or sf>150 end,
  function()
    pulse[0] = (sf % 20 < 3) and {start=true} or {}
    if ram(0x70)==4 and ram(0x1000)~=0 and ram(0x1080)~=0 then return true end
    if sf > 900 then log("NO-MATCH"); emu.stop(1) end
    return false
  end,
  function() return sf > 200 end,
  function()   -- dump APU RAM (ARAM) mid-match
    local names = {"spcMemory", "spcRam", "SpcMemory"}
    local mt = nil
    for _, n in ipairs(names) do if emu.memType[n] then mt = emu.memType[n]; log("ARAM memType: " .. n) end end
    if mt == nil then
      for k, v in pairs(emu.memType) do log("memType " .. tostring(k)) end
      log("NO ARAM MEMTYPE"); return true
    end
    local b = {}
    for i = 0, 0xFFFF do b[#b+1] = string.char(emu.read(i, mt)) end
    local f = assert(io.open(ENV.TRACE .. "saturn/aram_" .. TAG .. ".bin", "wb"))
    f:write(table.concat(b)); f:close()
    log("aram dumped")
    return true
  end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 9000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("cardportrait loaded char=" .. CHAR)
