-- probe_saturn_fxdma.lua — log the PARAMETERS of every VRAM DMA kicked through
-- $C0:92A4 during a round load, so the effects transfer's LENGTH can be read.
--
-- Why the length matters: the Saturn build overrides the $7F:0000 staging buffer
-- with her full 0x1040-byte effect sheet, but it does NOT touch the DMA that
-- follows -- and that DMA's length was computed from the SHELL character's own
-- (compressed) effect sheet. If a shell's sheet is smaller than hers, the tail
-- of her sheet is never transferred and the tiles at the end of her sheet are
-- whatever the previous match left in VRAM.
--
-- The DMA registers are write-only, so the parameters are read from DIRECT PAGE
-- at the kick site (the same technique probe_fontdma2.lua uses for the font
-- hunt). The D register is read from the CPU state rather than assumed.
--
--   SHELL_ID=7 TAG=n ROM=<build> tools/run.sh tools/saturn/probe_saturn_fxdma.lua 400
-- Output: traces/saturn/fxdma_<TAG>.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
local SATURN = os.getenv("SATURN") ~= "0"
local TAG = os.getenv("TAG") or "fxdma"
local LOG = assert(io.open(ENV.TRACE .. "saturn/fxdma_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print("FXDMA " .. s) end

local MEM = emu.memType.snesMemory
local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local function beat(on) return (frames % 7) < 3 and on or {} end
local function setchars() wr(0x1B40, SHELL); wr(0x1B80, 4) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and SATURN and p == 0 then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

-- $C0:92A4 = the generic VRAM-DMA kick the Saturn build already hooks
-- (DMA_KICK_OLD = ldy #$01 / sty $4300 / sty $420B).
-- The D register is NOT read from emu.getState(): that call is unreliable in
-- this build and, worse, it throws INSIDE the callback -- which silently kills
-- the hook and reports "0 DMA kicks", a broken probe wearing the costume of a
-- finding. Instead the direct page is located by CONTENT: the build's own stub
-- filters this site on `lda $30` == $6A00, so at the effects transfer some
-- direct-page word holds $6A00. Scan low WRAM for it and report every hit; the
-- offline pass picks the offset that is consistent across kicks.
local ndma, dumped = 0, 0
local function w16(a) return (emu.read(a, MEM) or 0) | ((emu.read(a + 1, MEM) or 0) << 8) end
emu.addMemoryCallback(function()
  -- D = $0000 and dp+$30/$32/$34/$36 = vram dest / length / src / src bank,
  -- established by content-scan on the effects transfer (which the build's own
  -- stub filters on `lda $30` == $6A00). Every kick is logged, so the resulting
  -- VRAM map can be checked for overlap before anyone extends a transfer.
  ndma = ndma + 1
  local vram, len, src, bank = w16(0x30), w16(0x32), w16(0x34), w16(0x36)
  local tag = ""
  if vram == 0x6A00 then tag = "   <== P1 EFFECTS"
  elseif vram == 0x7300 then tag = "   <== P2 EFFECTS" end
  log(string.format("f=%d kick#%-2d vram=$%04X len=$%04X (words $%04X..$%04X) src=$%02X:%04X%s",
    frames, ndma, vram, len, vram, vram + math.floor(len / 2), bank, src, tag))
end, emu.callbackType.exec, 0x8092A4, 0x8092A4, emu.cpuType.snes, MEM)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() setchars(); hold = true; return sf > 20 end,
  function() setchars(); pulse[0] = beat({ a = true })
             return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    setchars()
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return sf > 60 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("DONE dma_kicks=" .. ndma); LOG:close(); emu.stop(0) end
  if frames > 6000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
