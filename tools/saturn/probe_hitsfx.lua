
-- probe_hitsfx.lua — Saturn-vs-Saturn (or vanilla) hit: log every sfx write
-- ($78 one-shot, $1078/$10F8 voices) with the writing PC, plus effect spawns
-- and any VRAM DMA around the hit. MODE=sat|van
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = os.getenv("MODE") or "sat"
local LOG = assert(io.open(ENV.TRACE .. "saturn/hitsfx_" .. MODE .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local b1 = {}
local watching = false
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(b1), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
local function pcs()
  local ok, st = pcall(emu.getState)
  return string.format("%02X:%04X", st and (st["cpu.k"] or 0) or 0, st and (st["cpu.pc"] or 0) or 0)
end
for _, a in ipairs({0x7E0078, 0x000078}) do
  emu.addMemoryCallback(function(addr, value)
    if watching and (value or 0) ~= 0 then
      log(string.format("t=%03d SFX $78 <= %02X @ %s (p1act=%02X p2act=%02X)",
        t, value, pcs(), ram(0x1001), ram(0x1081)))
    end
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
for _, a in ipairs({0x7E1078, 0x7E10F8}) do
  emu.addMemoryCallback(function(addr, value)
    if watching and (value or 0) ~= 0 then
      log(string.format("t=%03d VOICE %06X <= %02X @ %s", t, addr, value, pcs()))
    end
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
local spawned = {}
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    if MODE == "sat" then
      for _, base in ipairs({0x1000, 0x1080}) do
        wr(base, 0x1C)
        for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(base + o, 0) end
      end
    end
    wr(0x1021, 0x90); wr(0x1022, 0x00); wr(0x10A1, 0xA6); wr(0x10A2, 0x00)
  end
  if t == 110 then watching = true; log("-- 5LP") end
  if t == 112 then b1 = {y = true} end
  if t == 116 then b1 = {} end
  if t == 200 then log("-- 5LK") end
  if t == 202 then b1 = {b = true} end
  if t == 206 then b1 = {} end
  if watching and t <= 300 then
    for _, s in ipairs({0x1100, 0x1180, 0x1200, 0x1280, 0x1300, 0x1380}) do
      local id = ram(s)
      if id ~= 0 and not spawned[s .. ":" .. id] then
        spawned[s .. ":" .. id] = true
        log(string.format("t=%03d spawn slot %04X id=%02X", t, s, id))
      end
    end
  end
  if t > 300 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)
print("hitsfx loaded " .. MODE)
