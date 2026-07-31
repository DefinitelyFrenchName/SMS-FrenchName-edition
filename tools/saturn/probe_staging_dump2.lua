-- probe_supers_effectload.lua — find where Saturn's EFFECT TILES (VRAM $6A00+,
-- OBJ tiles 0xA0-0xFF) come from at match load. Boots to Saturn-vs-Uranus like
-- probe_supers_saturn.lua; from char-select-confirm onward, every $420B (MDMAEN)
-- write logs channels whose B-bus is $2118/$2119 with VRAM addr in $6800-$7000:
-- source A-bus address = the (decompressed?) buffer to trace next.
-- ROM=<Super S> tools/run.sh tools/saturn/probe_supers_effectload.lua 200
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/effectload.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local watching = false

local function beat(on) return (frames % 7) < 3 and on or {} end

-- writer PC on the $7F decompression buffer head + first ROM reads
local wseen, rseen = 0, 0
local dumped = false
-- log every decompressor invocation: $C4/5=src16 $C6=bank $C2=dst $C0=count
emu.addMemoryCallback(function()
  if not watching then return end
  local c4 = ram(0xC4) + 256 * ram(0xC5)
  local c6 = ram(0xC6)
  local c2 = ram(0xC2) + 256 * ram(0xC3)
  local c0 = ram(0xC0) + 256 * ram(0xC1)
  log(string.format("f=%d LZJOB src=%02X:%04X dst=7F:%04X count=%04X", frames, c6, c4, c2, c0))
end, emu.callbackType.exec, 0x80EE39, 0x80EE39, emu.cpuType.snes, emu.memType.snesMemory)
local function pcstr()
  local ok, st = pcall(emu.getState)
  local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"])
  local k = st and (st["cpu.k"] or st["snes.cpu.k"])
  return pc and string.format("%02X:%04X", k or 0, pc) or "?"
end
emu.addMemoryCallback(function(addr, value)
  if watching and (value or 0) ~= 0 and wseen < 8 then
    wseen = wseen + 1
    local ok, st = pcall(emu.getState)
    local x = st and (st["cpu.x"] or st["snes.cpu.x"]) or -1
    log(string.format("f=%d W 7F%04X <= %02X @ %s X=%04X ins[00C8..CE]=%02X %02X %02X %02X %02X %02X",
      frames, addr % 0x10000, value or -1, pcstr(), x,
      ram(0xC8), ram(0xC9), ram(0xCA), ram(0xCB), ram(0xCC), ram(0xCD)))
  end
end, emu.callbackType.write, 0x7F0000, 0x7F00FF, emu.cpuType.snes, emu.memType.snesMemory)

-- track the VRAM address latch
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
        if bbus == 0x18 or bbus == 0x19 then
          local src = reg(c + 2) + 256 * reg(c + 3) + 65536 * reg(c + 4)
          local sz = reg(c + 5) + 256 * reg(c + 6)
          if vaddr >= 0x6800 and vaddr < 0x7100 then
            log(string.format("f=%d DMA ch%d VRAM %04X <- %06X len %04X", frames, ch, vaddr, src, sz))
            if not dumped and src == 0x7F0000 then
              dumped = true
              local f = assert(io.open(ENV.TRACE .. "saturn/staging_7f.bin", "wb"))
              local bytes = {}
              for i = 0, 0x14A0 - 1 do
                bytes[#bytes+1] = string.char(emu.read(0x7F0000 + i, emu.memType.snesMemory))
              end
              f:write(table.concat(bytes)); f:close()
              log("staging dumped at DMA moment")
            end
          end
        end
      end
    end
  end, emu.callbackType.write, base, base, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() return sf>240 end,
  function() wr(0x1B40, 10); wr(0x1B80, 6); return sf>20 end,
  function() pulse[0]=beat({a=true}); watching=true; return ram(0x1B42)==1 or sf>90 end,
  function() pulse[0]={}; return sf>30 end,
  function() pulse[1]=beat({a=true}); return sf>60 end,
  function() return sf>240 end,
  function() pulse[0]=beat({start=true}); pulse[1]=beat({start=true})
             return (ram(0x1000)==10 and ram(0x1080)~=0) or sf>600 end,
  function() return sf>150 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("IN-MATCH; done"); emu.stop(0) end
  if frames > 4500 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_supers_effectload loaded")
