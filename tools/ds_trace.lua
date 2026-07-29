-- ds_trace.lua: trace Neptune's Deep Submerge (214+P) fireball projectile.
-- Loads a Neptune-as-P1 state, scripts the 214 motion, logs BOTH Neptune (P1 $1000)
-- and her projectile slot ($1100) per frame: object id(+0x00), anim frame(+0x05),
-- hitbox idx(+0x40), origin Y(+0x25/26), X(+0x21/22), Yvel(+0x32), gravity(+0x34).
-- Config overridable via globals: STATE, BTN ('y'=LP / 'x'=HP), OUT, MAXT.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
STATE = STATE or "neptune_vs_jupiter.mss"
BTN   = BTN or "y"          -- y = LP (214LP), x = HP (214HP)
OUT   = OUT or "ds_trace.txt"
MAXT  = MAXT or 130

local log = io.open(TRACE .. OUT, "w")
local loaded, t = false, -1
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end
local function s16(lo, hi) local v = lo + 256 * hi; return v >= 32768 and v - 65536 or v end

-- 214 = down(2), down-back(1), back(4). Neptune P1 faces right -> back = left.
-- Attack pressed on the final "back" input.
local PLAN = {
  [8]  = { down = true },
  [11] = { down = true, left = true },
  [14] = { left = true, [BTN] = true },
  [17] = {},
}
local cur, applied = {}, -1

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(TRACE .. STATE, "rb"); local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss); loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t >= 0 then
    for k, v in pairs(PLAN) do
      if k <= t and k > applied then cur = v; applied = k end
    end
  end
  local base = { a=false,b=false,x=false,y=false,l=false,r=false,
                 up=false,down=false,left=false,right=false,start=false,select=false }
  local in1 = {}; for k, v in pairs(base) do in1[k] = v end
  for k, v in pairs(cur) do in1[k] = v end
  emu.setInput(in1, 0, 0)          -- port 0 = P1 (3rd arg!)
end, emu.eventType.inputPolled)

local shots = { [22]=true, [34]=true, [46]=true, [58]=true, [70]=true, [90]=true }

emu.addEventCallback(function()
  if t < 0 then return end
  if t <= MAXT then
    local pid = ram(0x1100)
    local alive = (pid ~= 0 and pid < 0x80)
    local py = ram(0x1125) + 256 * ram(0x1126)
    local px = ram(0x1121) + 256 * ram(0x1122)
    local pyv = s16(ram(0x1132), ram(0x1133))
    local pgr = s16(ram(0x1134), ram(0x1135))
    local ny = ram(0x1025) + 256 * ram(0x1026)
    log:write(string.format(
      "t=%03d  Nep[act=%02X stp=%02X spr=%02X x=%04X y=%04X]  "..
      "PROJ[%s id=%02X spr=%02X hb=%02X hub=%02X x=%04X Y=%04X Yvel=%d grav=%d]\n",
      t, ram(0x1001), ram(0x1002), ram(0x1005),
      ram(0x1021)+256*ram(0x1022), ny,
      alive and "LIVE" or "----", pid, ram(0x1105), ram(0x1140), ram(0x1141),
      px, py, pyv, pgr))
    if shots[t] then
      local f = io.open(TRACE .. "ds_shot_" .. BTN .. "_" .. t .. ".png", "wb")
      if f then f:write(emu.takeScreenshot()); f:close() end
    end
  end
  if t > MAXT then log:close(); emu.stop(0) end
  t = t + 1
end, emu.eventType.endFrame)

print("ds_trace loaded: STATE="..STATE.." BTN="..BTN)
