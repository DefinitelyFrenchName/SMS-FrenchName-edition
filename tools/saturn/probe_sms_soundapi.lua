-- probe_sms_soundapi.lua — find SMS's sound-play API: Uranus does 5LP (whoosh);
-- watch APU port writes ($2140-2143) with writer PC, plus writes to candidate
-- sound-queue WRAM (found by diffing: log the value flow).
-- ROM=<clean SMS> tools/run.sh tools/saturn/probe_sms_soundapi.lua 120
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/soundapi.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram
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

-- writers of the sfx slot $78 and voice slots $1078/$10F8 (nonzero values only)
for _, base in ipairs({ 0x000078, 0x7E0078, 0x001078, 0x7E1078, 0x0010F8, 0x7E10F8 }) do
  emu.addMemoryCallback(function(addr, value)
    if t >= 90 and (value or 0) ~= 0 and n < 60 then
      n = n + 1
      log(string.format("t=%03d SND[%04X] <= %02X @ %s", t, addr % 0x10000, value or -1, pcstr()))
    end
  end, emu.callbackType.write, base, base, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  local p1 = PL.pad()
  if t >= 100 and t <= 101 then p1 = PL.pad({ y = true })          -- 5LP whiff
  elseif t >= 160 and t <= 161 then p1 = PL.pad({ x = true })      -- 5HP whiff
  elseif t >= 220 and t <= 221 then p1 = PL.pad({ a = true })      -- 5HK whiff
  -- DS fireball 214+LP
  elseif t >= 280 and t <= 281 then p1 = PL.pad({ down = true })
  elseif t >= 282 and t <= 283 then p1 = PL.pad({ down = true, left = true })
  elseif t >= 284 and t <= 285 then p1 = PL.pad({ left = true })
  elseif t >= 286 and t <= 287 then p1 = PL.pad({ left = true, y = true }) end
  emu.setInput(p1, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 380 then log("DONE"); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_sms_soundapi loaded")
