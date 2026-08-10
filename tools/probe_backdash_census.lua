-- probe_backdash_census.lua — the NEUTRAL backdash, measured, for one character.
--
--   SMS_CHAR=5 ROM=<clean> tools/run.sh tools/probe_backdash_census.lua 200
--   -> appends one row to traces/backdash_census.txt
--
-- WHY. docs/game/sms_specials.md:90 states "neutral backdash distance is ~36px
-- for every character measured", and dismisses the wiki's Uranus row (154px) as
-- a data-entry duplication. But the per-character horizontal constants in the
-- act-0x26 handlers span 3.7x — Chibi -768, Jupiter -1152, Moon -1536, Uranus
-- -2816 — and Uranus's is the exact negation of her Shadow Dash's +2816, which
-- is the number the wiki reports. A universal 36px cannot be true of all of
-- those. One character (Venus, 51px over 15 frames) already contradicts it. So:
-- measure all nine, from a live match, rather than argue from constants.
--
-- It navigates char-select itself (the step list is coltest.lua's, which is the
-- tool that knows this menu) because the repo only has CLEAN-ROM savestates for
-- Venus and Jupiter, and a census that covers two of nine is not a census.
--
-- X IS 16-BIT. The pixel position is +0x21 low / +0x22 high; reading only +0x21
-- gives a value that silently wraps mid-measurement and turns a 90px backdash
-- into a small negative one. (ds_trace.lua reads it correctly; an earlier
-- version of this session's probe did not, and got away with it only because
-- the fixture happened to sit far from a boundary.)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("SMS_CHAR") or "5")
local DUMMY = tonumber(os.getenv("SMS_DUMMY") or "4")
local OUT = assert(io.open(ENV.TRACE .. "backdash_census.txt", "a"))

local P1, P2 = 0x1000, 0x1080
local ACT, STATUS, HURT = 0x01, 0x16, 0x41
local function ram(a) return PL.ram(a) end
local function px(base) return ram(base + 0x21) + 256 * ram(base + 0x22) end
local function act() return ram(P1 + ACT) end

local frames, step, sf = 0, 1, 0
local pulse = {}
local function beat(on) return (frames % 7) < 3 and on or {} end
local function confirm(tbl)
  local h = {}
  if (frames % 7) < 3 then for k, v in pairs(tbl) do h[k] = v end end
  return h
end

-- char-select navigation (coltest.lua's step list)
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function() emu.write(0x1B40, CHAR, emu.memType.snesWorkRam)
             emu.write(0x1B80, DUMMY, emu.memType.snesWorkRam); return sf > 20 end,
  function() pulse[0] = confirm({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = confirm({ a = true }); return sf > 60 end,
  function() return sf > 240 end,
  function() pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
             return ram(P1) == CHAR or sf > 600 end,
  function() return ram(P1) == CHAR and ram(P2) ~= 0 and act() == 0 end,
  function() return sf > 180 end,                      -- settle in neutral
}

-- measurement, after navigation
local mt, rows, phase, seen, post = 0, {}, "nav", false, 0

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] or {}
    emu.setInput(PL.pad(b), 0, p)
  end
end, emu.eventType.inputPolled)

local function finish()
  -- FIRST CONTIGUOUS run of act 0x26 only. The retry cycle fires a second
  -- backdash ~30 frames after the first, and summing every act-0x26 frame in the
  -- trace reported one 30-frame backdash travelling 73px — two 15-frame ones
  -- glued together. A duration is a property of one instance, not of a trace.
  local first, last, lastSkid, invuln, dur, ended = nil, nil, nil, 0, 0, false
  for _, r in ipairs(rows) do
    if r.act == 0x26 and not ended then
      first = first or r
      last = r; dur = dur + 1
      if r.hurt == 0 then invuln = invuln + 1 end
    elseif last and not ended then
      if r.act == 0x09 or r.act == 0x27 then lastSkid = r else ended = true end
    end
  end
  if not first then
    local acts = {}
    for _, r in ipairs(rows) do acts[r.act] = true end
    local ks = {}
    for k in pairs(acts) do ks[#ks + 1] = string.format("%02X", k) end
    table.sort(ks)
    OUT:write(string.format("char %d: NO BACKDASH SEEN; acts during measure: %s\n",
                            CHAR, table.concat(ks, " ")))
  else
    local travel = math.abs(first.x - last.x)
    local total = lastSkid and math.abs(first.x - lastSkid.x) or travel
    OUT:write(string.format(
      "char %d  dur %2df  travel %3dpx (%.1f px/f)  +skid %3dpx  invuln %2d/%2d frames  hurt seen %s\n",
      CHAR, dur, travel, travel / math.max(dur - 1, 1), total, invuln, dur,
      (invuln == dur) and "00 only" or "MIXED"))
  end
  local raw = io.open(ENV.TRACE .. "bd_raw_" .. CHAR .. ".txt", "w")
  if raw then
    for _, r in ipairs(rows) do
      raw:write(string.format("mt=%3d act=%02X hurt=%02X st=%02X x=%d\n",
                              r.t, r.act, r.hurt, r.st, r.x))
    end
    raw:close()
  end
  OUT:close(); emu.stop(0)
end

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if phase == "nav" then
    local fn = STEPS[step]
    if fn and fn() then step = step + 1; sf = 0; pulse = {} end
    if not STEPS[step] then phase = "measure"; mt = 0; pulse = {} end
    if frames > 4000 then
      OUT:write(string.format("char %d: NAV TIMEOUT at step %d (p1=%02X)\n", CHAR, step, ram(P1)))
      OUT:close(); emu.stop(1)
    end
    return
  end

  -- neutral backdash: tap back / release / tap back, both edges inside the
  -- recognizer's 15-frame window. Direction derived from the two positions.
  -- retry the double-tap on a 30-frame cycle: the recognizer needs the match to
  -- have actually started, and a probe that taps once and reports nothing is
  -- indistinguishable from a character that cannot backdash (HANDOFF trap 9).
  -- Facing comes from the engine's OWN byte (+0x09, nonzero = facing left), not
  -- from comparing the two x positions. The position comparison is what a probe
  -- reaches for first, and it produced acts "00 01" here — idle and walk FORWARD,
  -- i.e. it had been pressing toward the opponent the whole time. +0x09 is what
  -- the engine itself uses to mirror the move, so it cannot disagree with it.
  local back = (ram(P1 + 0x09) ~= 0) and "right" or "left"
  local c = mt % 90
  local b = {}
  if (c >= 0 and c < 5) or (c >= 9 and c < 14) then b[back] = true end
  pulse[0] = b
  local a = act()
  if true then
    rows[#rows + 1] = { t = mt, act = a, hurt = ram(P1 + HURT),
                        x = px(P1), st = ram(P1 + STATUS) }
  end
  if a == 0x26 then seen = true end
  mt = mt + 1
  if a ~= 0x26 and a ~= 0x09 then post = seen and post + 1 or 0 else post = 0 end
  if mt > 300 or post > 4 then finish() end
end, emu.eventType.endFrame)

print("probe_backdash_census loaded: char " .. CHAR)
