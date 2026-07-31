-- probe_sms_effectload.lua — verify the SMS-side effect-tile hypothesis: at match
-- load, is the manifest "anim payload" decompressed (via ~$C0:916B) to a WRAM
-- staging buffer and DMA'd to VRAM $6A00? Boots to Uranus-vs-Jupiter (SMS
-- charselect flow from coltest.lua), watches: DMA to VRAM $6800-7100 (source),
-- nonzero writes to $7E:6A00+ (writer PC), and reads of the manifest ptr region.
-- ROM=<clean SMS> tools/run.sh tools/saturn/probe_sms_effectload.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/bootcheck.txt", "w"))
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
  function() return sf>500 and ram(0x1001) <= 2 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if frames > 1500 and frames % 25 == 0 then
    log(string.format("f=%d p1 id=%02X act=%02X mode70=%02X clock=%02X%02X flag=%02X",
      frames, ram(0x1000), ram(0x1001), ram(0x70), ram(0x804), ram(0x803), emu.read(0x7FF100, emu.memType.snesMemory)))
  end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    -- verify: P1 became Saturn IN ROM (no pokes); tiles + palette correct
    local V = emu.memType.snesVideoRam
    local tf = io.open(ENV.TRACE .. "saturn/supers_effecttiles.bin", "rb")
    local match, total = 0, 0
    if tf then
      local d = tf:read("*a"); tf:close()
      for i = 1, 256 do
        total = total + 1
        if emu.read(0x6A00 * 2 + i - 1, V) == d:byte(i) then match = match + 1 end
      end
    end
    log(string.format("IN-MATCH: p1 id=%02X act=%02X pose=%02X flag1F60=%02X pal0600=%02X%02X tiles %d/%d",
      ram(0x1000), ram(0x1001), ram(0x1005), emu.read(0x7FF100, emu.memType.snesMemory),
      ram(0x601), ram(0x600), match, total))
    log(ram(0x1000) == 0x1C and "LR-SELECT PASS" or "LR-SELECT FAIL")
    log("done"); emu.stop(0)
  end
  if frames > 4500 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_sms_effectload loaded")
