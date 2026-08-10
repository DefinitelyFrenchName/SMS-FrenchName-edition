-- probe_guardcancel.lua — what act IDs is a BLOCKING fighter in, and what runs there?
--
-- The question this serves: SMS is said to define a "special" as a move that can be
-- guard-cancelled into. Before any of that can be checked, two things have to be
-- MEASURED rather than read off a document: which action IDs a blocking fighter
-- actually occupies, and which code decides what she may do while there.
--
--   ROM=<clean> tools/run.sh tools/probe_guardcancel.lua 400
--   -> traces/guardcancel.txt
--
-- Phase A: P1 (Jupiter) crouch-jabs; P2 (Venus) crouch-blocks. Every act change on both
--   sides is logged. Result: P2 enters act 0x0F (crouch blockstun) / 0x0E (stand
--   blockstun) with +0x46 = 0x20 and HP unchanged — i.e. blocked, not hit.
-- Phase B: P2 jumps, to settle what +0x16 bit7 means. The special-start table's
--   flag byte gates on it (bit0 of the flags requires it SET, bit1 requires it CLEAR)
--   and two write-ups in this repo disagree about which of those means "ground".
--   Measured: grounded = bit7 SET (0x80/0x90/0xC0, y=192), airborne = clear (0x40,
--   y=184) — so flag bit0 is ground-only and bit1 is air-only.
--
-- Facing is DERIVED from the two x positions each frame, never assumed: "back" is a
-- direction only relative to where the opponent is standing, and a probe that guesses
-- it reports "she never blocked" for a reason that has nothing to do with the game.
--
-- Two things this probe got wrong first, both kept in the code as comments because they
-- are the reusable part: standing block walks the defender OUT OF RANGE (so nothing ever
-- connected and it looked like she could not block), and the act-setter census used
-- emu.getState() inside a memory callback, which throws and kills the hook silently
-- (HANDOFF trap 8) — it collected an empty table that looked like evidence.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "guardcancel.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080          -- WRAM offsets of the two player structs
local ACT, STEP, HITSTUN, HP = 0x01, 0x02, 0x47, 0x49
local t, needLoad = -1, true
local lastA1, lastA2 = -1, -1
local actWriters = {}                   -- "P2 act 0xNN" -> count
local minGap = 9999
local lastF16 = -1
local seenGuard = {}

local function u16(off) return PL.ram(off) | (PL.ram(off + 1) << 8) end

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "jupiter_vs_venus_clean.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
    log("loaded jupiter_vs_venus_clean.mss (clean ROM)")
    log("frame  P1act P1step  P2act P2step  P2hitstun  P2hp   note")
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

-- Who sets an act, and for whom. Hooked on the act setter $C1:0224 itself rather
-- than on a write watch of P2's act byte: emu.getState() THROWS inside a memory
-- callback in this build and kills the hook without a message (HANDOFF trap 8), so
-- the first version of this probe collected an empty table and looked like evidence
-- that nothing ever wrote the field. An exec callback is a CPU context and is safe.
-- A = the act being set, X = the object base, so both are readable here.
emu.addMemoryCallback(function()
  if not t or t < 1 then return end
  local st = emu.getState().cpu
  local who = (st.x == 0x1080) and "P2" or ((st.x == 0x1000) and "P1" or
              string.format("obj$%04X", st.x))
  local key = string.format("%s act 0x%02X", who, st.a & 0xFF)
  actWriters[key] = (actWriters[key] or 0) + 1
end, emu.callbackType.exec, 0xC10224, 0xC10224, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if needLoad then return end
  local pad1, pad2 = PL.pad(), PL.pad()
  -- derive facing from the live positions; never assume a side
  local x1, x2 = u16(P1 + 0x21), u16(P2 + 0x21)
  local gap = math.abs(x1 - x2)
  -- P2 holds DOWN-back. Standing block was tried first and measured nothing: holding
  -- away walks her backwards out of range, so P1's jab never arrived and the probe
  -- reported "she never blocks" for a reason that has nothing to do with blocking.
  if t and t > 300 then
    if (t % 40) < 4 then pad2.up = true end     -- phase B: jump, to sample +0x16 airborne
  else
    pad2.down = true
    if x2 > x1 then pad2.right = true else pad2.left = true end
  end
  -- P1 walks in until she is close enough to connect, then jabs on a 12-frame cycle
  -- 40px still whiffed: a standing jab passes over a crouching opponent, so P1
  -- crouch-jabs (down+Y). The approach threshold is not a guess either — 22px was
  -- tried and never reached, because push collision stops them further apart than
  -- that, so P1 walked forever and never attacked. minGap below records what is
  -- actually achievable, and the probe reports it.
  if gap < minGap then minGap = gap end
  if gap > 30 then
    if x2 > x1 then pad1.right = true else pad1.left = true end
  elseif t and t > 30 and (t % 12) < 3 then
    pad1.down = true; pad1.y = true
  end
  emu.setInput(pad1, 0, 0)              -- 3rd arg is the port (Mesen quirk)
  emu.setInput(pad2, 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if needLoad then return end
  t = t + 1
  local a1, a2 = PL.ram(P1 + ACT), PL.ram(P2 + ACT)
  if a1 ~= lastA1 or a2 ~= lastA2 then
    local note = ""
    if a2 ~= lastA2 and PL.ram(P2 + HITSTUN) ~= 0 then note = "P2 stunned" end
    log(string.format("%5d   0x%02X  %3d    0x%02X  %3d   +43=%02X +46=%02X +47=%02X +48=%02X +4D=%02X  hp=%d gap=%d %s",
        t, a1, PL.ram(P1 + STEP), a2, PL.ram(P2 + STEP),
        PL.ram(P2 + 0x43), PL.ram(P2 + 0x46), PL.ram(P2 + 0x47),
        PL.ram(P2 + 0x48), PL.ram(P2 + 0x4D), PL.ram(P2 + HP),
        math.abs(u16(P1 + 0x21) - u16(P2 + 0x21)), note))
    lastA1, lastA2 = a1, a2
    if PL.ram(P2 + HITSTUN) ~= 0 or PL.ram(P2 + 0x48) ~= 0 then
      seenGuard[a2] = (seenGuard[a2] or 0) + 1
    end
  end
  -- Phase B: what IS +0x16 bit7? The special-start table's flag byte gates on it (bit0 of the
  -- flags requires it SET, bit1 requires it CLEAR) and the two write-ups disagree about
  -- which of those means "ground". Jump and read it — the cartridge can settle this.
  if t > 300 and t <= 420 then
    if t == 301 then log(""); log("phase B: +0x16 across a jump (P2)") end
    local a2, f16 = PL.ram(P2 + ACT), PL.ram(P2 + 0x16)
    local y = u16(P2 + 0x25)
    if f16 ~= lastF16 then
      log(string.format("  t=%d  P2 act 0x%02X  +0x16=%02X  bit7=%s  y=%d",
          t, a2, f16, (f16 & 0x80) ~= 0 and "SET" or "clear", y))
      lastF16 = f16
    end
  end
  if t > 420 then
    log("")
    log("P2 acts entered while her hitstun/blockstun field was non-zero:")
    for act, n in pairs(seenGuard) do log(string.format("   act 0x%02X   x%d", act, n)) end
    log("")
    log(string.format("closest the two ever got: %d px", minGap))
    log("acts set through the act setter $C1:0224 during the run:")
    local keys = {}
    for k in pairs(actWriters) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do log(string.format("   %-20s x%d", k, actWriters[k])) end
    log("DONE")
    emu.stop(0)
  end
end, emu.eventType.endFrame)
