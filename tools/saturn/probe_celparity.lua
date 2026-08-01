
-- probe_celparity.lua — force each act and compare the CEL the engine resolves
-- (pose -> cel record -> addr24). Port banks $EB-$ED map to Super S $DD-$DF, so
-- normalized (bank-delta, offset) must match exactly. GAME=supers|port
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local GAME = os.getenv("GAME") or "port"
local LOG = assert(io.open(ENV.TRACE .. "saturn/cel_" .. GAME .. ".txt", "w"))
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
local ACTS = {0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A,0x4B,0x4C,0x4D,0x4E,0x4F,
              0x50,0x52,0x54,0x56,0x58,0x5A,0x5C,0x5E,0x60,0x62,0x64,0x66,0x68,0x6A,0x6E}
local ai, phase = 1, 0
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 and GAME == "port" then
    wr(0x1000, 0x1C)
    for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
  end
  if t < 90 then return end
  local base = 90 + (ai - 1) * 26
  if ai <= #ACTS then
    local a = ACTS[ai]
    if t == base then
      wr(0x1001, a); wr(0x1002, 0); wr(0x1004, a); wr(0x1006, 0); wr(0x1007, 0)
    elseif t > base and t <= base + 20 then
      log(string.format("act %02X f%02d pose=%02X celA=%02X%02X%02X celB=%02X%02X%02X",
        a, t - base, ram(0x1005),
        ram(0x100E), ram(0x100D), ram(0x100C),
        ram(0x1011), ram(0x1010), ram(0x100F)))
    elseif t == base + 25 then
      ai = ai + 1
    end
  else
    log("done"); emu.stop(0)
  end
end, emu.eventType.endFrame)
print("celparity loaded " .. GAME)
