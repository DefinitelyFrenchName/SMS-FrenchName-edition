-- probe_saturn_fxsheet.lua — assert that Saturn's effect sheet reaches VRAM in
-- full, whatever shell she is wearing.
--
-- The bug this exists to catch (fixed v0.14.11): the build overrides the
-- $7F:0000 staging buffer with her 0x1040-byte effect sheet, but the DMA that
-- follows was sized from the SHELL character's own sheet. Uranus $11C0 and
-- Pluto $10C0 are large enough; NEPTUNE is $0E60, so 15 tiles ($113-$121) of
-- her sheet never arrived and kept whatever the previous match left in VRAM.
-- Her 214P projectile draws 7 of its 12 sprites from that range -- the field
-- report "two disconnected blue pieces instead of one shape".
--
-- The assertion is CROSS-SHELL INVARIANCE rather than a hardcoded checksum: her
-- sheet is the same data on every shell, so the checksum over VRAM $6A00 must
-- match across shells 6/7/8. That survives any future change to her art, and it
-- is the exact property that was broken -- the old gate passed on the broken
-- build because nothing ever compared one shell against another.
--
--   SHELL_ID=7 ROM=<build> tools/run.sh tools/saturn/probe_saturn_fxsheet.lua 500
-- Output: traces/saturn/fxsheet_<SHELL_ID>.txt, last line "FXSHEET ... sum=$XXXXXXXX"
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
-- PLAYER=2 measures the P2 side instead: a different effects transfer (VRAM
-- $7300) reached through the stub's other flag block. It shares the copy path,
-- so the fix applies by construction -- which is exactly the kind of claim this
-- project has been burned by, hence the option to actually measure it.
local PLAYER = num("PLAYER", 1)
local TAG = os.getenv("TAG") or (PLAYER == 2 and ("p2_" .. SHELL) or tostring(SHELL))
local LOG = assert(io.open(ENV.TRACE .. "saturn/fxsheet_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local VRAM = emu.memType.snesVideoRam
local FX_BYTE = (PLAYER == 2 and 0x7300 or 0x6A00) * 2   -- her effect sheet
local FX_LEN = 0x1040
local STRUCT = PLAYER == 2 and 0x1080 or 0x1000
local frames, step, sf = 0, 1, 0
local pulse, hold, done = {}, false, false
local function beat(on) return (frames % 7) < 3 and on or {} end
-- the shell goes on whichever player is being armed; the other stays a vanilla
-- control (the shell guard only allows 6/7/8, so the dummy must wear it too)
local function setchars()
  if PLAYER == 2 then wr(0x1B40, 4); wr(0x1B80, SHELL)
  else wr(0x1B40, SHELL); wr(0x1B80, 4) end
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and p == (PLAYER - 1) then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local function measure()
  done = true
  local sum, blank, nonblank = 0, 0, 0
  for t = 0, FX_LEN / 32 - 1 do
    local any = false
    for b = 0, 31 do
      local v = emu.read(FX_BYTE + t * 32 + b, VRAM) or 0
      if v ~= 0 then any = true end
      sum = (sum * 33 + v) % 0x100000000        -- order-sensitive, cheap
    end
    if any then nonblank = nonblank + 1 else blank = blank + 1 end
  end
  log(string.format("charID=%02X (expect 1C = Saturn)", ram(STRUCT)))
  log(string.format("FXSHEET shell=%d p%d tiles=%d nonblank=%d blank=%d sum=$%08X",
    SHELL, PLAYER, FX_LEN / 32, nonblank, blank, sum))
end

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
    if sf > 1500 then log("MATCH-LOAD-FAIL"); LOG:close(); emu.stop(1) end
    return false
  end,
  function()
    pulse[0] = {}
    -- Assert the precondition before believing the verdict: if she never
    -- transformed, the sheet in VRAM is the shell's and the sums would agree
    -- for the wrong reason.
    if sf > 90 then
      if ram(STRUCT) ~= 0x1C then log("NOT-SATURN charID=" .. ram(STRUCT)); LOG:close(); emu.stop(1) end
      measure(); return true
    end
    return false
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then LOG:close(); emu.stop(done and 0 or 1) end
  if frames > 6000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
