-- probe_p11_kd.lua (patch 11, P4+P7): wakeup backdash injection + KO flow in mode 5.
-- Phase A (mode 4): P1 sweeps P2 (2HK at 16px) -> knockdown; on P2's first actionable
--   act after KD, inject back(1f)/neutral(1f)/back(4f) -> expect act 0x26 backdash.
-- Phase B (mode 5): poke P2 hp=1, P1 2LP kills -> log every act/flag change for 400f:
--   does the round end (0x0070 change / positions reset / act 0x1F)?
-- Output: traces/p11_kd.txt (+ p11_kd_end.png)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p11_kd.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end
local function wr(a, v) emu.write(a, v, emu.memType.snesWorkRam) end

local t, needLoad = -1, true
local inj = nil
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function()
  if inj then wr(0x5E, inj[1]); wr(0x5F, inj[2]) end
end, emu.callbackType.exec, 0x808373, 0x808373, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k,v in pairs(b) do base[k]=v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local prev = {}
local function trackByte(name, addr)
  local v = ram(addr)
  if prev[name] ~= v then
    log(string.format("chg t=%d %s %s->%02X", t, name, prev[name] and string.format("%02X", prev[name]) or "--", v))
    prev[name] = v
  end
end

-- wakeup state machine (facing-aware: P2 right of P1 -> back = Right = $5F bit 01)
local kdSeen, bdPhase = false, 0
local function isKD(a) return a == 0x19 or a == 0x1A or a == 0x1E or a == 0x20 end
local function actionable(a) return a <= 0x04 or a == 0x0C or a == 0x0D end

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  trackByte("p2act", 0x1081); trackByte("p2hp", 0x10C9)
  trackByte("mode", 0x8D); trackByte("f0070", 0x70); trackByte("f01FA", 0x1FA)
  trackByte("p1act", 0x1001); trackByte("p1x", 0x1021)

  if t == 20 then
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    local x = p1x + 16
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
    log("phaseA sweep setup")
  end
  if t >= 24 and t <= 25 then pulse[0] = { a = true, down = true } end
  if t == 26 then pulse[0] = nil end

  if t > 26 and t < 200 then
    local a = ram(0x1081)
    if isKD(a) then kdSeen = true end
    if kdSeen and bdPhase == 0 and actionable(a) then
      bdPhase = 1; log(string.format("t=%d wake detected act=%02X -> inject backdash", t, a))
    end
    if bdPhase >= 1 and bdPhase <= 6 then
      if bdPhase == 2 then inj = { 0x00, 0x00 } else inj = { 0x00, 0x01 } end
      bdPhase = bdPhase + 1
    elseif bdPhase == 7 then
      inj = nil; bdPhase = 8
      log(string.format("t=%d backdash injected, act=%02X", t, ram(0x1081)))
    end
  end
  if t == 200 then
    log(string.format("VERDICT-A p2act=%02X (want 0x26 seen in chg log)", ram(0x1081)))
    -- Phase B: mode 5 KO
    wr(0x8D, 0x05); wr(0x10C9, 0x01)
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    local x = p1x + 16
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
    log("phaseB mode5, p2hp=01, kill with 2LP")
  end
  if t >= 204 and t <= 205 then pulse[0] = { y = true, down = true } end
  if t == 206 then pulse[0] = nil end
  if t == 600 then
    local f = io.open(TRACE .. "p11_kd_end.png", "wb")
    if not f then print("probe_p11_kd.lua: cannot open " .. (TRACE .. "p11_kd_end.png")) emu.stop(1) return end
    f:write(emu.takeScreenshot()); f:close()
    log(string.format("VERDICT-B mode=%02X f0070=%02X p2hp=%02X p2act=%02X p1act=%02X",
      ram(0x8D), ram(0x70), ram(0x10C9), ram(0x1081), ram(0x1001)))
    log("done"); emu.stop(0)
  end
end, emu.eventType.endFrame)

print("probe_p11_kd loaded")
