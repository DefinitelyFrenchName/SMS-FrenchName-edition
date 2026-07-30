-- probe_sms_smokedbg.lua — debug the smoke ROM: after the Saturn poke, does the
-- cel resolver ($80:9FB8) run? who writes +0x05/+0x06/+0x0C? why is the script stuck?
-- ROM=build/saturn/SailorMoonS_saturn_smoke.sfc tools/run.sh tools/saturn/probe_sms_smokedbg.lua 120
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/smokedbg.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local t, needLoad = -1, true
local resolverRuns, interpRuns = 0, 0

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

-- resolver + interpreter exec counters (register bank $80, $00, $C0 mirrors)
for _, a in ipairs({ 0x809FB8, 0x009FB8, 0xC09FB8 }) do
  emu.addMemoryCallback(function() if t >= 0 then resolverRuns = resolverRuns + 1 end end,
    emu.callbackType.exec, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
for _, a in ipairs({ 0x80A05C, 0x00A05C, 0xC0A05C }) do
  emu.addMemoryCallback(function() if t >= 0 then interpRuns = interpRuns + 1 end end,
    emu.callbackType.exec, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end

-- trap the wild jump: first exec at the STP site, dump the stack for the caller
local trapped = false
for _, a in ipairs({ -1 }) do a = nil
  emu.addMemoryCallback(function()
    if trapped or t < 0 then return end
    trapped = true
    local ok2, st = pcall(emu.getState)
    local sp = st and (st["cpu.sp"] or st["snes.cpu.sp"]) or 0
    local row = {}
    for i = sp + 1, sp + 32 do row[#row + 1] = string.format("%02X", ram(i)) end
    log(string.format("t=%03d TRAP exec %06X sp=%04X stack: %s", t, a, sp, table.concat(row, " ")))
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
local lastC0, lastC1, lastE8, last80 = 0, 0, 0, 0
emu.addMemoryCallback(function(a) if t >= 61 then lastC0 = a end end,
  emu.callbackType.exec, 0xC00000, 0xC0FFFF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function(a) if t >= 61 then lastC1 = a end end,
  emu.callbackType.exec, 0xC10000, 0xC1DFFF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function(a) if t >= 61 then lastE8 = a end end,
  emu.callbackType.exec, 0xE80000, 0xE8FFFF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function(a) if t >= 61 then last80 = a end end,
  emu.callbackType.exec, 0x800000, 0x80FFFF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function(addr)
  if trapped or t < 0 then return end
  trapped = true
  local ok2, st = pcall(emu.getState)
  local sp = st and (st["cpu.sp"] or st["snes.cpu.sp"]) or 0
  local row = {}
  for i = sp + 1, sp + 24 do row[#row + 1] = string.format("%02X", ram(i)) end
  log(string.format("t=%03d EARLY trap %06X sp=%04X stack: %s", t, addr, sp, table.concat(row, " ")))
  log(string.format("last PCs: C1low=%06X E8=%06X 80=%06X", lastC1, lastE8, last80))
end, emu.callbackType.exec, 0xC1E000, 0xC1EFFF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function(addr)
  if trapped or t < 0 then return end
  trapped = true
  log(string.format("(bank40 first, no early trap) %06X", addr))
  local ok2, st = pcall(emu.getState)
  local sp = st and (st["cpu.sp"] or st["snes.cpu.sp"]) or 0
  local row = {}
  for i = sp + 1, sp + 24 do row[#row + 1] = string.format("%02X", ram(i)) end
  log(string.format("t=%03d FIRST bank-$40 exec at %06X sp=%04X stack: %s",
    t, addr, sp, table.concat(row, " ")))
end, emu.callbackType.exec, 0x400000, 0x40FFFF, emu.cpuType.snes, emu.memType.snesMemory)

-- writes to P1 pose/duration/cel-src with writer PC (both bus mirrors)
for _, base in ipairs({ 0x001005, 0x7E1005, 0x001006, 0x7E1006, 0x00100C, 0x7E100C }) do
  emu.addMemoryCallback(function(addr, value)
    if t >= 58 and t <= 80 then
      log(string.format("t=%03d W %06X <= %02X @ %s", t, base, value or -1, pcstr()))
    end
  end, emu.callbackType.write, base, base, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1000 + o, 0) end
    log("t=060 poked; resolver/interp counters reset")
    resolverRuns, interpRuns = 0, 0
  end
  if t >= 60 and t <= 80 then
    log(string.format("t=%03d p1 act=%02X pose=%02X dur06=%02X cur07=%02X cel=%02X%02X%02X 16=%02X PC=%s",
      t, ram(0x1001), ram(0x1005), ram(0x1006), ram(0x1007),
      ram(0x100E), ram(0x100D), ram(0x100C), ram(0x1016), pcstr()))
  end
  if t == 90 then
    log(string.format("resolver execs since poke: %d, interpreter execs: %d", resolverRuns, interpRuns))
    log("DONE"); emu.stop(0)
  end
end, emu.eventType.endFrame)
print("probe_sms_smokedbg loaded")
