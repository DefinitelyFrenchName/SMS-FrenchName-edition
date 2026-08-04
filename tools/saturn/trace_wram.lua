-- trace_wram.lua — snapshot all 128 KB of WRAM at checkpoints through a scripted
-- session, plus log every write to a declared watch set with its writer PC.
--
-- Companion to trace_dsp.lua, aimed at the OTHER half of the risk. The DSP
-- differential bounds what a DATA change does; it is structurally blind to the
-- 65816 HOOK that applies that data. A load-time hook's realistic failure modes
-- are not audio at all:
--
--   stray `sta long` to $7F:F1xx        -> WRAM, global
--   direct page $10/$11 left clobbered  -> WRAM $0010/$0011, global
--   stack imbalance / wrong M,X width   -> caller misparses itself, global
--   APU handshake never acked           -> hard lockup, global
--
-- The loud ones (crash, freeze) already detonate in the character-load path and
-- are caught by verify_saturn.sh and by every autopilot's MATCH-LOAD-FAIL. The
-- QUIET one — a stray write or state residue read much later — is what this is
-- for, and nothing in the toolchain covered it before.
--
-- Two mechanisms, deliberately:
--   * checkpoint SNAPSHOTS of the whole 128 KB are ground truth. They see any
--     change however it arrived, including DMA, which a CPU write callback would
--     miss entirely.
--   * the WATCH log gives byte-level attribution (which PC wrote it, when) for
--     the addresses the design actually declares.
--
-- The assertion that matters most is the cheapest to state: a VANILLA session
-- (SATURN=0) on a patched build must diff to EMPTY against the same session on
-- the unpatched build. That is "the hook does not fire when it should not" and
-- "the restore path leaves no residue", neither of which play-testing can show.
--
--   TAG=a SATURN=0 ROM=<rom> tools/run.sh tools/saturn/trace_wram.lua 900
-- envs:
--   TAG          -> traces/saturn/wram_<TAG>.{bin,idx,watch}
--   SHELL_ID     character in P1's slot (default 6)
--   SATURN       1 (default) hold L+R at confirm; 0 = plain character
--   SNAP_EVERY   frames between snapshots (default 100)
--   FRAMES       post-sync frames (default 900)
--   POKE_LIST    her four transposes, as trace_dsp.lua (emulates the retune)
--   POKE_WRAM    "hexoffset:hexvalue" — inject a known WRAM change; the
--                SENSITIVITY self-test, so an empty diff is never mistaken for
--                a working differ
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr

local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local TAG = os.getenv("TAG") or "a"
local SHELL = num("SHELL_ID", 6)
local SATURN = os.getenv("SATURN") ~= "0"
local SNAP_EVERY = num("SNAP_EVERY", 100)
local FRAMES = num("FRAMES", 900)
local POKE_LIST = os.getenv("POKE_LIST")
local POKE_WRAM = os.getenv("POKE_WRAM")

local WRAM = emu.memType.snesWorkRam        -- offsets $00000-$1FFFF = $7E/$7F
local WSIZE = 0x20000
local SPC = emu.memType.spcRam

local BIN = assert(io.open(ENV.TRACE .. "saturn/wram_" .. TAG .. ".bin", "wb"))
local IDX = assert(io.open(ENV.TRACE .. "saturn/wram_" .. TAG .. ".idx", "w"))
local WCH = assert(io.open(ENV.TRACE .. "saturn/wram_" .. TAG .. ".watch", "w"))

