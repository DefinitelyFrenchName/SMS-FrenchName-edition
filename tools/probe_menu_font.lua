-- probe_menu_font.lua — where does the MENU FONT come from?
--
-- Known: the font CHR is not raw in ROM and is not DMA'd from ROM. Logging every
-- VRAM DMA from boot shows it arriving in 0x40-byte chunks from a WRAM staging
-- buffer at $7E:3640+. So the chain is ROM -> (decompress) -> $7E:3640 -> VRAM,
-- and the open link is what fills that buffer.
--
-- This watches the buffer itself. A block move (MVN) is still a CPU write per
-- byte, so the callback fires and the CPU state names the source outright:
-- MVN takes the source bank in the operand, the source offset in X, the
-- destination in Y and the count in A.
--
-- usage: ROM=<rom> tools/run.sh tools/probe_menu_font.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local DIR = ENV.TRACE .. "menu/"
local LOG = assert(io.open(DIR .. "font_src.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local MEMT = emu.memType.snesMemory
local frames, n = 0, 0
local seen = {}

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)

-- $C0:91C9 is inside $C0:916B, the movelist/tilemap decompressor — so the font
-- is COMPRESSED with the codec sms_lz.py already handles. Log every call with
-- its source (DP $00-$02) and destination (DP $03/$04) to get the exact block.
local calls = 0
emu.addMemoryCallback(function()
  if calls > 400 then return end
  local function dd(a) return emu.read(a, MEMT) or 0 end
  if frames < 1100 then calls = calls + 1; return end
  calls = calls + 1
  local function d(a) return emu.read(a, MEMT) or 0 end
  log(string.format("f=%d DECOMP src=$%02X:%02X%02X dest=$%02X:%02X%02X",
    frames, d(0x02), d(0x01), d(0x00), d(0x05), d(0x04), d(0x03)))
end, emu.callbackType.exec, 0x8091A0, 0x8091A0, emu.cpuType.snes, MEMT)
-- NB: hooked at $C0:91A0, the decompressor's loop setup, NOT its documented
-- entry $C0:916B — the font path reaches it by another entry, so a hook on
-- $916B never fires. At $91A0 the source pointer is still at the start.

-- both views of the same WRAM: the writer may use $7E or the bank-$00 mirror
for _, a in ipairs({ 0x7E3640, 0x003640, 0x7E3644, 0x003644 }) do
  emu.addMemoryCallback(function(addr, value)
    if n > 24 then return end
    local ok, st = pcall(emu.getState)
    local pc = string.format("%02X:%04X", ok and (st["cpu.k"] or 0) or 0,
                             ok and (st["cpu.pc"] or 0) or 0)
    if seen[pc] then return end
    seen[pc] = true; n = n + 1
    log(string.format("f=%d $%06X <= %02X @%s  A=%04X X=%04X Y=%04X DB=%02X",
      frames, addr, value or 0, pc,
      ok and (st["cpu.a"] or 0) or 0, ok and (st["cpu.x"] or 0) or 0,
      ok and (st["cpu.y"] or 0) or 0, ok and (st["cpu.db"] or 0) or 0))
  end, emu.callbackType.write, a, a, emu.cpuType.snes, MEMT)
end

emu.addEventCallback(function()
  frames = frames + 1
  pulse[0] = (frames % 90 < 3) and { start = true } or {}
  if frames == 1300 then
    -- and keep the buffer itself, to prove it is the font
    local b = {}
    for a = 0x7E3000, 0x7E3FFF do b[#b + 1] = string.char(emu.read(a, MEMT) or 0) end
    local f = io.open(DIR .. "font_wram.bin", "wb")
    if not f then print("probe_menu_font.lua: cannot open " .. (DIR .. "font_wram.bin")) emu.stop(1) return end
    f:write(table.concat(b)); f:close()
  end
  if frames > 1320 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)

print("probe_menu_font loaded")
