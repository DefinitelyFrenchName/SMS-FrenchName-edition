
-- probe_sms_mirror.lua — mirror-match wedge: both players Saturn, P2 throws P1
-- (6HP at point blank) and we watch BOTH structs + projectile slots in detail.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/mirror.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local b1, b2 = {}, {}
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(b1), 0, 0); emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)
local function dump(tag)
  log(string.format("%s t=%d | P1 id=%02X act=%02X st=%02X pose=%02X f43=%02X f56=%02X f76=%02X x=%d"
    .. " | P2 id=%02X act=%02X st=%02X pose=%02X f43=%02X f56=%02X f76=%02X x=%d | proj %02X/%02X",
    tag, t, ram(0x1000), ram(0x1001), ram(0x1002), ram(0x1005), ram(0x1043), ram(0x1056), ram(0x1076),
    ram(0x1021) + 256*ram(0x1022),
    ram(0x1080), ram(0x1081), ram(0x1082), ram(0x1085), ram(0x10C3), ram(0x10D6), ram(0x10F6),
    ram(0x10A1) + 256*ram(0x10A2), ram(0x1100), ram(0x1180)))
end
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    for _, base in ipairs({0x1000, 0x1080}) do
      wr(base, 0x1C)
      for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(base + o, 0) end
    end
    wr(0x1021, 0x80); wr(0x1022, 0x00); wr(0x10A1, 0x98); wr(0x10A2, 0x00)  -- point blank
  end
  -- P2 throws P1: 6HP
  if t == 150 then b2 = {left = true, x = true}; log("-- P2 throws (6HP)") end
  if t == 156 then b2 = {} end
  if t >= 150 and t <= 400 and (t % 5 == 0) then dump("thr") end
  if t == 420 then
    -- second attempt: P1 throws P2
    wr(0x1021, 0x80); wr(0x1022, 0x00); wr(0x10A1, 0x98); wr(0x10A2, 0x00)
    log("-- P1 throws (6HP)")
    b1 = {right = true, x = true}
  end
  if t == 426 then b1 = {} end
  if t >= 420 and t <= 650 and (t % 5 == 0) then dump("thr2") end
  if t > 680 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)
print("mirror loaded")
