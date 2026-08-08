-- probe_sms_vs2p.lua — field bug 2: in 2P VS the shell is NOT replaced, although
-- her sfx play, the confirm sfx is hers, and the palette is hers/altered.
--
-- RESOLVED (v0.14.6): the transform never ran at all. The story guard's
-- `$8D == 1` test is **2P VS**, not story (story is 00 — probe_sms_menurows.lua),
-- so the DMA stub force-cleared the latch and the helper was never reached; the
-- sfx still played because the sound remap keys off the FLAG, which the
-- char-select confirm hook sets earlier and independently. Kept because the
-- +0x00 writer trace below (with PC, on both mirrors) is the tool for any future
-- "the transform is being undone" question. For plain acceptance runs prefer
-- probe_sms_shellguard.lua MODE=vs, which shares this two-pad flow.
--
-- The original hypothesis, for the record: the transform RUNS and is then UNDONE — the
-- palette copy lives inside the helper's transform path (EE_PALCOPY, right after
-- `sta $00,x`), the sound remap keys off the latch, but the proc dispatch and the
-- sprite both read `+0x00`. So this probe drives a REAL two-pad VS — P1 and P2
-- each confirm their own cursor with their own pad, which no existing probe does
-- (they drive pad 1 only and poke the second cursor) — and watches every write to
-- either player's `+0x00` with its writer PC, on BOTH mirrors ($00:10xx direct
-- page and $7E:10xx), alongside the helper's gate and transform.
--
--   SHELL_ID=6 OPP=7 ROW=1 ROM=<saturn build> tools/run.sh tools/saturn/probe_sms_vs2p.lua 500
-- envs: ROW (menu row = $8D; 0=story 1=2P VS 2=vs-COM 4=practice), SHELL_ID, OPP,
--       BOTH=1 (hold L+R on both pads), HELPER, GATE_OFF, XFORM_OFF, TAG
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr

-- $SHELL is a standard shell variable, so a bare run inherits /bin/zsh
local function num(name, default)
  return tonumber(os.getenv(name) or "") or default
end
local ROW = num("ROW", 1)   -- 1 = 2P VS (0 = story, 2 = vs-COM, 4 = practice)
local SHELL = num("SHELL_ID", 6) or num("SHELL", 6)
local OPP = num("OPP", 7)   -- P2 must also be 6/7/8 to transform (shell guard)
local BOTH = os.getenv("BOTH") == "1"
local HELPER = num("HELPER", 0xF7DB70)
local GATE = HELPER + num("GATE_OFF", 0x33)
local XFORM = HELPER + num("XFORM_OFF", 0x4A)

