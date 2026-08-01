
-- probe_attackid.lua — what attackIDs (+0x44) does she set, and do they stay
-- inside SMS's on-hit table range? Sweeps her move requests and logs +0x44.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local GAME = os.getenv("GAME") or "port"
local LOG = assert(io.open(ENV.TRACE .. "saturn/attackid_" .. GAME .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local STATE = (GAME == "supers") and "saturn/saturn_vs_uranus_supers.mss" or "uranus_vs_jupiter_f5.mss"
local HOOK = (GAME == "supers") and 0x808347 or 0x808353
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, HOOK, HOOK, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
local ACTS = {0x40,0x42,0x44,0x46,0x48,0x4A,0x4C,0x4E,0x50,0x52,0x54,0x56,0x58,0x5A,0x5C,0x5E,
              0x60,0x62,0x64,0x66,0x68,0x6A,0x6E,0x74,0x78,0x79}
local ai = 1
local seen = {}
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 and GAME == "port" then
    wr(0x1000, 0x1C)
    for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
  end
  if t < 90 then return end
  local base = 90 + (ai - 1) * 30
  if ai <= #ACTS then
    local a = ACTS[ai]
    if t == base then
      wr(0x1001, a); wr(0x1002, 0); wr(0x1004, a); wr(0x1006, 0); wr(0x1007, 0)
      seen[a] = {}
    elseif t > base and t <= base + 24 then
      local id = ram(0x1044)
      if id ~= 0 then seen[a][id] = true end
    elseif t == base + 28 then
      local ids = {}
      for k in pairs(seen[a] or {}) do ids[#ids+1] = string.format("%02X", k) end
      table.sort(ids)
      log(string.format("act %02X: attackIDs [%s]", a, table.concat(ids, " ")))
      ai = ai + 1
    end
  else
    log("done"); emu.stop(0)
  end
end, emu.eventType.endFrame)
print("attackid loaded " .. GAME)
