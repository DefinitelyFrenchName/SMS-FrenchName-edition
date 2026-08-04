-- probe_fontdma2.lua — read the DMA parameters from DIRECT PAGE at the trigger.
--
-- The upload routines ($C0:9287 / $C0:92AD) stage a transfer in direct page and
-- fire $420B: $00 = VRAM word address, $02 = length, $04 = source address,
-- $06 = source bank (the $30/$32/$34/$36 variant is the same shape).
--
-- Reading the DMA REGISTERS back at the trigger does not work — $4301 and
-- friends are WRITE-ONLY, so a filter built on emu.read($4301) silently drops
-- most transfers, which is how the font upload stayed hidden through three
-- probes. Read the direct page instead: it is real RAM and it still holds what
-- the routine just wrote.
--
--   ROM=<rom> tools/run.sh tools/probe_fontdma2.lua 400
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram = PL.ram
local MEM = emu.memType.snesMemory
local LOG = assert(io.open(ENV.TRACE .. (os.getenv("TAG") or "fontdma2") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local frames, step, sf = 0, 1, 0
local pulse = {}
local n, big = 0, {}

local function st()
  local ok, s = pcall(emu.getState)
  return ok and s or nil
end

for b = 0x00, 0xBF do
  if b <= 0x3F or b >= 0x80 then
    local a = (b << 16) | 0x420B
    emu.addMemoryCallback(function(_, v)
      if (v or 0) == 0 then return end
      local s = st()
      if not s then return end
      local dp = s["cpu.d"] or 0
      local pc = ((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)
      local function w(o)
        return (emu.read(dp + o, MEM) or 0) | ((emu.read(dp + o + 1, MEM) or 0) << 8)
      end
      -- Only the real uploader. Reading direct page blind at every $420B write
      -- picks up whatever happens to be there for transfers staged by other
      -- code, which produced pages of impossible parameters (len=$FFE7 and so
      -- on). $C0:92D2 is the routine disassembled at $C0:92AD; trust it alone.
      if pc ~= 0x8092D2 then return end
      for _, base in ipairs({ 0x00 }) do
        local vad, len = w(base + 0), w(base + 2)
        local src, bank = w(base + 4), emu.read(dp + base + 6, MEM) or 0
        if len > 0 then
          n = n + 1
          local last = vad + len // 2
          local hit = (vad <= 0x5000 and last > 0x5000)
          local key = string.format("dp+%02X vram=$%04X len=$%04X src=$%02X:%04X pc=$%06X%s",
            base, vad, len, bank, src, pc, hit and "   <== COVERS the font" or "")
          if not big[key] then big[key] = 0 end
          big[key] = big[key] + 1
        end
      end
    end, emu.callbackType.write, a, a, emu.cpuType.snes, MEM)
  end
end

local function beat(on) return (frames % 7) < 3 and on or {} end
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 400 end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("large DMAs observed: %d", n))
    local ks = {}
    for k, v in pairs(big) do ks[#ks + 1] = string.format("%s  x%d", k, v) end
    table.sort(ks)
    for _, l in ipairs(ks) do log("  " .. l) end
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT " .. step); emu.stop(1) end
end, emu.eventType.endFrame)
