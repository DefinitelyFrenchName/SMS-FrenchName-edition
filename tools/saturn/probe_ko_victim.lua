
-- probe_ko_victim.lua — KO sequence for a SATURN VICTIM. GAME env: supers|sms.
-- Super S: Saturn is P1 in the fixture; SMS: poke P1 to Saturn. Opponent lands
-- a jab that kills; we log the victim's act chain (expect 1A -> 1E -> 1F -> 21)
-- and whether the round sequencer ($1E05) advances.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local GAME = os.getenv("GAME") or "sms"
local LOG = assert(io.open(ENV.TRACE .. "saturn/kovictim_" .. GAME .. (os.getenv("VANILLA") == "1" and "_van" or "") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local b2 = {}
local STATE = (GAME == "supers") and "saturn/saturn_vs_uranus_supers.mss" or "uranus_vs_jupiter_f5.mss"
local HOOK = (GAME == "supers") and 0x808347 or 0x808353
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, HOOK, HOOK, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)
local seen = {}
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    if GAME == "sms" and os.getenv("VANILLA") ~= "1" then
      wr(0x1000, 0x1C)
      for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
    end
    wr(0x1021, 0x90); wr(0x1022, 0x00); wr(0x10A1, 0xA4); wr(0x10A2, 0x00)
    wr(0x1049, 1)                                   -- P1 (Saturn) at 1 HP
  end
  if t >= 90 and t < 260 then b2 = (t % 12 < 3) and {y = true} or {} end
  if t >= 90 and t % 15 == 0 then
    local a = ram(0x1001)
    if not seen[a] then seen[a] = t end
    log(string.format("t=%03d act=%02X st=%02X pose=%02X hp=%d | y=%02X%02X vy=%02X%02X vx=%02X%02X f16=%02X f18=%02X | 1E05=%02X",
      t, a, ram(0x1002), ram(0x1005), ram(0x1049),
      ram(0x1026), ram(0x1025), ram(0x1035), ram(0x1034), ram(0x1033), ram(0x1032),
      ram(0x1016), ram(0x1018), ram(0x1E05)))
  end
  if t > 700 then
    local acts = {}
    for a in pairs(seen) do acts[#acts+1] = string.format("%02X", a) end
    table.sort(acts)
    log("victim acts seen: " .. table.concat(acts, " "))
    log(ram(0x1049) == 0 and (ram(0x1001) == 0x1E and "STUCK IN 1E" or "progressed past 1E") or "no KO")
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("kovictim loaded " .. GAME)
