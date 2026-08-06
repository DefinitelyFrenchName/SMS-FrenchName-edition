-- probe_sms_p2effect.lua — where would P2's effect tiles go? P1-only L+R
-- Saturn load (Uranus-vs-Jupiter poked at charselect) with the DMA watch
-- widened to VRAM $6800-7A00 (source + PC per transfer); once in-match, dumps
-- the pad/effect vars $5C/$5E/$1050/$01FA and exits.
-- ROM=build/saturn/<rom> tools/run.sh tools/saturn/probe_sms_p2effect.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/p2effect.txt", "w"))
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
        if (bbus == 0x18 or bbus == 0x19) and vaddr >= 0x6800 and vaddr < 0x7A00 then
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
    if p == 0 and frames > 1400 then b.l = true; b.r = true end   -- hold L+R through load
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() return sf>240 end,
  function() wr(0x1B40, 6); wr(0x1B80, 4); return sf>20 end,     -- Uranus vs Jupiter
  function() pulse[0]=beat({a=true}); watching=true; return ram(0x1B42)==1 or sf>90 end,
  function() pulse[0]={}; return sf>30 end,
  function() pulse[1]=beat({a=true}); return sf>60 end,
  function() return sf>240 end,
  function() pulse[0]=beat({start=true}); pulse[1]=beat({start=true})
             return (ram(0x1000)==6 and ram(0x1080)~=0) or sf>600 end,
  function() return sf>150 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("IN-MATCH; pad vars: 5C=%02X%02X 5E=%02X%02X 1050=%02X%02X 01FA=%02X",
      ram(0x5D), ram(0x5C), ram(0x5F), ram(0x5E), ram(0x1051), ram(0x1050), ram(0x1FA)))
    log("done"); emu.stop(0)
  end
  if frames > 4500 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_sms_effectload loaded")
