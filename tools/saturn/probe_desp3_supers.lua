
-- probe_desp3_supers.lua — desperation CONNECT test on the Super S
-- saturn_vs_uranus_supers savestate: poke req=0x0B at near/mid/far P2 distances;
-- watch her acts, hitboxes, P2 reaction and damage.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/desp3_supers.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn/saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
local CASES = { {0xA0, "near"}, {0xC0, "mid"}, {0xF0, "far"} }
local case = 0
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1049, 0x10)
  end
  local base = 120 + case * 200
  if t == base and case < #CASES then
    local c = CASES[case + 1]
    wr(0x10A1, c[1]); wr(0x10A2, 0x00)     -- position P2
    wr(0x10C9, 96)                          -- refresh P2 HP
    log("-- case " .. c[2] .. " p2x=" .. c[1])
  end
  if t == base + 10 then wr(0x1051, 0x0B) end
  if t >= base + 10 and t <= base + 150 and t % 3 == 0 then
    local a = ram(0x1001)
    if a ~= 0 and a ~= 2 or ram(0x1081) ~= 0 then
      log(string.format("t=%03d act=%02X pose=%02X hit40=%02X p2act=%02X p2hp=%d p1x=%d p2x=%d",
        t, a, ram(0x1005), ram(0x1040), ram(0x1081), ram(0x10C9),
        ram(0x1021) + 256*ram(0x1022), ram(0x10A1) + 256*ram(0x10A2)))
    end
  end
  if t == base + 160 then case = case + 1 end
  if case >= #CASES and t > base + 170 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)
print("desp3 loaded")
