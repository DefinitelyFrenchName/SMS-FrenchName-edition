-- probe_sms_saturn_attacks.lua — drive Saturn's REAL proc block in SMS: for each
-- move-request nibble poked into +0x51 (bypassing the unported button-map table),
-- record which act her proc starts, the poses/hitboxes seen, and that she returns
-- to neutral (act 0/2) without wedging the engine. P2 parked far away.
-- ROM=build/saturn/SailorMoonS_saturn_smoke.sfc tools/run.sh tools/saturn/probe_sms_saturn_attacks.lua 600
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/saturn_attacks.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local t, needLoad = -1, true
local nib = 9
local acts, poses, hits = {}, {}, {}
local shotDone = false

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1000 + o, 0) end
    -- park P2 far away so nothing connects
    wr(0x10A1, 0x30); wr(0x10A2, 0x01)
  end
  if t == 120 then
    wr(0x1051, nib)
    acts, poses, hits = {}, {}, {}
  end
  if t > 120 and t <= 240 then
    local a, p, h = ram(0x1001), ram(0x1005), ram(0x1040)
    acts[a] = true; poses[p] = true
    if h ~= 0 then hits[h] = true end
    -- screenshot the far-5HK-ish active frame once
    if not shotDone and (a == 0x6E or a == 0x70) and h ~= 0 then
      shotDone = true
      local png = emu.takeScreenshot()
      local f = assert(io.open(ENV.TRACE .. "saturn/saturn_special.png", "wb"))
      f:write(png); f:close()
    end
  end
  if t >= 121 and t <= 200 then
    local ok2, st = pcall(emu.getState)
    local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
    local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
    log(string.format("t=%03d p1 act=%02X step=%02X pose=%02X dur06=%02X cur07=%02X f16=%02X f54=%02X%02X f76=%02X | proj id=%02X act=%02X f03=%02X f76=%02X",
      t, ram(0x1001), ram(0x1002), ram(0x1005), ram(0x1006), ram(0x1007),
      ram(0x1016), ram(0x1055), ram(0x1054), ram(0x1076),
      ram(0x1100), ram(0x1101), ram(0x1103), ram(0x1176)))
  end
  if t >= 121 and t <= 200 then
    log(string.format("t=%03d p1 act=%02X | s1100 id=%02X act=%02X pose=%02X x=%d | s1180 id=%02X act=%02X",
      t, ram(0x1001), ram(0x1100), ram(0x1101), ram(0x1105),
      ram(0x1121) + 256 * ram(0x1122), ram(0x1180), ram(0x1181)))
  end
  if t == 240 then
    local la, lp, lh = {}, {}, {}
    for a in pairs(acts) do la[#la + 1] = string.format("%02X", a) end
    for p in pairs(poses) do lp[#lp + 1] = string.format("%02X", p) end
    for h in pairs(hits) do lh[#lh + 1] = string.format("%02X", h) end
    table.sort(la); table.sort(lp); table.sort(lh)
    local back = ram(0x1001)
    log(string.format("req=%02X: acts[%s] poses[%s] hitidx[%s] end-act=%02X %s",
      nib, table.concat(la, " "), table.concat(lp, " "), table.concat(lh, " "),
      back, (back <= 0x03) and "OK" or "STUCK?"))
    nib = nib + 1
    if nib > 0x09 then log("DONE"); emu.stop(0) end
    needLoad = true; t = -1
  end
end, emu.eventType.endFrame)
print("probe_sms_saturn_attacks loaded")
