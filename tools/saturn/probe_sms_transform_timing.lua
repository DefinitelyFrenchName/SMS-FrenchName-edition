-- probe_sms_transform_timing.lua — measure WHEN the L+R shell becomes Saturn:
-- boots to Uranus-vs-Jupiter with L+R held on both pads, then logs the frame the
-- helper latch ($7F:F102 == $A5) arms vs the frame $1000 becomes $1C, with the
-- gate variables ($1E04 / $01FA / $70) every frame and entrance screenshots —
-- the question is which gate could move her transform earlier, before control.
-- Also retains the effectload watchers (writes to $7E:6A00/$7F:0000, DMA to
-- VRAM $6800-7100) in case the swap streams tiles.
-- ROW=<mode row> ROM=build/saturn/<rom> tools/run.sh tools/saturn/probe_sms_transform_timing.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/lrboth.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local watching = false
local wseen = 0

local function beat(on) return (frames % 7) < 3 and on or {} end

local function pcstr()
  local ok, st = pcall(emu.getState)
  local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"])
  local k = st and (st["cpu.k"] or st["snes.cpu.k"])
  return pc and string.format("%02X:%04X", k or 0, pc) or "?"
end

-- staging-buffer writes (both the $7E:6A00 hypothesis and $7F:0000 like Super S)
for _, rng in ipairs({ { 0x7E6A00, 0x7E6A1F }, { 0x7F0000, 0x7F001F } }) do
  emu.addMemoryCallback(function(addr, value)
    if watching and (value or 0) ~= 0 and wseen < 8 then
      wseen = wseen + 1
      log(string.format("f=%d W %06X <= %02X @ %s", frames, addr, value or -1, pcstr()))
    end
  end, emu.callbackType.write, rng[1], rng[2], emu.cpuType.snes, emu.memType.snesMemory)
end

local vaddr = 0
for _, base in ipairs({ 0x002116, 0x802116 }) do
  emu.addMemoryCallback(function(addr, value)
    vaddr = (vaddr & 0xFF00) | (value or 0)
  end, emu.callbackType.write, base, base, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(addr, value)
    vaddr = (vaddr & 0x00FF) | ((value or 0) << 8)
  end, emu.callbackType.write, base + 1, base + 1, emu.cpuType.snes, emu.memType.snesMemory)
end
local REG = emu.memType.snesMemory
local function reg(a) return emu.read(0x800000 + a, REG) end
for _, base in ipairs({ 0x00420B, 0x80420B }) do
  emu.addMemoryCallback(function(addr, value)
    if not watching or (value or 0) == 0 then return end
    for ch = 0, 7 do
      if ((value >> ch) & 1) == 1 then
        local c = 0x4300 + ch * 0x10
        local bbus = reg(c + 1)
        if (bbus == 0x18 or bbus == 0x19) and vaddr >= 0x6800 and vaddr < 0x7100 then
          local src = reg(c + 2) + 256 * reg(c + 3) + 65536 * reg(c + 4)
          local sz = reg(c + 5) + 256 * reg(c + 6)
          local ok, st = pcall(emu.getState)
          local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
          local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
          log(string.format("f=%d DMA ch%d VRAM %04X <- %06X len %04X @ %02X:%04X",
            frames, ch, vaddr, src, sz, k, pc))
        end
      end
    end
  end, emu.callbackType.write, base, base, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if frames > 1400 then b.l = true; b.r = true end   -- hold L+R on BOTH pads
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local ROW = tonumber(os.getenv("ROW") or "1")   -- player-select row = game mode
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==ROW end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() return sf>240 end,
  function() wr(0x1B40, 6); wr(0x1B80, 4); return sf>20 end,     -- Uranus vs Jupiter
  function() pulse[0]=beat({a=true}); watching=true; return ram(0x1B42)==1 or sf>90 end,
  function() pulse[0]={}; return sf>30 end,
  function() pulse[1]=beat({a=true}); return sf>60 end,
  function() return sf>240 end,
  function() pulse[0]=beat({start=true}); pulse[1]=beat({start=true})
             return (ram(0x1000)==6 and ram(0x1080)~=0) or sf>600 end,
  function() return sf>500 and ram(0x1001) <= 2 end,
}


-- WHEN does the shell become Saturn, and what is on screen at that moment?
-- The helper's gates are: $1E04 == 0 (intro sequencer idle), $01FA == 0x80
-- (round live) and the object's act < 3. The maintainer wants her visible
-- BEFORE the player gets control, so the question is what those three read
-- during the entrance, and which of them can move earlier safely.
local armed_at, became_at = nil, nil
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local latch = emu.read(0x7FF102, emu.memType.snesMemory) or 0
  if latch == 0xA5 and not armed_at then
    armed_at = frames
    log(string.format("f=%d LATCH ARMED  id=%02X act=%02X $1E04=%02X $01FA=%02X MODE $8D=%02X",
      frames, ram(0x1000), ram(0x1001), ram(0x1E04), ram(0x1FA), ram(0x8D)))
  end
  if armed_at and not became_at and ram(0x1000) == 0x1C then
    became_at = frames
    log(string.format("f=%d BECAME SATURN (+%d frames)  act=%02X $1E04=%02X $01FA=%02X MODE $8D=%02X",
      frames, frames - armed_at, ram(0x1001), ram(0x1E04), ram(0x1FA), ram(0x8D)))
  end
  if armed_at and frames <= armed_at + 260 then
    log(string.format("  f=%d id=%02X act=%02X $1E04=%02X $01FA=%02X $70=%02X",
      frames, ram(0x1000), ram(0x1001), ram(0x1E04), ram(0x1FA), ram(0x70)))
  end
  if armed_at then
    local d = frames - armed_at
    if d == 60 or d == 110 or d == 160 or d == 210 or d == 260 or d == 320 then
      local f = io.open(ENV.TRACE .. "saturn/entrance_" .. d .. ".png", "wb")
      f:write(emu.takeScreenshot()); f:close()
    end
  end
  if armed_at and frames > armed_at + 340 then log("done"); emu.stop(0) end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if frames > 3000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_transform_timing loaded")
