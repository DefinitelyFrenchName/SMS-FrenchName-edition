
-- probe_poseparity.lua — POSE PARITY vs Super S: drive the same inputs in both
-- games and log (act,pose) per frame so they can be diffed.
-- GAME=supers|port, DIST=far|close
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local GAME = os.getenv("GAME") or "port"
local DIST = os.getenv("DIST") or "far"
local LOG = assert(io.open(ENV.TRACE .. "saturn/parity_" .. GAME .. "_" .. DIST .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local b1 = {}
local STATE = (GAME == "supers") and "saturn/saturn_vs_uranus_supers.mss" or "uranus_vs_jupiter_f5.mss"
local HOOK = (GAME == "supers") and 0x808347 or 0x808353
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, HOOK, HOOK, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(b1), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
-- (label, frame, buttons)
local SEQ = {
  {"5LP",   120, {y=true}}, {"",      124, {}},
  {"5LK",   200, {b=true}}, {"",      204, {}},
  {"2LK",   280, {down=true, b=true}}, {"", 284, {down=true}}, {"", 288, {}},
  {"5HK",   360, {a=true}}, {"",      364, {}},
  {"LPxLK", 440, {y=true}}, {"",      444, {}}, {"", 452, {b=true}}, {"", 456, {}},
}
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    if GAME == "port" then
      wr(0x1000, 0x1C)
      for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
    end
    if DIST == "close" then
      wr(0x1021, 0x90); wr(0x1022, 0x00); wr(0x10A1, 0xA8); wr(0x10A2, 0x00)
    else
      wr(0x1021, 0x60); wr(0x1022, 0x00); wr(0x10A1, 0x40); wr(0x10A2, 0x01)
    end
  end
  for _, e in ipairs(SEQ) do
    if t == e[2] then
      b1 = e[3]
      if e[1] ~= "" then log("== " .. e[1]) end
    end
  end
  if t >= 118 and t <= 520 then
    log(string.format("t=%03d act=%02X pose=%02X hit=%02X", t, ram(0x1001), ram(0x1005), ram(0x1040)))
  end
  if t > 530 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)
print("parity loaded " .. GAME .. " " .. DIST)
