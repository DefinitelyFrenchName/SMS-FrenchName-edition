-- probe_airguard.lua — WOULD THE ENGINE HONOR AN AIR BLOCK? (Phase 1 of the
-- anime-fighter feasibility programme; the air-block/air-GC kill-shot.)
--
--   SMS_GMODE=air    tools/run.sh tools/probe_airguard.lua 90
--   SMS_GMODE=ground tools/run.sh tools/probe_airguard.lua 90
--   -> traces/airguard_<mode>.txt
--
-- Vanilla has no air block, but the reason decides the cost: the route census
-- shows no jump handler offers a guard entry (structural absence), and the
-- AIR posture reaction sub-table is the "guard-incapable" row. The open
-- question is whether HIT RESOLUTION itself would honor a guard pose on an
-- airborne victim — if it does, air block is an entry-route + reaction-row
-- problem (authorable, and air guard-cancel rides along via the blockstun
-- act's one $0958 route); if resolution checks grounded, the redesign is
-- deeper.
--
--   air    : Jupiter (P2) neutral-jumps holding back; mid-air his act is
--            POKED to 0x0C (stand guard pose) and held; Venus (P1) 5HPs him.
--            Outcomes: blockstun 0x0E/chip = resolution honors air guard;
--            clean hit reaction = a grounded gate exists in resolution.
--   ground : the POSITIVE CONTROL for the poke itself — same poke on a
--            GROUNDED victim must produce a normal block, or the poke does
--            not create a blocking state and the air verdict means nothing.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")

local MODE = os.getenv("SMS_GMODE") or "air"
-- SMS_GVAR: which victim-state bits the harness supplies, comma-joined:
--   natural         no pokes (ground: validates block detection end to end)
--   act             poke act 0x0C, step 0, once (re-poked if the game leaves it)
--   threat          OR 0x10 into +0x51 every frame (the proximity-guard threat bit)
--   back            OR 0x01 into +0x54 every frame (the held-back stance flag)
local GVAR = os.getenv("SMS_GVAR") or "act"
local V = {}
for w in GVAR:gmatch("[^,]+") do V[w] = true end
local DIST = tonumber(os.getenv("SMS_DIST") or "40")
local STATE = os.getenv("SMS_STATE") or "venus_vs_jupiter_clean.mss"
local LOG = assert(io.open(ENV.TRACE .. "airguard_" .. MODE .. "_" .. GVAR:gsub(",", "-") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local ACT, STEP, STATUS, X, XH, Y, HP, F46, HSTOP = 0x01, 0x02, 0x16, 0x21, 0x22, 0x25, 0x49, 0x46, 0x4D
local function r(base, o) return PL.ram(base + o) end
local function x16(base) return r(base, X) + 256 * r(base, XH) end
local function airborne(base) return (r(base, STATUS) & 0x80) == 0 end

local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local rows, hp0, poked, contact = {}, nil, false, nil

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_airguard: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local function dirs()
  local fwd = x16(P1) < x16(P2) and "right" or "left"
  return fwd, fwd    -- P2's back (away from P1) is the SAME screen direction as P1's forward
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  local b1, b2 = {}, {}
  local _, p2back = dirs()
  if phase == "approach" then
    local fwd = dirs()
    b1[fwd] = true
  elseif phase == "jump" then
    if MODE == "air" then
      if k < 6 then b2.up = true              -- neutral jump: back only once airborne
      elseif airborne(P2) and not V.noguard then b2[p2back] = true end
    else
      b2[p2back] = true
    end
  elseif phase == "arm" or phase == "watch" then
    if not V.noguard then b2[p2back] = true end
    local pk = MODE == "air" and 12 or 4      -- air: the juggle probe's proven timing
    if phase == "arm" and k >= pk and k < pk + 4 then b1.x = true end   -- 5HP
  end
  emu.setInput(PL.pad(b1), 0, 0)
  emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)

local function snap()
  return string.format("t=%4d v.act=%02X stp=%02X st=%02X 46=%02X 47=%02X hp=%3d y=%3d hstop=%02X | a.act=%02X",
      t, r(P2, ACT), r(P2, STEP), r(P2, STATUS), r(P2, F46), r(P2, 0x47), r(P2, HP), r(P2, Y), r(P2, HSTOP), r(P1, ACT))
end
local pend47 = nil

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart

  if phase == "settle" then
    if k == 5 then
      local md = PL.ram(0x008D)
      log(string.format("mode byte $8D=%02X (need 01)", md))
      if md ~= 1 then log("SETUP-FAIL: not 2P VS"); LOG:close(); emu.stop(1); return end
    end
    if k > 70 then phase, phaseStart = "approach", t end
  elseif phase == "approach" then
    if math.abs(x16(P1) - x16(P2)) <= DIST then hp0 = r(P2, HP); phase, phaseStart = "jump", t
    elseif k > 150 then log("SETUP-FAIL: approach never closed"); LOG:close(); emu.stop(1) end
  elseif phase == "jump" then
    local ready = MODE == "ground" and k > 4 or (airborne(P2) and k > 2)
    if ready then
      if V.act then
        PL.wr(P2 + ACT, 0x0C); PL.wr(P2 + STEP, 0)
        poked = true
      end
      log(string.format("t=%4d ARMED (%s): victim act=%02X y=%d st=%02X airborne=%s",
          t, GVAR, r(P2, ACT), r(P2, Y), r(P2, STATUS), tostring(airborne(P2))))
      phase, phaseStart = "arm", t
    elseif k > 40 then log("SETUP-FAIL: jump never rose"); LOG:close(); emu.stop(1) end
  elseif phase == "arm" or phase == "watch" then
    -- hold the supplied state until contact so the active frames meet it
    if not contact then
      if poked and r(P2, ACT) ~= 0x0C and r(P2, ACT) < 0x0E then
        PL.wr(P2 + ACT, 0x0C); PL.wr(P2 + STEP, 0)
      end
      if V.threat then PL.wr(P2 + 0x51, PL.ram(P2 + 0x51) | 0x10) end
      if V.back then PL.wr(P2 + 0x54, PL.ram(P2 + 0x54) | 0x01) end
    end
    rows[#rows + 1] = snap()
    if not contact and r(P2, 0x47) ~= 0 then pend47 = r(P2, 0x47) end
    local va = r(P2, ACT)
    if not contact and (va >= 0x0E and va <= 0x20) then
      contact = { t = t, act = va, air = airborne(P2), y = r(P2, Y) }
      log(string.format("CONTACT t=%4d victim -> act %02X  pending-code(+0x47)=%s  airborne=%s y=%d hp %d->%d",
          t, va, pend47 and string.format("%02X", pend47) or "??", tostring(contact.air), r(P2, Y), hp0, r(P2, HP)))
      phase, phaseStart = "watch", t
    end
    if (phase == "arm" and k > 60) or (phase == "watch" and k > 50) then
      log(""); log("== probe_airguard mode=" .. MODE .. " ==")
      for _, s in ipairs(rows) do log("   " .. s) end
      log("")
      if not contact then
        log("SETUP-FAIL: the 5HP never made contact")
      else
        local blocked = contact.act == 0x0E or contact.act == 0x0F
        local hpEnd = r(P2, HP)
        log(string.format("VERDICT (%s): contact act=%02X (%s), airborne=%s, hp %d -> %d (%s)",
            MODE, contact.act, blocked and "BLOCKSTUN — resolution honored the guard" or "HIT reaction — guard not honored",
            tostring(contact.air), hp0, hpEnd,
            hpEnd == hp0 and "no damage" or (hpEnd > hp0 - 4 and "chip-sized" or "full damage")))
      end
      LOG:close(); emu.stop(0)
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_airguard loaded: " .. MODE)
