
-- probe_sms_desp2.lua — desperation deep-dive on the SMS side, P1 poked to
-- Saturn (charID 0x1C):
-- (a) feed 412364+P with clean 8f-per-direction steps, watching all 5 rec
--     states (+0x5B..+0x64), +0x51 and act every frame — first with P2 far,
--     then repeated with P2 close as a connect test;
-- (b) then poke +0x51=0x0A (the computed desperation request nibble) at
--     normal HP and at low HP to validate the act side.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/desp2_sms.txt", "w"))
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
local function states()
  local s = {}
  for r = 0, 4 do
    s[#s+1] = string.format("%02X.%02X", ram(0x105B + r*2), ram(0x105C + r*2))
  end
  return table.concat(s, " ")
end
-- P1 faces right (P2 parked right), so back=left, fwd=right
local SEQ = {  -- 412364 = b, db, d, df, f, b   each 8 frames
  {left=true}, {left=true, down=true}, {down=true}, {down=true, right=true},
  {right=true}, {left=true},
}
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
    wr(0x10A1, 0x30); wr(0x10A2, 0x01); wr(0x1049, 0x10)   -- P2 far, low HP
  end
  -- (a) the motion, 8f per step, then button with the last back held
  local base = 120
  for i, pad in ipairs(SEQ) do
    if t >= base + (i-1)*8 and t < base + i*8 then buttons = pad end
  end
  if t >= base + 48 and t < base + 52 then buttons = {left=true, x=true} end  -- back+HP
  if t == base + 52 then buttons = {} end
  if t >= base and t <= base + 70 then
    log(string.format("t=%03d pad=%s recs[%s] req51=%02X act=%02X", t,
      buttons and (buttons.left and "L" or "") .. (buttons.right and "R" or "") ..
      (buttons.down and "D" or "") .. (buttons.y and "Y" or "") or "-",
      states(), ram(0x1051), ram(0x1001)))
  end
  -- (b2) P2 close + repeat motion (connect test)
  if t == 200 then wr(0x10A1, 0xA0); wr(0x10A2, 0x00) end   -- P2 near
  local b2 = 205
  for i, pad in ipairs(SEQ) do
    if t >= b2 + (i-1)*8 and t < b2 + i*8 then buttons = pad end
  end
  if t >= b2 + 48 and t < b2 + 52 then buttons = {left=true, x=true} end
  if t == b2 + 52 then buttons = {} end
  if t >= b2 + 44 and t <= b2 + 130 then
    log(string.format("t=%03d CLOSE req=%02X act=%02X p2act=%02X p2hp=%d", t,
      ram(0x1051), ram(0x1001), ram(0x1081), ram(0x10C9)))
  end
  -- (b) request-nibble poke, normal HP
  if t == 260 then log("-- poke req51=0x0A (normal HP)"); wr(0x1051, 0x0A) end
  if t >= 260 and t <= 300 and t % 4 == 0 then
    log(string.format("t=%03d req51=%02X act=%02X hp=%d", t, ram(0x1051), ram(0x1001), ram(0x1049)))
  end
  -- (c) low HP + poke
  if t == 340 then log("-- poke req51=0x0A (low HP)"); wr(0x1049, 0x10); wr(0x1051, 0x0A) end
  if t >= 340 and t <= 420 and t % 4 == 0 then
    log(string.format("t=%03d req51=%02X act=%02X hp=%d", t, ram(0x1051), ram(0x1001), ram(0x1049)))
  end
  if t > 430 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)
print("desp2 loaded")
