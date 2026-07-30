-- probe_sms_oambuild.lua — find the OAM builder + its per-char sprite-layout data.
-- On clean SMS (uranus_vs_jupiter_f5): log writer PCs into the OAM shadow $7E:0200
-- (both bus mirrors), a few per frame, for two frames; then log ROM reads by the
-- builder once identified. First pass: writer PCs only.
-- ROM=<clean SMS> tools/run.sh tools/saturn/probe_sms_oambuild.lua 100 -> traces/oambuild.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/oambuild.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram

local t, needLoad = -1, true
local perframe = 0

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

for _, base in ipairs({ 0x000200, 0x7E0200 }) do
  emu.addMemoryCallback(function(addr, value)
    if t >= 60 and t <= 61 and perframe < 80 then
      local pc = pcstr()
      if pc ~= "80:9A14" and pc ~= "80:9A20" and pc ~= "80:9A16" and pc ~= "80:9A22" then
        perframe = perframe + 1
        log(string.format("t=%03d W %06X <= %02X @ %s", t, addr, value or -1, pc))
      end
    end
  end, emu.callbackType.write, base, base + 0x21F, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 62 then log("DONE"); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_sms_oambuild loaded")
