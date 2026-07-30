-- probe_sms_saturn_flow.lua — verify the UNVERIFIED mechanics on the Saturn build:
--   throw:   P1 Saturn close 6HP on Jupiter -> throw act, P2 held/thrown
--   thrown:  Jupiter close 6HP on Saturn -> her victim acts (0x1C/0x1D), survives
--   desp06/07(+b1): low-HP special requests -> does a desperation act start?
--   ko-win:  KO Jupiter with fireball -> win pose -> round transition, no hang
--   close5HK-guard: close 5HK vs held guard -> BLOCKED (pose 0x1D fix coverage)
-- ROM=build/saturn/SailorMoonS_saturn_v0.6.0.sfc tools/run.sh tools/saturn/probe_sms_saturn_flow.lua 900
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/saturn_flow.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local CASES = {
  { name = "desp req06 lowHP", dist = 120, lowhp = true, req = 0x06 },
  { name = "desp req07 lowHP", dist = 120, lowhp = true, req = 0x07 },
  { name = "ko-win-round", dist = 70, kop2 = true, motion = true, watch = 220 },
  { name = "close5HK guard", dist = 24, guard = true, act = function(t, PRESS)
      if t >= PRESS and t <= PRESS + 1 then return PL.pad({ a = true }) end end },
}
local ci, t, needLoad = 1, -1, true
local acts1, acts2, notes = {}, {}, {}
local PRESS = 150

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
    if c.act then p1 = c.act(t, PRESS) or PL.pad() end
    if c.p2act then p2 = c.p2act(t, PRESS) or PL.pad() end
    if c.motion then
      local q = PRESS
      if t == q or t == q + 1 then p1 = PL.pad({ down = true })
      elseif t <= q + 3 then p1 = PL.pad({ down = true, right = true })
      elseif t <= q + 5 then p1 = PL.pad({ right = true })
      elseif t <= q + 7 then p1 = PL.pad({ right = true, y = true }) end
    end
    if c.guard and t >= PRESS - 30 then p2 = PL.pad({ right = true }) end
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
    if c.lowhp then wr(0x1049, 0x16) end
    if c.kop2 then wr(0x10C9, 0x02) end
  end
  if c.req and t == PRESS then wr(0x1051, c.req) end
  if t > PRESS and t <= PRESS + (c.watch or 110) then
    acts1[ram(0x1001)] = true; acts2[ram(0x1081)] = true
    if ram(0x1051) ~= 0 and c.req then notes["req-consumed"] = true end
  end
  if t == PRESS + (c.watch or 110) then
    local l1, l2 = {}, {}
    for a in pairs(acts1) do l1[#l1 + 1] = string.format("%02X", a) end
    for a in pairs(acts2) do l2[#l2 + 1] = string.format("%02X", a) end
    table.sort(l1); table.sort(l2)
    log(string.format("%-20s p1acts[%s] p2acts[%s] endP1=%02X endP2=%02X p2hp=%d",
      c.name, table.concat(l1, " "), table.concat(l2, " "),
      ram(0x1001), ram(0x1081), ram(0x10C9)))
    acts1, acts2, notes = {}, {}, {}
    ci = ci + 1
    if not CASES[ci] then log("DONE"); emu.stop(0) end
    needLoad = true; t = -1
  end
end, emu.eventType.endFrame)
print("probe_sms_saturn_flow loaded")
