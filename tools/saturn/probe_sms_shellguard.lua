-- probe_sms_shellguard.lua — bug 3 measurement: what does the $EF-helper's
-- `lda $00,x` actually read at the gate where SHELL_GUARD would test the shell?
--
-- The maintainer's story lock is "only arm on Uranus/Neptune/Pluto shells"
-- (charID 6/7/8, the three story cannot select). Placed in the helper it
-- reportedly blocks EVERY shell, including 6/7/8 — unexplained. This probe
-- hooks the helper at the exact instruction the guard would precede
-- (`lda $01,x`, helper+0x33, right after `rep #$10 / ldx $88`) and logs the
-- registers and what `$00,x` / `$01,x` resolve to, so the id is measured
-- rather than assumed.
--
-- Helper layout it depends on (v0.14.x, SHELL_GUARD off):
--   +0x00 E2 30  sep #$30 | +0x2F C2 10 rep #$10 | +0x31 A6 88 ldx $88
--   +0x33 B5 01  lda $01,x   <- the guard would sit here
--   +0x40 95 00  sta $00,x   (the transform)
--
-- Navigation follows probe_sms_lrmodes.lua (MODE vscpu = menu row 0, the flow
-- that is known to transform; practice = row 4).
--
-- Result (v0.14.5): the guard always read the right byte — D=0, X=$1000/$1080,
-- $00,x = the true shell (06 for a Uranus shell, 04 for a Jupiter one). The
-- "blocks every shell" report came from a HARNESS fault: the older flows poke
-- $1B40 once and then mash A/Start through a second selection screen that reuses
-- that cursor, so the fight loaded charID 1. This probe re-pokes for the whole
-- load; always check the FINAL line's p1 against the shell you asked for.
--
-- Acceptance matrix (SHELL_GUARD on; XFORM_OFF=0x4A because the guard shifts the
-- transform 10 bytes later):
--   practice 6/7/8 -> LR PASS   practice 1/4/9 -> LR FAIL, xforms=0
--   vscpu 6 -> LR PASS          vscpu 1 -> LR FAIL
--   story -> LR FAIL (and still LR FAIL on a STORY_GUARD=0 build, where the
--            latch DOES arm — that is the proof the shell test alone locks story)
--
--   MODE=practice SHELL=6 XFORM_OFF=0x4A ROM=<saturn build> \
--     tools/run.sh tools/saturn/probe_sms_shellguard.lua 500
-- envs: MODE=vscpu|practice|story  SHELL  DUMMY  STORY_SHELL=1 (force the story
--       cursor, adversarial only)  TAG  HELPER  GATE_OFF  XFORM_OFF
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr

local MODE = os.getenv("MODE") or "vscpu"
-- NOTE: $SHELL is a standard shell variable (/bin/zsh), so a bare run inherits a
-- non-numeric value — prefer SHELL_ID, and fall back to 6 rather than to nil
-- (a nil here made wr() throw and the script die with no verdict at all).
local function shellid(default)
  return tonumber(os.getenv("SHELL_ID") or "") or tonumber(os.getenv("SHELL") or "") or default
end
local SHELL = shellid(6)                               -- P1 shell char (6=Uranus)
local DUMMY = tonumber(os.getenv("DUMMY") or "") or 4  -- practice dummy char
local HELPER = tonumber(os.getenv("HELPER") or "0xF7DB70")
-- offsets into the helper; defaults are the SHELL_GUARD-off layout. With the
-- guard built in, the shell test sits at +0x33 and the transform moves to +0x4A.
local GATE = HELPER + tonumber(os.getenv("GATE_OFF") or "0x33")
local XFORM = HELPER + tonumber(os.getenv("XFORM_OFF") or "0x40")

