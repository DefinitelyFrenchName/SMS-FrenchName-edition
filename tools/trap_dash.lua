-- trap_dash.lua: run the rep (2LP>2HP>66); log every write to P1 act ($1001)
-- with PC + context. Also log writes to $1004 (mirror).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local log = io.open(TRACE .. "trap_dash.txt", "w")
local loaded = false
local t = -1

local function ram(addr) return emu.read(addr, emu.memType.snesWorkRam) end

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(TRACE .. "uranus_vs_moon.mss", "rb")
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    loaded = true
    t = 0
    emu.write(0x1021, 0xE8, emu.memType.snesWorkRam)
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local PLAN = {
  [10] = { down = true },
  [60] = { down = true, y = true },
  [62] = { down = true },
  [77] = { down = true, x = true },
  [80] = { down = true },
  [81] = {},
  [83] = { right = true },
  [85] = {},
  [87] = { right = true },
  [89] = {},
}
local cur = {}
local applied = -1
emu.addEventCallback(function()
  if t >= 0 then
    for k, v in pairs(PLAN) do
      if k <= t and k > applied then cur = v; applied = k end
    end
  end
  local base = { a=false,b=false,x=false,y=false,l=false,r=false,
                 up=false,down=false,left=false,right=false,start=false,select=false }
  for k, v in pairs(cur) do base[k] = v end
  emu.setInput(base, 0, 0)
end, emu.eventType.inputPolled)

emu.addMemoryCallback(function(addr, value)
  if t >= 55 and t <= 130 then
    local st = emu.getState()
    local sp = st["cpu.sp"]
    local stk = {}
    for i = 1, 12 do stk[#stk+1] = string.format("%02X", ram(sp + i)) end
    log:write(string.format("t=%03d WRITE $%04X=%02X pc=%02X:%04X A=%04X | act=%02X stp=%02X hstop=%02X cmd=%02X,%02X stack=%s\n",
      t, addr, value, st["cpu.k"], st["cpu.pc"], st["cpu.a"],
      ram(0x1001), ram(0x1002), ram(0x1043), ram(0x105D), ram(0x105E), table.concat(stk, " ")))
    log:flush()
  end
end, emu.callbackType.write, 0x1001, 0x1001, emu.cpuType.snes, emu.memType.snesWorkRam)

emu.addMemoryCallback(function()
  if t >= 90 and t <= 96 then
    local st = emu.getState()
    local sp = st["cpu.sp"]
    local stk = {}
    for i = 1, 10 do stk[#stk+1] = string.format("%02X", ram(sp + i)) end
    log:write(string.format("t=%03d EXEC C1:0952 A=%04X X=%04X Y=%04X $0001=%02X stack=%s\n",
      t, st["cpu.a"], st["cpu.x"], st["cpu.y"], ram(0x0001), table.concat(stk, " ")))
    log:flush()
  end
end, emu.callbackType.exec, 0xC10952, 0xC10952, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  if t > 130 then log:close(); emu.stop(0) end
  t = t + 1
end, emu.eventType.endFrame)

print("trap_dash loaded")
