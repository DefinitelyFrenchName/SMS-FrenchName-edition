-- probe_sms_lztrace.lua — single-step SMS's movelist decompressor ($C0:919F)
-- and log every decision, so a Python twin can be checked against it.
--
-- The format is hand-decoded and correct for the first $14F output bytes of
-- Uranus's movelist, then diverges — the tenth literal in a run comes out as the
-- stream's next byte where the real output has a different one. Rather than
-- guess further, this logs what the ROM itself does:
--   $C0:91C5  literal   -> source $00, dest $03
--   $C0:9240  copy      -> dest $03, distance $14, count $16
-- Comparing the two traces names the exact operation where they part company.
--
-- usage: CHAR=6 ROM=<rom> tools/run.sh tools/saturn/probe_sms_lztrace.lua 400
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "6")
local DUMMY = tonumber(os.getenv("DUMMY") or "4")
local N = tonumber(os.getenv("N") or "80")
local TAG = os.getenv("TAG") or ("lz" .. (os.getenv("CHAR") or "6"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/lztrace_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local MEM = emu.memType.snesMemory

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end
local function slowbeat(on) return (frames % 20) < 4 and on or {} end

local function r8(a) return emu.read(0x7E0000 + a, MEM) end
local function r16(a) return r8(a) + 256 * r8(a + 1) end

local arm, n = false, 0
-- arm only for the movelist expand (source = the per-character pointer)
for _, a in ipairs({ 0x00919F, 0x80919F, 0xC0919F }) do
  emu.addMemoryCallback(function()
    local src = r16(0x00) + 0x10000 * r8(0x02)
    -- the nine movelist sources live in bank $E2 between $6F40 and $7C00
    arm = (r8(0x02) == 0xE2 and r16(0x00) >= 0x6F40 and r16(0x00) < 0x7C00)
    if arm then
      n = 0
      log(string.format("=== decompress src $%06X (char %d) ===", src, ram(0x1000)))
    end
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, MEM)
end
for _, a in ipairs({ 0x0091C5, 0x8091C5, 0xC091C5 }) do
  emu.addMemoryCallback(function()
    if not arm or n >= N then return end
    n = n + 1
    log(string.format("%3d LIT   src +%04X  dest %04X  byte %02X", n,
      r16(0x00) - 0x6F40, r16(0x03), emu.read(r8(0x02) * 0x10000 + r16(0x00), MEM)))
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, MEM)
end
for _, a in ipairs({ 0x009240, 0x809240, 0xC09240 }) do
  emu.addMemoryCallback(function()
    if not arm or n >= N then return end
    n = n + 1
    local d = r16(0x14)
    if d >= 0x8000 then d = d - 0x10000 end
    log(string.format("%3d COPY  src +%04X  dest %04X  dist %-6d count %d", n,
      r16(0x00) - 0x6F40, r16(0x03), d, r16(0x16)))
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, MEM)
end

-- the four control-word refill sites, so the bit accounting is observed rather
-- than inferred (this is what a Python twin keeps getting wrong)
for _, a in ipairs({ 0x91B6, 0x91D8, 0x91EA, 0x91FC }) do
  for _, bank in ipairs({ 0x000000, 0x800000, 0xC00000 }) do
    local addr = bank + a
    emu.addMemoryCallback(function()
      if not arm or n >= N then return end
      n = n + 1
      log(string.format("%3d REFILL @%04X  src +%04X  word %02X%02X", n, a,
        r16(0x00) - 0x6F40,
        emu.read(r8(0x02) * 0x10000 + r16(0x00) + 1, MEM),
        emu.read(r8(0x02) * 0x10000 + r16(0x00), MEM)))
    end, emu.callbackType.exec, addr, addr, emu.cpuType.snes, MEM)
  end
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = slowbeat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = slowbeat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = {}; return sf > 10 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() wr(0x1B40, CHAR); wr(0x1B80, DUMMY); return sf > 20 end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    wr(0x1B80, DUMMY)
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x1000) == CHAR and ram(0x1080) ~= 0 then return true end
    if sf > 900 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() return sf > 60 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_lztrace loaded")
