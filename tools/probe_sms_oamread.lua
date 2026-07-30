-- probe_sms_oamread.lua — smoke ROM: which $84:8000-table entry does the OAM
-- renderer read for P1 after the Saturn poke? Watches bus reads of the Uranus
-- entry ($84:8012) vs Saturn's ($84:8054) with reader PC.
-- ROM=build/SailorMoonS_saturn_smoke.sfc tools/run.sh tools/probe_sms_oamread.lua 120
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "oamread.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local n = 0

local function pcstr()
  local ok, st = pcall(emu.getState)
  local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"])
  local k = st and (st["cpu.k"] or st["snes.cpu.k"])
  return pc and string.format("%02X:%04X", k or 0, pc) or "?"
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

-- emitter entries: normal $80:9B17 / flipped $80:9BCB; log inputs per call
local function dp(a) return ram(a) end
for _, e in ipairs({ { 0x809B17, "emitN" }, { 0x809BCB, "emitF" } }) do
  emu.addMemoryCallback(function()
    if t >= 100 and t <= 101 and n < 30 then
      n = n + 1
      log(string.format("t=%03d %s obj=%02X%02X cnt=%02X list12=%02X%02X x01=%02X%02X y03=%02X%02X slot98=%02X%02X",
        t, e[2], ram(0x89), ram(0x88), ram(0x00), ram(0x13), ram(0x12),
        ram(0x02), ram(0x01), ram(0x04), ram(0x03), ram(0x99), ram(0x98)))
    end
  end, emu.callbackType.exec, e[1], e[1], emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1000 + o, 0) end
  end
  if t == 110 then log("DONE"); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_sms_oamread loaded")