local TAG = os.getenv("TAG") or ("vs2p_" .. SHELL)
local LOG = assert(io.open(ENV.TRACE .. "saturn/" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local frames, step, sf = 0, 1, 0
local pulse = {}
local hold = false
local gates, xforms, idw = 0, 0, 0

local function beat(on) return (frames % 7) < 3 and on or {} end
local function st()
  local ok, s = pcall(emu.getState)
  return ok and s or {}
end
local function reg(s, ...)
  for _, k in ipairs({ ... }) do if s[k] then return s[k] end end
  return nil
end
local function pcstr()
  local s = st()
  return string.format("%02X:%04X", reg(s, "cpu.k") or 0, reg(s, "cpu.pc") or 0)
end
local function latch(n)
  return emu.read(0x7FF100 + n, emu.memType.snesMemory) or 0
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and (p == 0 or BOTH) then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

-- TWO PADS: P1 confirms its own cursor, P2 confirms its own. The cursors are
-- poked for the whole load — a one-shot poke is undone by the second selection
-- screen that reuses $1B40 (see docs/project/saturn/BUILDS.md v0.14.5).
local function poke()
  wr(0x1B40, SHELL); wr(0x1B80, OPP)
end

local STEPS = {
  function() return frames >= 900 end,
  function()
    if ROW == 0 then return sf > 30 end
    pulse[0] = beat({ down = true }); return ram(0x1B10) == ROW
  end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function() poke(); hold = true; return sf > 20 end,
  function() poke(); pulse[0] = beat({ a = true })
             return ram(0x1B42) == 1 or sf > 120 end,
  function() poke(); pulse[0] = {}; return sf > 20 end,
  function() poke(); pulse[1] = beat({ a = true })       -- P2's OWN pad confirms
             return ram(0x1B82) == 1 or sf > 120 end,
  function() poke(); pulse[0] = {}; pulse[1] = {}; return sf > 30 end,
  function()  -- both pads mash Start through the config screen into the match
    poke()
    local m = frames % 14
    local b = (m < 3) and { start = true } or ((m >= 7 and m < 10) and { a = true } or {})
    pulse[0] = b; pulse[1] = b
    if ram(0x70) == 4 and ram(0x1000) ~= 0 and ram(0x1080) ~= 0 then return true end
    if sf > 2000 then
      log(string.format("MATCH-LOAD-FAIL $8D=%02X $70=%02X 1000=%02X 1080=%02X 1B42=%02X 1B82=%02X",
        ram(0x8D), ram(0x70), ram(0x1000), ram(0x1080), ram(0x1B42), ram(0x1B82)))
      emu.stop(1)
    end
    return false
  end,
  function() pulse[0] = {}; pulse[1] = {}; return sf > 400 end,
}

-- every write to either player's +0x00, on BOTH mirrors (direct-page stores land
-- at $00:10xx and do NOT fire a $7E:10xx callback)
for _, a in ipairs({ 0x001000, 0x001080, 0x7E1000, 0x7E1080 }) do
  emu.addMemoryCallback(function(addr, value)
    if idw >= 60 or not hold then return end
    idw = idw + 1
    log(string.format("f=%d IDW %06X <= %02X @ %s   (1000=%02X 1080=%02X latch=%02X/%02X)",
      frames, addr, value or -1, pcstr(), ram(0x1000), ram(0x1080), latch(2), latch(3)))
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addMemoryCallback(function()
  gates = gates + 1
  if gates > 12 then return end
  local s = st()
  local x = reg(s, "cpu.x") or -1
  local d = reg(s, "cpu.d") or -1
  log(string.format("f=%d GATE x=%04X d=%04X [$00,x]=%02X [$01,x]=%02X  latch=%02X/%02X",
    frames, x, d, emu.read((d + x) & 0xFFFF, emu.memType.snesMemory) or 0,
    emu.read((d + x + 1) & 0xFFFF, emu.memType.snesMemory) or 0, latch(2), latch(3)))
end, emu.callbackType.exec, GATE, GATE, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function()
  xforms = xforms + 1
  if xforms > 6 then return end
  local s = st()
  local x = reg(s, "cpu.x") or -1
  local d = reg(s, "cpu.d") or -1
  log(string.format("f=%d XFORM -> $%04X", frames, (d + x) & 0xFFFF))
end, emu.callbackType.exec, XFORM, XFORM, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if hold and frames % 30 == 0 then
    log(string.format("  f=%d $8D=%02X $70=%02X 1000=%02X/%02X 1080=%02X/%02X flag=%02X/%02X latch=%02X/%02X",
      frames, ram(0x8D), ram(0x70), ram(0x1000), ram(0x1001), ram(0x1080), ram(0x1081),
      latch(0), latch(1), latch(2), latch(3)))
  end
  local fn = STEPS[step]
  if fn and fn() then
    log(string.format("f=%d step %d done  $8D=%02X $70=%02X 1B40=%02X/%02X 1B80=%02X/%02X",
      frames, step, ram(0x8D), ram(0x70), ram(0x1B40), ram(0x1B42), ram(0x1B80), ram(0x1B82)))
    step = step + 1; sf = 0; pulse = {}
  end
  if not STEPS[step] then
    log(string.format("FINAL: $8D=%02X p1=%02X p2=%02X  %s  gates=%d xforms=%d",
      ram(0x8D), ram(0x1000), ram(0x1080),
      ram(0x1000) == 0x1C and "P1 IS SATURN" or "P1 NOT SATURN", gates, xforms))
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print(string.format("probe_sms_vs2p loaded: row %d shell %d vs %d", ROW, SHELL, OPP))
