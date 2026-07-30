-- probe_sms_saturn_pad.lua — PAD-INPUT test for Saturn in SMS: real buttons through
-- the hooked button-map, a real qcf motion through the grafted recognizers, and box
-- checks (her 5LP connects on Jupiter; Jupiter's 5LP connects on her).
-- ROM=build/SailorMoonS_saturn_smoke.sfc tools/run.sh tools/probe_sms_saturn_pad.lua 400
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn_pad.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

-- each case: name, plan = {t -> pad}, park (P2 distance), watch window, verdicts
local CASES = {
  { name = "5LP button",  btn = "y", dist = 200 },
  { name = "5HP button",  btn = "x", dist = 200 },
  { name = "5LK button",  btn = "b", dist = 200 },
  { name = "5HK button",  btn = "a", dist = 200 },
  { name = "qcf+LP motion", motion = true, dist = 200 },
  { name = "5LP connects", btn = "y", dist = 40, expectHit = true },
  { name = "Jupiter hits Saturn", p2btn = "y", dist = 40, expectP1Hit = true },
  { name = "crouch 5LP", btn = "y", hold = { down = true }, dist = 200 },
  { name = "crouch 5HK", btn = "a", hold = { down = true }, dist = 200 },
  { name = "jump", hold = { up = true }, dist = 200, holdlen = 4 },
  { name = "jump 5HK", btn = "a", hold = { up = true }, dist = 200, holdlen = 20 },
}
local ci, t, needLoad = 1, -1, true
local acts, sawP2Hit, sawP1Hit = {}, false, false
local PRESS = 140

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local c = CASES[ci]
  local p1, p2 = PL.pad(), PL.pad()
  if c and t >= PRESS then
    if c.hold then
      local base = {}
      for k, v in pairs(c.hold) do base[k] = v end
      if t <= PRESS + (c.holdlen or 30) then p1 = PL.pad(base) end
      if c.btn and t >= PRESS + 16 and t <= PRESS + 17 then
        base[c.btn] = true; p1 = PL.pad(base)
      end
    elseif c.motion then
      local q = PRESS
      if t <= q + 1 then p1 = PL.pad({ down = true })
      elseif t <= q + 3 then p1 = PL.pad({ down = true, right = true })
      elseif t <= q + 5 then p1 = PL.pad({ right = true })
      elseif t <= q + 7 then p1 = PL.pad({ right = true, y = true }) end
    elseif c.btn and t <= PRESS + 1 then p1 = PL.pad({ [c.btn] = true })
    elseif c.p2btn and t <= PRESS + 1 then p2 = PL.pad({ [c.p2btn] = true }) end
  end
  emu.setInput(p1, 0, 0); emu.setInput(p2, 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  local c = CASES[ci]
  if not c then return end
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1000 + o, 0) end
  end
  if t == PRESS - 12 then
    local px = ram(0x1021) + 256 * ram(0x1022)
    local x = px + c.dist
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
  end
  if t > PRESS and t <= PRESS + 90 then
    acts[ram(0x1001)] = true
    local a2 = ram(0x1081)
    if a2 >= 0x0E and a2 <= 0x16 then sawP2Hit = true end
    local a1 = ram(0x1001)
    if a1 >= 0x0E and a1 <= 0x16 then sawP1Hit = true end
  end
  if t == PRESS + 90 then
    local la = {}
    for a in pairs(acts) do la[#la + 1] = string.format("%02X", a) end
    table.sort(la)
    local verdict = "?"
    if c.expectHit then verdict = sawP2Hit and "HIT-CONFIRMED" or "NO-HIT"
    elseif c.expectP1Hit then verdict = sawP1Hit and "SATURN-TAKES-HITS" or "NO-HIT-ON-SATURN"
    else
      local atk = false
      for a in pairs(acts) do if a >= 0x40 then atk = true end end
      verdict = atk and "MOVE-CAME-OUT" or "NOTHING"
    end
    log(string.format("%-22s acts[%s] p2hit=%s p1hit=%s -> %s",
      c.name, table.concat(la, " "), tostring(sawP2Hit), tostring(sawP1Hit), verdict))
    acts, sawP2Hit, sawP1Hit = {}, false, false
    ci = ci + 1
    if not CASES[ci] then log("DONE"); emu.stop(0) end
    needLoad = true; t = -1
  end
end, emu.eventType.endFrame)
print("probe_sms_saturn_pad loaded")