-- Watch set: the project's own Saturn state block only, by default.
--
-- The low direct page was in here first and had to come out: $0000-$001F is the
-- engine's hottest scratch, 460k writes in 900 frames, which is 9 MB of noise
-- and a getState() per write. The DP $10/$11 question that motivated watching it
-- is about RESIDUE at one moment, not about traffic — and residue is exactly
-- what the checkpoint snapshots already catch. Watch hot addresses only when
-- chasing a specific writer, via WATCH.
--
--   WATCH="7E0010-7E0011,7FF100-7FF11F"   (SNES addresses, comma separated)
local WATCH = {}
do
  local spec = os.getenv("WATCH") or "7FF100-7FF11F"
  for part in spec:gmatch("[^,]+") do
    local lo, hi = part:match("^%s*(%x+)%-(%x+)%s*$")
    if not lo then lo = part:match("^%s*(%x+)%s*$"); hi = lo end
    assert(lo, "WATCH wants SNES hex addresses like 7FF100-7FF11F")
    WATCH[#WATCH + 1] = { tonumber(lo, 16) - 0x7E0000, tonumber(hi, 16) - 0x7E0000 }
  end
end

local TR = { 0x1C91, 0x1CAB, 0x1CB6, 0x1CC1 }
local TR_VANILLA = { 0xFE, 0xFE, 0xFF, 0xFD }

local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local synced, pf = false, -1
local snaps, watchn = 0, 0

local function beat(on) return (frames % 7) < 3 and on or {} end
local function setchars() wr(0x1B40, SHELL); wr(0x1B80, 4) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and SATURN and p == 0 then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

for _, w in ipairs(WATCH) do
  emu.addMemoryCallback(function(addr, value)
    -- ALWAYS on, not just after sync. The hook this exists to watch runs during
    -- CHARACTER LOAD, which is before the match goes live — gating the watch on
    -- `synced` (the first version did) misses the only moment that matters and
    -- reports a reassuring zero. Frames are absolute for that reason; the idx
    -- header records the sync frame so post-sync events can still be placed.
    local ok, st = pcall(emu.getState)
    local pc = -1
    if ok and st then pc = ((st["cpu.k"] or 0) << 16) | (st["cpu.pc"] or 0) end
    watchn = watchn + 1
    WCH:write(string.format("%d %05X %02X %06X\n", frames, addr or 0, value or 0, pc))
  end, emu.callbackType.write, w[1], w[2], emu.cpuType.snes, WRAM)
end

-- 128 KB a byte at a time is the only read the API offers; batch the string
-- building so the cost is 512 string.char calls per snapshot rather than 131072
-- concatenations.
local function snapshot()
  local chunk, out = {}, {}
  for base = 0, WSIZE - 1, 256 do
    for i = 0, 255 do chunk[i + 1] = emu.read(base + i, WRAM) or 0 end
    out[#out + 1] = string.char(table.unpack(chunk))
  end
  BIN:write(table.concat(out))
  IDX:write(string.format("snap %d %d\n", pf, snaps))
  snaps = snaps + 1
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
    if sf > 1500 then IDX:write("MATCH-LOAD-FAIL\n"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 150 end,
  function()
    if sf == 1 then
      synced = true; pf = 0
      IDX:write(string.format("# trace_wram TAG=%s shell=%d saturn=%d frames=%d every=%d\n",
        TAG, SHELL, SATURN and 1 or 0, FRAMES, SNAP_EVERY))
      IDX:write(string.format("# sync at abs frame %d, p1=%02X dummy=%02X\n",
        frames, ram(0x1000), ram(0x1080)))
      if POKE_LIST then
        local pl = {}
        for h in POKE_LIST:gmatch("[^,]+") do pl[#pl + 1] = tonumber(h, 16) end
        assert(#pl == #TR, "POKE_LIST needs " .. #TR .. " values")
        for i, a in ipairs(TR) do
          local got = emu.read(a, SPC) or 0
          if got ~= TR_VANILLA[i] then
            IDX:write(string.format("PRECONDITION-FAIL $%04X=$%02X expect $%02X\n",
              a, got, TR_VANILLA[i]))
            emu.stop(1); return true
          end
        end
        for i, a in ipairs(TR) do emu.write(a, pl[i], SPC) end
        IDX:write("# poked transpose " .. POKE_LIST .. "\n")
      end
      if POKE_WRAM then
        local o, v = POKE_WRAM:match("^(%x+):(%x+)$")
        assert(o, "POKE_WRAM wants hexoffset:hexvalue")
        emu.write(tonumber(o, 16), tonumber(v, 16), WRAM)
        IDX:write(string.format("# poked WRAM $%05X <= $%02X\n",
          tonumber(o, 16), tonumber(v, 16)))
      end
    end
    -- identical fixed schedule to trace_dsp.lua, keyed on pf not on game state
    local m = pf % 60
    if m < 6 then pulse[0] = { down = true }
    elseif m < 12 then pulse[0] = { down = true, right = true }
    elseif m < 18 then pulse[0] = { right = true }
    elseif m < 22 then pulse[0] = { y = true }
    elseif m < 30 then pulse[0] = {}
    elseif m < 36 then pulse[0] = { down = true }
    elseif m < 42 then pulse[0] = { down = true, left = true }
    elseif m < 48 then pulse[0] = { left = true }
    elseif m < 52 then pulse[0] = { y = true }
    else pulse[0] = {} end
    return pf >= FRAMES
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if synced then
    if pf % SNAP_EVERY == 0 then snapshot() end
    pf = pf + 1
  end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    snapshot()                                   -- always end on a checkpoint
    IDX:write(string.format("# END snaps=%d watchwrites=%d frames=%d\n", snaps, watchn, pf))
    BIN:close(); IDX:close(); WCH:close()
    emu.stop(0)
  end
  if frames > 8000 then IDX:write("# TIMEOUT step " .. step .. "\n"); emu.stop(1) end
end, emu.eventType.endFrame)

print("trace_wram loaded: TAG=" .. TAG .. " shell=" .. SHELL ..
  (SATURN and " SATURN" or " vanilla"))
