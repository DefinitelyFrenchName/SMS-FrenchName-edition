
-- probe_sms_5lk.lua — 5LK regression: does an id-0x1C object appear in the
-- projectile/effect pools (a second Saturn drawn), and how many sprites does
-- she occupy? Presses LP then LK and compares.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/lk5_" .. (os.getenv("TAG") or "x") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local b1 = {}
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(b1), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
local function sprites()
  local n = 0
  for slot = 0, 127 do
    if ram(0x200 + slot*4 + 1) < 0xE0 then n = n + 1 end
  end
  return n
end
local function pools()
  local out = {}
  for _, a in ipairs({0x1100, 0x1180, 0x1200, 0x1280, 0x1300, 0x1380}) do
    out[#out+1] = string.format("%02X", ram(a))
  end
  return table.concat(out, " ")
end
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
    wr(0x10A1, 0x30); wr(0x10A2, 0x01)
  end
  if t == 120 then b1 = {y = true}; log("-- 5LP") end
  if t == 124 then b1 = {} end
  if t >= 120 and t <= 190 and t % 6 == 0 then
    log(string.format("t=%03d LP act=%02X pose=%02X sprites=%d pools[%s]", t, ram(0x1001), ram(0x1005), sprites(), pools()))
  end
  if t == 240 then b1 = {b = true}; log("-- 5LK") end
  if t == 244 then b1 = {} end
  if t >= 240 and t <= 320 and t % 6 == 0 then
    log(string.format("t=%03d LK act=%02X pose=%02X sprites=%d pools[%s]", t, ram(0x1001), ram(0x1005), sprites(), pools()))
  end
  if t == 300 then
    local png = emu.takeScreenshot()
    local f = assert(io.open(ENV.TRACE .. "saturn/lk5_" .. (os.getenv("TAG") or "x") .. ".png", "wb"))
    f:write(png); f:close()
  end
  if t > 330 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)
print("5lk probe loaded")
