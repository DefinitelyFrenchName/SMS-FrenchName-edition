-- probe_p11_standup.lua (patch 11): can a refilled dummy be made to stand up?
-- Phase 1: refill + poke $108F (the +0x0F latch candidate) to 0x40 during KD.
-- Phase 2: refill + force standup act 0x20 at first act==0x1E frame (vendor-style write).
-- Each phase: lethal 2LP kill with REFILL on; verdict = no 0x1F + act returns to 0.
-- Output: traces/p11_standup.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p11_standup.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end
local function stw(off, v) wr(0x1F000 + off, v) end

local phase, pt, needLoad = 1, nil, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; pt = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local saw = {}
emu.addEventCallback(function()
  if not pt then return end
  pt = pt + 1
  if pt == 5 then stw(0x26, 1); wr(0x8D, 5); stw(0x04, 0xA5) end
  if pt == 10 then
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    wr(0x10A1, (p1x + 16) % 256); wr(0x10A2, math.floor((p1x + 16) / 256))
    wr(0x10C9, 0x01)
  end
  if pt >= 24 and pt <= 25 then pulse[0] = { down = true, y = true } elseif pt == 26 then pulse[0] = nil end
  local a = ram(0x1081)
  if a == 0x1A or a == 0x19 then
    saw.kd = true
    if phase == 1 and not saw.poked then wr(0x108F, 0x40); saw.poked = true; log("P1 poked $108F=40 at t=" .. pt) end
  end
  if phase == 2 and a == 0x1E and not saw.forced then
    wr(0x1081, 0x20); wr(0x1082, 1); wr(0x1084, 0x20); wr(0x1086, 0); wr(0x1087, 0)
    saw.forced = true; log("P2 forced act 0x20 at t=" .. pt)
  end
  if a == 0x1F then saw.ko = true end
  if saw.kd and pt > 60 and a == 0x00 then saw.neutral = true end
  -- responsiveness check: after neutral, inject crouch and see act 3
  if saw.neutral and not saw.injT then saw.injT = pt end
  if saw.injT and pt >= saw.injT + 2 and pt <= saw.injT + 20 then
    wr(0x5F, 0x04)  -- endFrame write won't stick; do a real check below instead
  end
  if saw.injT and pt == saw.injT + 30 then
    log(string.format("phase %d verdict: ko=%s neutral=%s act=%02X hp=%02X",
      phase, tostring(saw.ko), tostring(saw.neutral), ram(0x1081), ram(0x10C9)))
    if phase == 1 then phase = 2; pt = nil; needLoad = true; saw = {}; pulse = {}
    else log("done"); emu.stop(0) end
  end
  if pt and pt > 400 then
    log(string.format("phase %d TIMEOUT: ko=%s kd=%s act=%02X", phase, tostring(saw.ko), tostring(saw.kd), ram(0x1081)))
    if phase == 1 then phase = 2; pt = nil; needLoad = true; saw = {}; pulse = {}
    else emu.stop(1) end
  end
end, emu.eventType.endFrame)

print("probe_p11_standup loaded")
