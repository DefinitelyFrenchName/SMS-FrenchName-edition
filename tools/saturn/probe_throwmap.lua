-- probe_throwmap.lua — which BUTTON and which DIRECTION produce which ground
-- throw? Measures the behaviour directly, for Saturn and for a vanilla control.
--
-- Field report (2026-08-05, inherited from Super S): (1) her two ground throws
-- are on the wrong buttons — HK triggers the "punch" grab and HP the "kick"
-- grab; (2) the punch grab's DIRECTIONS are reversed as well — 6 at contact
-- gives what 4 should give and vice versa.
--
-- Rather than reason from her button-map record (`$C1:174E` in Super S, whose
-- bytes differ from the common record by a swapped pair — a lead, not a
-- finding), this walks into contact, presses ONE configured input, and reports
-- what actually happened: the thrower's act chain, the victim's act chain, and
-- which SIDE the victim ends up on. Run the same matrix on a vanilla character
-- and the difference between the two tables IS the bug, in the game's own terms.
--
--   SATURN=1 SHELL_ID=6 INPUT=6hp TAG=sat_6hp ROM=<build> \
--     tools/run.sh tools/saturn/probe_throwmap.lua 900
--   SATURN=0 P1CHAR=6  INPUT=6hp TAG=ura_6hp ROM=<build> ...
-- INPUT: lp|lk|hp|hk optionally prefixed 6 or 4 (6hp, 4hk, ...).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
local P1CHAR = num("P1CHAR", 6)
local P2CHAR = num("P2CHAR", 4)          -- Jupiter: a big, stationary victim
local SATURN = os.getenv("SATURN") == "1"
local INPUT = (os.getenv("INPUT") or "6hp"):lower()
local TAG = os.getenv("TAG") or INPUT
local LOG = assert(io.open(ENV.TRACE .. "saturn/throwmap_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end

local P1, P2 = 0x1000, 0x1080
local function act(b) return ram(b + 0x01) end
local function posx(b) return ram(b + 0x21) | (ram(b + 0x22) << 8) end
local function facing(b) return ram(b + 0x09) end

-- decode INPUT into a pad table
local BTN = { lp = "y", lk = "b", hp = "x", hk = "a" }
local dir, btn = INPUT:match("^([64]?)(%a+)$")
if not BTN[btn] then error("bad INPUT " .. INPUT) end
local function press()
  local t = {}
  t[BTN[btn]] = true
  if dir == "6" then t.right = true elseif dir == "4" then t.left = true end
  return t
end

local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local function beat(on) return (frames % 7) < 3 and on or {} end
local function poke() wr(0x1B40, SATURN and SHELL or P1CHAR); wr(0x1B80, P2CHAR) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and p == 0 and SATURN then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local chain1, chain2 = {}, {}
local last1, last2 = -1, -1
local trace = {}
local function watch()
  local a1, a2 = act(P1), act(P2)
  if a1 ~= last1 then chain1[#chain1 + 1] = string.format("%02X", a1); last1 = a1 end
  if a2 ~= last2 then chain2[#chain2 + 1] = string.format("%02X", a2); last2 = a2 end
  -- FACING is the shared engine's direction handle: the throw code sets it from
  -- the input (`lda $50,x / and #$01 / eor #$01 / sta $09,x` at $C1:061B), and
  -- the toss follows it. Logging it separates "the input was read backwards"
  -- from "the act itself moves the victim the wrong way".
  if #trace < 14 then
    trace[#trace + 1] = string.format("a1=%02X f=%d dx=%d", a1, facing(P1),
      posx(P2) - posx(P1))
  end
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
  function()   -- into the round
    poke(); hold = false
    pulse[0] = (sf % 30 < 4) and { start = true } or {}
    pulse[1] = {}
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); LOG:close(); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return ram(0x01FA) == 0x80 and sf > 120 end,
  function()   -- walk into contact
    local d = posx(P2) - posx(P1)
    pulse[0] = (d > 0) and { right = true } or { left = true }
    if math.abs(d) <= 26 then
      ctx.p1char, ctx.p2char = ram(P1), ram(P2)
      ctx.d0, ctx.face = d, facing(P1)
      ctx.x1, ctx.x2 = posx(P1), posx(P2)
      log(string.format("contact: p1char=$%02X p2char=$%02X dx=%d facing=$%02X",
        ctx.p1char, ctx.p2char, d, ctx.face))
      return true
    end
    if sf > 600 then
      log("VOID: never reached contact range — nothing measured.")
      LOG:close(); emu.stop(2)
    end
    return false
  end,
  function()   -- the one input
    pulse[0] = (sf < 5) and press() or {}
    -- SHOT=1 captures the throw itself. "Which of these is the PUNCH grab" is a
    -- question about the animation, and the only honest way to answer it is to
    -- look; act numbers and victim chains are circumstantial.
    if os.getenv("SHOT") == "1" and ctx.shot0 then
      local n = sf - ctx.shot0
      if n == 6 or n == 16 or n == 26 or n == 40 then
        local f = io.open(ENV.TRACE .. "saturn/throwpose_" .. TAG .. "_" .. n .. ".png", "wb")
        if f then f:write(emu.takeScreenshot()); f:close() end
      end
    elseif act(P1) ~= 0 and sf > 2 then ctx.shot0 = sf end
    if sf % 6 == 0 then watch() else
      local a1 = act(P1)
      if a1 ~= last1 then watch() end
    end
    return sf > 150
  end,
  function()
    local dx = posx(P2) - posx(P1)
    -- "side" is the sign of the victim's offset: it flips if the throw put them
    -- behind the thrower, which is the whole question for the direction bug.
    local function side(v) return v > 0 and "right" or "left" end
    log(string.format("THROWMAP tag=%s input=%s saturn=%s p1=$%02X p2=$%02X",
      TAG, INPUT, tostring(SATURN), ctx.p1char or 0, ctx.p2char or 0))
    log(string.format("  thrower acts: %s", table.concat(chain1, " ")))
    log(string.format("  victim  acts: %s", table.concat(chain2, " ")))
    log(string.format("  victim side: %s -> %s   (dx %d -> %d)",
      side(ctx.d0), side(dx), ctx.d0, dx))
    log("  trace: " .. table.concat(trace, " | "))
    -- One compact, greppable verdict so the gate can assert the throw MAPPING
    -- (which button) and the throw DIRECTION (which side) rather than just
    -- "the probe exited 0". Both were wrong in Super S and both are fixed here.
    log(string.format("THROWVERDICT input=%s firstact=$%s side=%s->%s",
      INPUT, chain1[2] or "--", side(ctx.d0), side(dx)))
    if #chain1 <= 1 then
      log("  NOTE: the thrower never changed act — the input produced nothing.")
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
