-- trace.lua: load VS savestate, drive scripted P1 inputs, log player structs per frame.
-- Experiment config comes from tools/trace_plan.lua:
--   PLAN: { [t]= {btn1=true,...}, ... }  (inputs applied at local frame t, held until changed)
--   P2PLAN: same for port 2 (optional)
--   LOGFROM, LOGTO: local frame range to log
--   OUT: output file name (in traces/)
--   POKES: optional { {t=, addr=, val=}, ... }
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
-- $TRACE_PLAN overrides the config path (#13). Generators used to write their plan
-- INTO the tracked tools/trace_plan.lua, so running one silently rewrote a file
-- under version control; they now write a temp file and point this at it.
dofile(os.getenv("TRACE_PLAN") or (ENV.TOOLS .. "trace_plan.lua"))

local log = assert(io.open(TRACE .. (OUT or "trace.txt"), "w"), "trace.lua: cannot open " .. (TRACE .. (OUT or "trace.txt")))
local loaded = false
local t = -1              -- local frame counter, starts when state loaded
local cur1, cur2 = {}, {}
local applied1, applied2 = nil, nil

local function ram(addr) return emu.read(addr, emu.memType.snesWorkRam) end

-- state load + frame boundary: exec at $80:8353 (joy_read; runs once/frame, before input decode)
emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(TRACE .. (STATE or "uranus_vs_moon.mss"), "rb")
    if not f then print("trace.lua: cannot open " .. (TRACE .. (STATE or "uranus_vs_moon.mss"))) emu.stop(1) return end
    local ss = f:read("*a")
    f:close()
    emu.loadSavestate(ss)
    loaded = true
    t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t >= 0 then
    for k, v in pairs(PLAN) do
      if k <= t and k > (applied1 or -1) then cur1 = v; applied1 = k end
    end
    if P2PLAN then
      for k, v in pairs(P2PLAN) do
        if k <= t and k > (applied2 or -1) then cur2 = v; applied2 = k end
      end
    end
  end
  local base = { a=false,b=false,x=false,y=false,l=false,r=false,
                 up=false,down=false,left=false,right=false,start=false,select=false }
  local in1 = {}
  for k, v in pairs(base) do in1[k] = v end
  for k, v in pairs(cur1) do in1[k] = v end
  local in2 = {}
  for k, v in pairs(base) do in2[k] = v end
  for k, v in pairs(cur2 or {}) do in2[k] = v end
  emu.setInput(in2, 0, 1)
  emu.setInput(in1, 0, 0)
end, emu.eventType.inputPolled)

if WATCH_STUB then
  emu.addMemoryCallback(function()
    local st = emu.getState()
    log:write(string.format("t=%03d STUB-EXEC act=%02X\n", t, ram(0x1001)))
  end, emu.callbackType.exec, 0xC1BE2A, 0xC1BE2A, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  if t < 0 then return end
  if POKES then
    for _, p in ipairs(POKES) do
      if p.t == t then emu.write(p.addr, p.val, emu.memType.snesWorkRam) end
    end
  end
  if t >= (LOGFROM or 0) and t <= (LOGTO or 300) then
    log:write(string.format(
      "t=%03d p1[act=%02X stp=%02X a4=%02X spr=%02X tick=%02X%02X hb=%02X hurtb=%02X cb=%02X hstop=%02X atk=%02X str=%02X in54=%02X x=%02X%02X] p2[act=%02X hurt=%02X h47=%02X hstop=%02X hp=%02X x=%02X%02X]\n",
      t,
      ram(0x1001), ram(0x1002), ram(0x1004), ram(0x1005), ram(0x1007), ram(0x1006),
      ram(0x1040), ram(0x1041), ram(0x1042), ram(0x1043), ram(0x1044), ram(0x1077), ram(0x1054),
      ram(0x1022), ram(0x1021),
      ram(0x1081), ram(0x10C6), ram(0x10C7), ram(0x10C3), ram(0x10C9),
      ram(0x10A2), ram(0x10A1)))
    local cmd = {}
    for a = 0x105B, 0x1068 do cmd[#cmd+1] = string.format("%02X", ram(a)) end
    log:write("   cmd5B-68: " .. table.concat(cmd, " ") .. "\n")
    if EXTRA then
      local ex = {}
      for a = 0x1008, 0x101F do ex[#ex+1] = string.format("%02X", ram(a)) end
      log:write("   ex08-1F: " .. table.concat(ex, " ") .. "\n")
      local ex2 = {}
      for a = 0x1045, 0x1048 do ex2[#ex2+1] = string.format("%02X", ram(a)) end
      log:write("   ex45-48: " .. table.concat(ex2, " ") .. "\n")
    end
  end
  if t > (LOGTO or 300) then
    log:close()
    if SHOT then
      local f = io.open(TRACE .. SHOT .. ".png", "wb")
      if f then f:write(emu.takeScreenshot()); f:close() end
    end
    emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("trace loaded")
