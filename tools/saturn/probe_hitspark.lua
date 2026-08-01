
-- probe_hitspark.lua — which effect-object id spawns when a character GETS HIT?
-- GAME=supers (Saturn victim) | sms (vanilla victim) | port (our Saturn victim)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local GAME = os.getenv("GAME") or "sms"
local LOG = assert(io.open(ENV.TRACE .. "saturn/hitspark_" .. GAME .. ".txt", "w"))
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
    if GAME == "port" then
      wr(0x1000, 0x1C)
      for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
    end
    wr(0x1021, 0x90); wr(0x1022, 0x00); wr(0x10A1, 0xA4); wr(0x10A2, 0x00)
  end
  if t >= 90 and t < 200 then b2 = (t % 14 < 3) and {y = true} or {} end
  if t >= 90 and t < 260 then
    for _, slot in ipairs({0x1200, 0x1280, 0x1300, 0x1380}) do
      local id = ram(slot)
      if id ~= 0 and not seen[id] then
        seen[id] = t
        log(string.format("t=%03d effect-pool spawn: id=%02X (victim act=%02X)", t, id, ram(0x1001)))
      end
    end
  end
  if t > 280 then
    local ids = {}
    for id in pairs(seen) do ids[#ids+1] = string.format("%02X", id) end
    table.sort(ids)
    log("effect ids seen: " .. table.concat(ids, " "))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("hitspark loaded " .. GAME)
