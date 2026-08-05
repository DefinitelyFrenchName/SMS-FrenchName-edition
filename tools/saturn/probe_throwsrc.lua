-- probe_throwsrc.lua — WHO decides which ground throw comes out?
--
-- probe_throwmap.lua reproduced both field bugs (HK gives the punch grab, and
-- that grab's 6/4 directions are inverted). This finds the code responsible
-- instead of inferring it from data that merely looks odd: it watches the
-- thrower's act byte and the move-request register and records the PC of every
-- write, so the answer is an address, not a hypothesis.
--
-- Reading the PC matters most for telling apart the two candidate homes:
--   * bank $C0/$C1        — shared engine code, so the fault is in HER DATA;
--   * her $C1 COPY / $EF-graft banks — her ported Super S proc, so it is CODE.
-- (The build grafts a full copy of $C1; a hook applied to $C1 alone would miss
-- her path entirely — the trap that hid the throw corruption for four sessions.)
--
--   SATURN=1 SHELL_ID=6 INPUT=6hk TAG=src_6hk ROM=<build> \
--     tools/run.sh tools/saturn/probe_throwsrc.lua 900
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
local P1CHAR = num("P1CHAR", 6)
local P2CHAR = num("P2CHAR", 4)
local SATURN = os.getenv("SATURN") == "1"
local INPUT = (os.getenv("INPUT") or "6hk"):lower()
local TAG = os.getenv("TAG") or ("src_" .. INPUT)
local LOG = assert(io.open(ENV.TRACE .. "saturn/throwsrc_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local P1, P2 = 0x1000, 0x1080
local function posx(b) return ram(b + 0x21) | (ram(b + 0x22) << 8) end

local BTN = { lp = "y", lk = "b", hp = "x", hk = "a" }
local dir, btn = INPUT:match("^([64]?)(%a+)$")
if not BTN[btn] then error("bad INPUT " .. INPUT) end
local function press()
  local t = {}; t[BTN[btn]] = true
  if dir == "6" then t.right = true elseif dir == "4" then t.left = true end
  return t
end

local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local armed = false
local function beat(on) return (frames % 7) < 3 and on or {} end
local function poke() wr(0x1B40, SATURN and SHELL or P1CHAR); wr(0x1B80, P2CHAR) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and p == 0 and SATURN then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

-- Increment BEFORE the call that can throw: emu.getState() raises inside a
-- memory callback in this build, and a dead hook would otherwise report "no
-- writes" — indistinguishable from "the game never wrote it".
local nwrite = 0
local hits = {}
local function st() local ok, s = pcall(emu.getState); return ok and s or nil end
local function watch(label, addr)
  emu.addMemoryCallback(function(_, v)
    if not armed then return end
    nwrite = nwrite + 1
    local s = st(); if not s then return end
    local pc = ((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)
    local k = string.format("%s <- $%02X  from PC $%06X", label, v or 0, pc)
    hits[k] = (hits[k] or 0) + 1
  end, emu.callbackType.write, addr, addr, emu.cpuType.snes, emu.memType.snesWorkRam)
end
-- The act VALUE is chosen by whoever calls the generic act-setter, so the write
-- site alone ($F7:022C) names the setter, not the decision. Hook the setter's
-- entry and read the return address off the stack: that is the deciding code.
local ACTSET = tonumber(os.getenv("ACTSET") or "0xF70226")
emu.addMemoryCallback(function()
  if not armed then return end
  nwrite = nwrite + 1
  local s = st(); if not s then return end
  local sp = s["cpu.sp"] or 0
  local lo = emu.read(sp + 1, emu.memType.snesMemory) or 0
  local hi = emu.read(sp + 2, emu.memType.snesMemory) or 0
  local ret = ((hi << 8) | lo) + 1        -- JSR pushes PC-1
  local a = (s["cpu.a"] or 0) & 0xFF
  local k = string.format("act-setter A=$%02X  called from $%02X:%04X",
    a, (s["cpu.k"] or 0), ret)
  hits[k] = (hits[k] or 0) + 1
end, emu.callbackType.exec, ACTSET, ACTSET, emu.cpuType.snes, emu.memType.snesMemory)

-- The toss itself: $C1:07E5 copies a 5-byte record from Y (b1-b2 = X velocity,
-- b3-b4 = Y velocity), negates X when the thrower faces left, and stores it as
-- the victim's velocity. So the direction of a throw is DATA, and this reports
-- both the record's address and its contents.
local TOSS = tonumber(os.getenv("TOSS") or "0xF707E5")
emu.addMemoryCallback(function()
  if not armed then return end
  nwrite = nwrite + 1
  local s = st(); if not s then return end
  local y = s["cpu.y"] or 0
  local k = s["cpu.k"] or 0
  local sp = s["cpu.sp"] or 0
  local ret = ((emu.read(sp + 2, emu.memType.snesMemory) or 0) << 8
             | (emu.read(sp + 1, emu.memType.snesMemory) or 0)) + 1
  local rec = {}
  for i = 0, 5 do
    rec[#rec + 1] = string.format("%02X",
      emu.read((k << 16) | ((y + i) & 0xFFFF), emu.memType.snesMemory) or 0)
  end
  hits[string.format("TOSS record $%02X:%04X = %s   (called from $%02X:%04X)",
    k, y, table.concat(rec, " "), k, ret)] = 1
end, emu.callbackType.exec, TOSS, TOSS, emu.cpuType.snes, emu.memType.snesMemory)

watch("p1 act  +0x01", P1 + 0x01)
watch("p1 req  +0x51", P1 + 0x51)
watch("p1 step +0x02", P1 + 0x02)
-- VICTIM side. The direction bug survives a correct facing byte, so the sign
-- must enter where the victim is moved: watch the victim's X-velocity and X.
if os.getenv("VICTIM") == "1" then
  -- $C1:01B0 integrates position from the velocity terms +0x30/+0x36/+0x38
  -- into +0x20..+0x23, so the toss's SIGN is written to +0x30.
  watch("p2 xvel +0x30", P2 + 0x30)
  watch("p2 xvel +0x31", P2 + 0x31)
  watch("p2 act  +0x01", P2 + 0x01)
  watch("p2 face +0x09", P2 + 0x09)
end

local ctx = {}
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() poke(); hold = true; return sf > 20 end,
  function() poke(); pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 120 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() poke(); pulse[1] = beat({ a = true }); return ram(0x1B82) == 1 or sf > 120 end,
  function()
    poke(); hold = false
    pulse[0] = (sf % 30 < 4) and { start = true } or {}
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); LOG:close(); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return ram(0x01FA) == 0x80 and sf > 120 end,
  function()
    local d = posx(P2) - posx(P1)
    pulse[0] = (d > 0) and { right = true } or { left = true }
    if math.abs(d) <= 26 then
      ctx.p1char = ram(P1); armed = true
      return true
    end
    if sf > 600 then log("VOID: never reached contact range."); LOG:close(); emu.stop(2) end
    return false
  end,
  function()
    pulse[0] = (sf < 5) and press() or {}
    return sf > 170        -- long enough for the slower throw's toss frame
  end,
  function()
    armed = false
    local ks = {}
    for k in pairs(hits) do ks[#ks + 1] = k end
    table.sort(ks)
    log(string.format("THROWSRC tag=%s input=%s saturn=%s p1char=$%02X writes=%d distinct=%d",
      TAG, INPUT, tostring(SATURN), ctx.p1char or 0, nwrite, #ks))
    for _, k in ipairs(ks) do log("  " .. k .. "  x" .. hits[k]) end
    if nwrite == 0 then
      log("VOID: no writes seen at all — broken hook, not a silent engine.")
      LOG:close(); emu.stop(2)
    end
    LOG:close(); emu.stop(0)
    return true
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then LOG:close(); emu.stop(0) end
  if frames > 9000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
