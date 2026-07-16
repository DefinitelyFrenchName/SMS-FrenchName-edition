-- perf_patch11.lua: cycle cost + vblank span of patch 11's two stubs, plus a soak.
-- Config tools/perf_patch11_cfg.lua: STUB_I / STUB_U = 24-bit stub entries (from the
-- mkpatch11 build output), optional SOAK=true for the 5000f all-features soak.
-- Scenario: idle -> menu open (paint burst) -> nav -> close -> SHOW+record+playback.
-- Reports mean/max cycles per stub per phase + UPL2 scanline span. Thresholds:
-- each stub < 5% of a ~40850-cycle frame; UPL2 span < 25 scanlines.
-- Output: traces/p11_perf.txt
dofile("/Users/koneko/Developer/SailorMoonS/tools/perf_patch11_cfg.lua")
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p11_perf.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end
local function stw(off, v) wr(0x1F000 + off, v) end

local t, needLoad = -1, true
local iStart, uStart, uSlStart = nil, nil, nil
local stats = {}   -- phase -> {iSum,iMax,iN,uSum,uMax,uN,slMax}
local phase = "idle"
local function P() local s = stats[phase]; if not s then s = {iSum=0,iMax=0,iN=0,uSum=0,uMax=0,uN=0,slMax=0}; stats[phase]=s end; return s end
local function cyc() return emu.getState()["cpu.cycleCount"] end

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function() iStart = cyc() end,
  emu.callbackType.exec, STUB_I, STUB_I, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function()
  if iStart and t >= 0 then
    local d = cyc() - iStart; iStart = nil
    local s = P(); s.iSum = s.iSum + d; s.iN = s.iN + 1; if d > s.iMax then s.iMax = d end
  end
end, emu.callbackType.exec, 0x808377, 0x808377, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function() uStart = cyc(); uSlStart = emu.getState()["ppu.scanline"] end,
  emu.callbackType.exec, STUB_U, STUB_U, emu.cpuType.snes, emu.memType.snesMemory)
local function uEnd()
  if uStart and t >= 0 then
    local d = cyc() - uStart; uStart = nil
    local sl = emu.getState()["ppu.scanline"] - (uSlStart or 0)
    local s = P(); s.uSum = s.uSum + d; s.uN = s.uN + 1; if d > s.uMax then s.uMax = d end
    if sl > s.slMax then s.slMax = sl end
  end
end
emu.addMemoryCallback(uEnd, emu.callbackType.exec, 0x80D579, 0x80D579, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(uEnd, emu.callbackType.exec, 0x80D596, 0x80D596, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local DONE = SOAK and 5200 or 900
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if SOAK then
    phase = "soak"
    if t == 5 then
      stw(0x21, 1); stw(0x22, 1); stw(0x23, 1); stw(0x25, 1); stw(0x26, 1); stw(0x29, 1)
      wr(0x8D, 5); stw(0x04, 0xA5)
    end
    -- constant pressure: P1 attacks in bursts
    if t % 40 < 3 then pulse[0] = { down = true, y = true }
    elseif t % 40 < 6 then pulse[0] = { right = true, x = true }
    elseif t % 40 < 9 then pulse[0] = { down = true, a = true }
    else pulse[0] = nil end
    if t == 5000 then
      local ok = ram(0x1001) <= 0x7F and ram(0x1081) <= 0x7F and ram(0x10C9) <= 0x60 and ram(0x1049) <= 0x60
      log(string.format("soak sanity: p1act=%02X p2act=%02X hp=%02X/%02X mode=%02X %s",
        ram(0x1001), ram(0x1081), ram(0x1049), ram(0x10C9), ram(0x8D), ok and "OK" or "SUSPECT"))
      local f = io.open(TRACE .. "p11_soak.png", "wb"); f:write(emu.takeScreenshot()); f:close()
    end
  else
    if t < 200 then phase = "idle" end
    if t == 200 then phase = "paint" end
    if t >= 200 and t <= 202 then pulse[0] = { l = true, r = true } elseif t == 203 then pulse[0] = nil end
    if t == 260 then phase = "menunav" end
    if t >= 260 and t % 10 < 2 and t < 340 then pulse[0] = { down = true } elseif t >= 260 and t < 340 then pulse[0] = nil end
    if t == 340 then phase = "close"; stw(0x29, 1); stw(0x27, 1) end   -- SHOW on + REC arm
    if t >= 345 and t <= 347 then pulse[0] = { l = true, r = true } elseif t == 348 then pulse[0] = nil end
    if t == 360 then phase = "record" end
    if t >= 360 and t < 500 then
      if t % 20 < 4 then pulse[0] = { down = true } elseif t % 20 < 6 then pulse[0] = { down = true, y = true } else pulse[0] = nil end
    end
    if t >= 500 and t <= 502 then pulse[0] = { l = true, r = true } elseif t == 503 then pulse[0] = nil end
    if t == 510 then stw(0x28, 2) end
    if t >= 515 and t <= 517 then pulse[0] = { l = true, r = true } elseif t == 518 then pulse[0] = nil end
    if t == 530 then phase = "playback+show" end
  end
  if t == DONE then
    local worst = 0
    for ph, s in pairs(stats) do
      local im = s.iN > 0 and math.floor(s.iSum / s.iN) or 0
      local um = s.uN > 0 and math.floor(s.uSum / s.uN) or 0
      log(string.format("%-14s INPUT mean=%d max=%d | UPL2 mean=%d max=%d slMax=%d",
        ph, im, s.iMax, um, s.uMax, s.slMax))
      local w = (s.iMax + s.uMax) / 40850 * 100
      if w > worst then worst = w end
    end
    log(string.format("worst combined stub frame cost: %.2f%% (ceiling 5%%)", worst))
    log(worst < 5 and "PERF PASS" or "PERF FAIL")
    emu.stop(worst < 5 and 0 or 1)
  end
end, emu.eventType.endFrame)
print("perf_patch11 loaded")
