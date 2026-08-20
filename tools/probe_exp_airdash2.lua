-- probe_exp_airdash2.lua — does URANUS get air dashes via ROUTE INSERTION?
-- (Phase 3 of the anime-fighter feasibility programme. Companion of
-- tools/exp_airdash2.py; harness shape per probe_exp_airdash.lua.)
--
--   SMS_DIR=back  ROM=build/exp_airdash2.sfc tools/run.sh tools/probe_exp_airdash2.lua 90
--   SMS_DIR=front ROM=build/exp_airdash2.sfc tools/run.sh tools/probe_exp_airdash2.lua 90
--   SMS_DIR=back                             tools/run.sh tools/probe_exp_airdash2.lua 90   (clean = negative)
--   -> traces/exp_airdash2_<dir>.txt
--
-- Controls in every run: the GROUND backdash (act 0x26) and the GROUND Shadow
-- Dash (act 0x60) must behave as vanilla — the stub's grounded branch falls
-- through to the untouched table entries. The air phase is the measurement:
-- back double-tap -> act 0x2B, 66 -> act 0x2C, only on the build.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local DIR = os.getenv("SMS_DIR") or "back"
local TAG = os.getenv("SMS_TAG") or DIR
local LOG = assert(io.open(ENV.TRACE .. "exp_airdash2_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local STATE = "uranus_vs_jupiter_clean.mss"
local t, loaded = -1, false
local phase, phaseStart = "settle", 0
local gback, g66, air = {}, {}, {}

local function p1(o) return PL.ram(P1 + o) end
local function airborne() return (p1(0x16) & 0x80) == 0 end
local function backDir() return (p1(0x09) ~= 0) and "right" or "left" end
local function fwdDir()
  return p1(0x21) + 256 * p1(0x22) < PL.ram(P2 + 0x21) + 256 * PL.ram(P2 + 0x22)
      and "right" or "left"
end
local function setPhase(p)
  log(string.format("t=%4d  %s -> %s  (act=%02X st=%02X y=%d)", t, phase, p, p1(0x01), p1(0x16), p1(0x25)))
  phase, phaseStart = p, t
end

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_exp_airdash2: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  local k, b = t - phaseStart, {}
  if phase == "gback" or phase == "g66" or phase == "air" then
    local d
    if phase == "gback" then d = backDir()
    elseif phase == "g66" then d = fwdDir()
    else d = (DIR == "front") and fwdDir() or backDir() end
    if (k >= 0 and k < 5) or (k >= 9 and k < 14) then b[d] = true end
  elseif phase == "jump" and k < 6 then
    b.up = true
  end
  emu.setInput(PL.pad(b), 0, 0)
  emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

local function snap()
  return { t = t, act = p1(0x01), step = p1(0x02), hurt = p1(0x41), st = p1(0x16),
           x = p1(0x21) + 256 * p1(0x22), y = p1(0x25), cmd = p1(0x51) }
end
local function report(name, rs, want)
  log(""); log("== " .. name .. " ==")
  local acts, hurts, x0, x1 = {}, {}, nil, nil
  for _, r in ipairs(rs) do
    log(string.format("   t=%4d act=%02X stp=%02X hurt=%02X st=%02X x=%4d y=%3d cmd=%02X",
        r.t, r.act, r.step, r.hurt, r.st, r.x, r.y, r.cmd))
    if want[r.act] then
      acts[r.act] = (acts[r.act] or 0) + 1
      hurts[r.hurt] = (hurts[r.hurt] or 0) + 1
      x0 = x0 or r.x; x1 = r.x
    end
  end
  local an, hn = {}, {}
  for a, n in pairs(acts) do an[#an + 1] = string.format("%02X x%d", a, n) end
  for h, n in pairs(hurts) do hn[#hn + 1] = string.format("%02X x%d", h, n) end
  table.sort(an); table.sort(hn)
  if next(acts) then
    log(string.format("   VERDICT: acts %s; hurt %s; dx=%d", table.concat(an, ","),
        table.concat(hn, ","), (x1 or 0) - (x0 or 0)))
  else
    log("   VERDICT: none of the wanted acts appeared")
  end
end

emu.addEventCallback(function()
  if t < 0 then return end
  local k = t - phaseStart
  if phase == "settle" then
    if k > 70 then setPhase("gback") end
  elseif phase == "gback" then
    if k >= 0 then gback[#gback + 1] = snap() end
    if k > 45 then setPhase("g66") end
  elseif phase == "g66" then
    g66[#g66 + 1] = snap()
    if k > 55 then setPhase("rest") end
  elseif phase == "rest" then
    if k > 30 then setPhase("jump") end
  elseif phase == "jump" then
    if k > 2 and airborne() then setPhase("air") end
    if k > 40 then setPhase("done") end
  elseif phase == "air" then
    air[#air + 1] = snap()
    if k > 70 then setPhase("done") end
  elseif phase == "done" then
    report("GROUND 44 (control: act 26, hurt 00)", gback, { [0x26] = true })
    report("GROUND 66 (control: act 60, the Shadow Dash)", g66, { [0x60] = true })
    report("AIR " .. DIR .. " (build: 2B back / 2C front; clean: nothing)", air,
        { [0x2B] = true, [0x2C] = true, [0x26] = true, [0x60] = true })
    LOG:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_airdash2 loaded: " .. DIR)
