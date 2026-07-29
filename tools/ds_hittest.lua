-- ds_hittest.lua: Neptune (P1) throws Deep Submerge at P2; P2 holds a pose (POSE:
-- 'stand'/'crouch'). Logs projectile + P2 state/HP so we can see whether the fireball
-- connects, and at what height. Compare vanilla vs patched ROM. Config: STATE, BTN, POSE,
-- OUT, P2X (optional poke of P2 pixel-X to set distance).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
STATE = STATE or "neptune_vs_jupiter.mss"
BTN   = BTN or "y"
POSE  = POSE or "crouch"
OUT   = OUT or "ds_hit.txt"
local WRAM = emu.memType.snesWorkRam
local loaded, t = false, -1
local function ram(a) return emu.read(a, WRAM) end
local log = io.open(TRACE .. OUT, "w")

local P1PLAN = { [8]={down=true},[11]={down=true,left=true},[14]={left=true,[BTN]=true},[17]={} }
local cur, applied = {}, -1
local hp0

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(TRACE .. STATE, "rb"); local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss); loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t >= 0 then for k, v in pairs(P1PLAN) do if k <= t and k > applied then cur = v; applied = k end end end
  local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
  local in1 = {}; for k, v in pairs(base) do in1[k] = v end
  for k, v in pairs(cur) do in1[k] = v end
  local in2 = {}; for k, v in pairs(base) do in2[k] = v end
  if POSE == "crouch" then in2.down = true end
  emu.setInput(in2, 0, 1)
  emu.setInput(in1, 0, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  if P2X and t == 1 then emu.write(0x10A1, P2X, WRAM) end
  if t == 1 then hp0 = ram(0x10C9) end
  if t <= 90 then
    local pid = ram(0x1100); local alive = pid ~= 0 and pid < 0x80
    log:write(string.format(
      "t=%03d PROJ[%s hb=%02X X=%04X Y=%04X] P1x=%04X  P2[act=%02X hurt=%02X hp=%02X x=%04X]\n",
      t, alive and "LIVE" or "----", ram(0x1140),
      ram(0x1121)+256*ram(0x1122), ram(0x1125)+256*ram(0x1126),
      ram(0x1021)+256*ram(0x1022),
      ram(0x1081), ram(0x10C6), ram(0x10C9), ram(0x10A1)+256*ram(0x10A2)))
  end
  if t == 90 then
    local hp1 = ram(0x10C9)
    log:write(string.format("RESULT: P2 hp %02X->%02X  %s\n", hp0 or 0, hp1,
      (hp0 and hp1 < hp0) and "*** HIT (hp dropped) ***" or "no damage"))
    log:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("ds_hittest loaded POSE="..POSE)
