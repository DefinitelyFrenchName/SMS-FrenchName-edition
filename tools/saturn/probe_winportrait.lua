
-- probe_winportrait.lua — the report-card screen: which per-WINNER-id tables /
-- decompression jobs drive the portrait? Play a quick 1P match to a KO, then
-- watch LZ jobs + DMAs while the report card builds.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/winportrait_" .. (os.getenv("TAG") or "van") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local watching = false
local function beat(on) return (frames % 10) < 2 and on or {} end
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)
-- LZ jobs (the decompressor entry) with src/dst
emu.addMemoryCallback(function()
  if not watching then return end
  log(string.format("f=%d LZJOB src=%02X:%04X dst=7F:%04X count=%04X",
    frames, ram(0xC6), ram(0xC4) + 256 * ram(0xC5),
    ram(0xC2) + 256 * ram(0xC3), ram(0xC0) + 256 * ram(0xC1)))
end, emu.callbackType.exec, 0x80EE39, 0x80EE39, emu.cpuType.snes, emu.memType.snesMemory)
-- VRAM DMA kicks
local vaddr = 0
for _, base in ipairs({0x002116, 0x802116}) do
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0xFF00) | (v or 0) end,
    emu.callbackType.write, base, base, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0x00FF) | ((v or 0) << 8) end,
    emu.callbackType.write, base + 1, base + 1, emu.cpuType.snes, emu.memType.snesMemory)
end
local REG = emu.memType.snesMemory
local function reg(a) return emu.read(0x800000 + a, REG) end
for _, base in ipairs({0x00420B, 0x80420B}) do
  emu.addMemoryCallback(function(addr, value)
    if not watching or (value or 0) == 0 then return end
    for ch = 0, 7 do
      if ((value >> ch) & 1) == 1 then
        local c = 0x4300 + ch * 0x10
        if reg(c + 1) == 0x18 or reg(c + 1) == 0x19 then
          local src = reg(c+2) + 256*reg(c+3) + 65536*reg(c+4)
          log(string.format("f=%d DMA VRAM %04X <- %06X len %04X", frames, vaddr, src, reg(c+5) + 256*reg(c+6)))
        end
      end
    end
  end, emu.callbackType.write, base, base, emu.cpuType.snes, emu.memType.snesMemory)
end
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function()
    pulse[0] = (sf % 20 < 3) and {start=true} or {}
    if ram(0x1B40) ~= 0 then return sf > 60 end
    if sf > 1200 then log("NO-CHARSEL"); emu.stop(1) end
    return false
  end,
  function() wr(0x1B40, 6); pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>150 end,
  function()
    pulse[0] = (sf % 14 < 3) and {a=true} or ((sf % 14 >= 7 and sf % 14 < 10) and {start=true} or {})
    if ram(0x70)==4 and ram(0x1000)~=0 and ram(0x1080)~=0 then return true end
    if sf > 2500 then log("NO-FIGHT"); emu.stop(1) end
    return false
  end,
  function() return sf > 150 end,
  -- KO both rounds fast
  function() wr(0x10C9, 1); pulse[0]=beat({y=true}); return ram(0x10C9)==0 or sf>400 end,
  function() pulse[0]={}; return sf>420 end,
  function() wr(0x10C9, 1); pulse[0]=beat({y=true}); return ram(0x10C9)==0 or sf>500 end,
  function() watching = true; log("-- watching (post match-end)"); pulse[0]={}; return sf>60 end,
  function()
    pulse[0] = (sf % 30 < 3) and {start=true} or {}
    if sf == 300 or sf == 600 then
      local png = emu.takeScreenshot()
      local f = assert(io.open(ENV.TRACE .. "saturn/winportrait_" .. (os.getenv("TAG") or "van") .. "_" .. sf .. ".png", "wb"))
      f:write(png); f:close()
      log("shot at +" .. sf)
    end
    return sf > 700
  end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 9000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("winportrait loaded")
