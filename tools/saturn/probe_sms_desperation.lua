-- probe_sms_desperation.lua — trigger her DESPERATION with the decoded motion
-- (spec5 = dirs back,db,down,df,fwd,back + button = 412364+P per Fighter S).
-- Pokes low HP early, waits out the dizzy/danger act, then performs the motion.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/desperation.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local acts = {}
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  local p1 = PL.pad()
  local q = 400
  -- 412364 facing right: b, db, d, df, f, b then +LP (generous 3f per dir)
  local seq = {
    { left = true }, { left = true, down = true }, { down = true },
    { down = true, right = true }, { right = true }, { left = true },
  }
  if t >= q and t < q + 18 then
    p1 = PL.pad(seq[math.floor((t - q) / 3) + 1])
  elseif t >= q + 18 and t <= q + 20 then
    p1 = PL.pad({ left = true, x = true })
  end
  emu.setInput(p1, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1000 + o, 0) end
    wr(0x1049, 0x14)
  end
  if t == 395 then log(string.format("pre-motion act=%02X hp=%d", ram(0x1001), ram(0x1049))) end
  if t >= 399 and t <= 428 then
    log(string.format("t=%03d dir00=%02X st1[%02X %02X] st2[%02X %02X] st3[%02X %02X] st4[%02X %02X] st5[%02X %02X]",
      t, ram(0x00),
      ram(0x105B), ram(0x105C), ram(0x105D), ram(0x105E), ram(0x105F), ram(0x1060),
      ram(0x1061), ram(0x1062), ram(0x1063), ram(0x1064)))
  end
  if t > 400 and t <= 560 then acts[ram(0x1001)] = true end
  if t == 560 then
    local l = {}
    for a in pairs(acts) do l[#l + 1] = string.format("%02X", a) end
    table.sort(l)
    log(string.format("acts after motion: [%s] end=%02X req51=%02X", table.concat(l, " "),
      ram(0x1001), ram(0x1051)))
    log("DONE"); emu.stop(0)
  end
end, emu.eventType.endFrame)
print("desperation probe loaded")