local TAG = os.getenv("TAG") or (MODE .. "_" .. SHELL)
local LOG = assert(io.open(ENV.TRACE .. "saturn/shellguard_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local frames, step, sf = 0, 1, 0
local pulse = {}
local hold = false
local hits, xforms = 0, 0
local became_at = nil

local function beat(on) return (frames % 7) < 3 and on or {} end
-- byte on the CPU bus in bank 0 (mirrors WRAM $7E:0000-1FFF below $2000)
local function bus(a) return emu.read(a & 0xFFFF, emu.memType.snesMemory) end
local function st()
  local ok, s = pcall(emu.getState)
  return ok and s or {}
end
local function reg(s, ...)
  for _, k in ipairs({ ... }) do if s[k] then return s[k] end end
  return nil
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if p == 0 and hold then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

-- menu rows: vscpu = 0, story = 1, practice = 4.
-- The story flow needs its own step list: after P1 confirms, the screen wants a
-- SECOND confirm on pad 2 and then Start on both pads (the practice-style A/Start
-- mash on pad 1 alone stalls there forever — measured).
local STEPS_STORY = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function()
    -- STORY_SHELL=1 forces the cursor (a direct poke bypasses the nav table's
    -- story roster restriction — used only to prove the guard, never a real flow)
    if os.getenv("STORY_SHELL") == "1" then wr(0x1B40, SHELL) end
    hold = true; return sf > 20
  end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = beat({ a = true }); return sf > 60 end,
  function() return sf > 240 end,
  function() pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
             return (ram(0x1000) ~= 0 and ram(0x1080) ~= 0) or sf > 600 end,
  function() pulse[0] = {}; pulse[1] = {}; return sf > 400 end,
}

local STEPS_VS = {
  function() return frames >= 900 end,
  function()
    if MODE == "vscpu" then return sf > 30 end
    pulse[0] = beat({ down = true }); return ram(0x1B10) == 1
  end,
  function()
    if MODE ~= "practice" then return true end
    pulse[0] = beat({ right = true }); return ram(0x1B10) == 4
  end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() wr(0x1B40, SHELL); if MODE == "practice" then wr(0x1B80, DUMMY) end
             hold = true; return sf > 20 end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()  -- mash A/Start until actually IN MATCH ($0070==4)
    -- keep poking the cursor: in vscpu the A/Start mash walks through a SECOND
    -- selection screen that reuses $1B40, so a one-shot poke at step 5 is
    -- silently undone and the fight loads charID 1 (this is what made the
    -- 2026-08-03 "SHELL_GUARD blocks 6/7/8" reading wrong)
    wr(0x1B40, SHELL)
    if MODE == "practice" then wr(0x1B80, DUMMY) end
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return sf > 400 end,
}

local STEPS = (MODE == "story") and STEPS_STORY or STEPS_VS

emu.addMemoryCallback(function()
  if hits >= 40 then return end
  local s = st()
  local x = reg(s, "cpu.x", "snes.cpu.x") or -1
  local d = reg(s, "cpu.d", "snes.cpu.d") or -1
  local a = reg(s, "cpu.a", "snes.cpu.a") or -1
  local ea = (d + x) & 0xFFFF
  hits = hits + 1
  log(string.format(
    "f=%d GATE x=%04X d=%04X a=%04X ea=%04X [$00,x]=%02X [$01,x]=%02X | " ..
    "1000:%02X/%02X 1080:%02X/%02X $88=%04X flag=%02X/%02X latch=%02X/%02X",
    frames, x, d, a, ea, bus(ea), bus(ea + 1),
    ram(0x1000), ram(0x1001), ram(0x1080), ram(0x1081),
    ram(0x88) + 256 * ram(0x89),
    emu.read(0x7FF100, emu.memType.snesMemory) or 0,
    emu.read(0x7FF101, emu.memType.snesMemory) or 0,
    emu.read(0x7FF102, emu.memType.snesMemory) or 0,
    emu.read(0x7FF103, emu.memType.snesMemory) or 0))
end, emu.callbackType.exec, GATE, GATE, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function()
  xforms = xforms + 1
  if xforms > 4 then return end
  local s = st()
  local x = reg(s, "cpu.x", "snes.cpu.x") or -1
  local d = reg(s, "cpu.d", "snes.cpu.d") or -1
  log(string.format("f=%d XFORM x=%04X d=%04X -> writes $%04X",
    frames, x, d, (d + x) & 0xFFFF))
end, emu.callbackType.exec, XFORM, XFORM, emu.cpuType.snes, emu.memType.snesMemory)

-- who writes the per-player select flags / latches, and what the pads read there
local fw = 0
for a = 0x7FF100, 0x7FF103 do
  emu.addMemoryCallback(function(addr, value)
    if fw >= 24 then return end
    local s = st()
    local pc = reg(s, "cpu.pc") or -1
    local k = reg(s, "cpu.k") or -1
    fw = fw + 1
    log(string.format("f=%d FLAGW %06X <= %02X @ %02X:%04X  JOY1=%02X/%02X JOY2=%02X/%02X",
      frames, addr, value or -1, k, pc,
      emu.read(0x004218, emu.memType.snesMemory) or 0,
      emu.read(0x004219, emu.memType.snesMemory) or 0,
      emu.read(0x00421A, emu.memType.snesMemory) or 0,
      emu.read(0x00421B, emu.memType.snesMemory) or 0))
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if not became_at and ram(0x1000) == 0x1C then
    became_at = frames
    log(string.format("f=%d BECAME SATURN", frames))
  end
  local fn = STEPS[step]
  if fn and fn() then
    log(string.format("f=%d step %d done  $8D=%02X $70=%02X 1B40=%02X 1000=%02X flag=%02X latch=%02X",
      frames, step, ram(0x8D), ram(0x70), ram(0x1B40), ram(0x1000),
      emu.read(0x7FF100, emu.memType.snesMemory) or 0,
      emu.read(0x7FF102, emu.memType.snesMemory) or 0))
    step = step + 1; sf = 0; pulse = {}
  end
  if not STEPS[step] then
    log(string.format("FINAL: p1=%02X p2=%02X %s  gate_hits=%d xforms=%d",
      ram(0x1000), ram(0x1080),
      ram(0x1000) == 0x1C and "LR PASS" or "LR FAIL", hits, xforms))
    emu.stop(0)
  end
  if frames > 6000 then
    log(string.format("TIMEOUT step %d gate_hits=%d xforms=%d", step, hits, xforms))
    emu.stop(1)
  end
end, emu.eventType.endFrame)

print("probe_sms_shellguard loaded: " .. MODE .. " shell " .. SHELL)
