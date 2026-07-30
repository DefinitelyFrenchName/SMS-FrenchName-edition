-- probe_sms_oamdump.lua — smoke ROM: dump P1 Saturn's live OAM entries vs the
-- expected sprite records from the ported $EE blob, for one idle frame.
-- ROM=build/SailorMoonS_saturn_smoke.sfc tools/run.sh tools/probe_sms_oamdump.lua 120
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "oamdump.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, rom, wr = PL.ram, PL.rom, PL.wr

local t, needLoad = -1, true
local EE = 0x2E0000
local poseAtRender = -1
emu.addMemoryCallback(function()
  poseAtRender = ram(0x1005)
end, emu.callbackType.exec, 0x809A43, 0x809A43, emu.cpuType.snes, emu.memType.snesMemory)
local emits = {}
for _, e in ipairs({ { 0x809B17, "N" }, { 0x809BCB, "F" } }) do
  emu.addMemoryCallback(function()
    if t == 140 and #emits < 12 then
      local ok2, st = pcall(emu.getState)
      local db = "?"
      if ok2 and st then
        for k, v in pairs(st) do
          if type(k) == "string" and (k:lower():find("%.db") or k:lower() == "db") then
            db = string.format("%s=%02X", k, v)
          end
        end
      end
      emits[#emits + 1] = string.format("  emit%s cnt=%02X list=%02X%02X x=%02X%02X slotbyte=%02X%02X DB[%s]",
        e[2], ram(0x00), ram(0x13), ram(0x12), ram(0x02), ram(0x01), ram(0x99), ram(0x98), db)
    end
  end, emu.callbackType.exec, e[1], e[1], emu.cpuType.snes, emu.memType.snesMemory)
end

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
  end
  if t == 141 then
    for _, l in ipairs(emits) do log(l) end
  end
  if t == 140 then
    local pose = poseAtRender
    local listp = rom(EE + 0x8000 + 2 * pose) + 256 * rom(EE + 0x8000 + 2 * pose + 1)
    local cnt = rom(EE + listp)
    log(string.format("pose=%02X list=$EE:%04X count=%d p1 x28=%04X y2A=%04X tile0A=%02X%02X flip09=%02X",
      pose, listp, cnt, ram(0x1028) + 256 * ram(0x1029), ram(0x102A) + 256 * ram(0x102B),
      ram(0x100B), ram(0x100A), ram(0x1009)))
    for i = 0, math.min(cnt - 1, 9) do
      local r = EE + listp + 1 + 6 * i
      log(string.format("  rec%02d: %02X %02X %02X %02X %02X %02X", i,
        rom(r), rom(r + 1), rom(r + 2), rom(r + 3), rom(r + 4), rom(r + 5)))
    end
    for s = 0, 11 do
      local o = 0x0200 + 4 * s
      log(string.format("  oam%02d: x=%02X y=%02X tile=%02X attr=%02X", s,
        ram(o), ram(o + 1), ram(o + 2), ram(o + 3)))
    end
    -- P2 Jupiter reference: original chain $84:8000[4] -> bank:ptr -> pose list
    local ob = 0x048000 + 3 * 4
    local jptr = rom(ob) + 256 * rom(ob + 1)
    local jbank = rom(ob + 2)
    local jbase = (jbank - 0x80) * 0x10000   -- $8x:8000+ maps to file (x)<<16 | addr
    local jpose = ram(0x1085)
    local jlp = rom(jbase + jptr + 2 * jpose) + 256 * rom(jbase + jptr + 2 * jpose + 1)
    local jcnt = rom(jbase + jlp)
    log(string.format("P2 pose=%02X tbl=$%02X:%04X list=%04X count=%d x=%04X y=%04X flip=%02X tile0A=%02X%02X",
      jpose, jbank, jptr, jlp, jcnt, ram(0x10A8) + 256 * ram(0x10A9),
      ram(0x10AA) + 256 * ram(0x10AB), ram(0x1089), ram(0x108B), ram(0x108A)))
    for i = 0, math.min(jcnt - 1, 7) do
      local r = jbase + jlp + 1 + 6 * i
      log(string.format("  jrec%02d: %02X %02X %02X %02X %02X %02X", i,
        rom(r), rom(r + 1), rom(r + 2), rom(r + 3), rom(r + 4), rom(r + 5)))
    end
    for s = 12, 60 do
      local o = 0x0200 + 4 * s
      log(string.format("  oam%02d: x=%02X y=%02X tile=%02X attr=%02X", s,
        ram(o), ram(o + 1), ram(o + 2), ram(o + 3)))
    end
    log("DONE") end
  if t == 142 then emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_sms_oamdump loaded")
