-- probe_sms_mlppu.lua — read the PPU's real layer configuration while the
-- movelist is on screen, so the font's CHR window is measured rather than
-- guessed.
--
-- Inferring it from tile codes plus a VRAM dump did not converge: the roman
-- letters resolve cleanly at one base while the $1xx katakana codes do not,
-- which means the base assumption was wrong. The emulator knows the answer.
--
-- usage: CHAR=6 ROM=<rom> tools/run.sh tools/saturn/probe_sms_mlppu.lua 400
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "6")
local DUMMY = tonumber(os.getenv("DUMMY") or "4")
local TAG = os.getenv("TAG") or ("ppu" .. (os.getenv("CHAR") or "6"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/mlppu_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local VRAM = emu.memType.snesVideoRam

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end
local function slowbeat(on) return (frames % 20) < 4 and on or {} end

-- $210B/$210C are write-only, so shadow them as the game sets them
local nba = { [0x210B] = -1, [0x210C] = -1, [0x2105] = -1 }
for reg, _ in pairs(nba) do
  for _, b in ipairs({ reg, 0x800000 + reg }) do
    emu.addMemoryCallback(function(_, v) nba[reg] = v or 0 end,
      emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
  end
end
-- and the BG tilemap base registers, to confirm which layer the list is on
local sc = {}
for reg = 0x2107, 0x210A do
  for _, b in ipairs({ reg, 0x800000 + reg }) do
    emu.addMemoryCallback(function(_, v) sc[reg] = v or 0 end,
      emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
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
  function() pulse[0] = {}; return sf > 120 and ram(0x1001) == 0 end,
  function()
    if sf >= 5 and sf <= 8 then pulse[0] = { start = true } else pulse[0] = {} end
    return sf > 120
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("=== movelist open ($01FA=$%02X), P1 char %d ===",
      ram(0x01FA), ram(0x1000)))
    log(string.format("  $2105 BGMODE   = $%02X  (mode %d)", nba[0x2105], nba[0x2105] % 8))
    log(string.format("  $210B BG12NBA  = $%02X  -> BG1 chr $%04X, BG2 chr $%04X",
      nba[0x210B], (nba[0x210B] % 16) * 0x1000, (nba[0x210B] // 16) * 0x1000))
    log(string.format("  $210C BG34NBA  = $%02X  -> BG3 chr $%04X, BG4 chr $%04X",
      nba[0x210C], (nba[0x210C] % 16) * 0x1000, (nba[0x210C] // 16) * 0x1000))
    for reg = 0x2107, 0x210A do
      local v = sc[reg] or 0
      log(string.format("  $%04X BG%dSC    = $%02X  -> tilemap word $%04X, size %d",
        reg, reg - 0x2106, v, (v // 4) * 0x400, v % 4))
    end
    log("  (CHR word address * 2 = the byte offset in a VRAM dump)")
    local f = assert(io.open(ENV.TRACE .. "saturn/vram_" .. TAG .. ".bin", "wb"))
    local t = {}
    for a = 0, 0xFFFF do t[#t + 1] = string.char(emu.read(a, VRAM)) end
    f:write(table.concat(t)); f:close()
    log("  VRAM dumped")
    log("done"); emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_mlppu loaded")
