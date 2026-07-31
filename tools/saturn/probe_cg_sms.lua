
-- probe_CGRAMDUMP — dump CGRAM OBJ palette rows during a fireball
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/cg_sms.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
local buttons = {}
emu.addEventCallback(function()
  emu.setInput(PL.pad(buttons), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
local function cg(row)
  local base = 128 * 2 + row * 32   -- OBJ palettes at CGRAM word 128
  local tcol = {}
  for i = 0, 15 do
    local lo = emu.read(base + i * 2, emu.memType.snesCgRam)
    local hi = emu.read(base + i * 2 + 1, emu.memType.snesCgRam)
    tcol[#tcol + 1] = string.format("%04X", hi * 256 + lo)
  end
  return table.concat(tcol, " ")
end
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then emu.write(0x7FF100, 1, emu.memType.snesMemory); emu.write(0x7FF102, 1, emu.memType.snesMemory)
    wr(0x10A1, 0x30); wr(0x10A2, 0x01) end
  if t == 80 then log(string.format("p1 id=%02X (helper transform)", ram(0x1000))) end
  if t == 120 then buttons = {down=true} end
  if t == 124 then buttons = {down=true, right=true} end
  if t == 128 then buttons = {right=true} end
  if t == 132 then buttons = {right=true, y=true} end
  if t == 136 then buttons = {} end
  if t == 170 then
    for r = 0, 3 do log(string.format("OBJpal%d: %s", r, cg(r))) end
    log(string.format("proj id=%02X", ram(0x1100)))
    log("done"); emu.stop(0)
  end
end, emu.eventType.endFrame)
print("cgdump loaded")
