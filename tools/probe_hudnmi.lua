-- probe_hudnmi.lua — patch-10 probe R3: who CONSUMES the HUD staging block ($0806-$0815)
-- and who touches the rest of the $0800 page ($0816-$08FF)? Logs unique reader/writer PCs.
-- USE: ROM=<clean> tools/run.sh tools/probe_hudnmi.lua 60 → traces/probe_hudnmi.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local log = io.open(TRACE .. "probe_hudnmi.txt", "w")
local t, needLoad = -1, true
local consumers, others = {}, {}

local function pc()
  local ok, st = pcall(emu.getState)
  if not ok then return "?" end
  return string.format("%02X:%04X", st["cpu.k"] or 0, st["cpu.pc"] or 0)
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = io.open(TRACE .. "venus_vs_jupiter_clean.mss", "rb")
    if not f then return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr)
  if t < 0 then return end
  local k = string.format("%s R %04X", pc(), addr)
  consumers[k] = (consumers[k] or 0) + 1
end, emu.callbackType.read, 0x0806, 0x0815, emu.cpuType.snes, emu.memType.snesWorkRam)

emu.addMemoryCallback(function(addr, v)
  if t < 0 then return end
  local k = string.format("%s %s %04X", pc(), "W", addr)
  others[k] = (others[k] or 0) + 1
end, emu.callbackType.write, 0x0816, 0x08FF, emu.cpuType.snes, emu.memType.snesWorkRam)

emu.addMemoryCallback(function(addr)
  if t < 0 then return end
  local k = string.format("%s %s %04X", pc(), "R", addr)
  others[k] = (others[k] or 0) + 1
end, emu.callbackType.read, 0x0816, 0x08FF, emu.cpuType.snes, emu.memType.snesWorkRam)

emu.addEventCallback(function()
  if t < 0 then return end
  if t == 180 then
    log:write("== readers of $0806-$0815 (HUD staging consumers) ==\n")
    local keys = {}
    for k in pairs(consumers) do keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do log:write(string.format("  %s x%d\n", k, consumers[k])) end
    log:write("== accesses to $0816-$08FF ==\n")
    keys = {}
    for k in pairs(others) do keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do log:write(string.format("  %s x%d\n", k, others[k])) end
    if next(others) == nil then log:write("  (none — page tail unused)\n") end
    log:close()
    emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_hudnmi loaded")
