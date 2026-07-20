-- probe_p11_ko_lr.lua: does L+R still work AFTER a KO in damage-on training?
-- Loads training_p11.mss, opens menu (L+R), 4 downs -> DAMAGE, right (ON), L+R close,
-- pokes P2 hp low, P1 jabs -> KO, waits through the KO latch, then L+R x2.
-- Logs mode/$0070/$01FA/menu/acts/hp around every step. Output: traces/p11_ko_lr.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p11_ko_lr.txt", "w"))
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local function snap(tag, t)
  log(string.format("%s t=%d mode=%02X g70=%02X g1FA=%02X menu=%02X dmg=%02X p1act=%02X p2act=%02X hp=%02X/%02X",
    tag, t, ram(0x8D), ram(0x70), ram(0x1FA), ram(0x1F005), ram(0x1F004),
    ram(0x1001), ram(0x1081), ram(0x1049), ram(0x10C9)))
end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
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

emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  -- open menu
  if t >= 10 and t <= 12 then pulse[0] = { l = true, r = true } elseif t == 13 then pulse[0] = nil end
  -- 4 downs at 12f pace -> DAMAGE row
  if t >= 50 and t < 98 then
    local ph = (t - 50) % 12
    pulse[0] = (ph < 2) and { down = true } or nil
  end
  -- right -> DAMAGE ON
  if t >= 110 and t <= 111 then pulse[0] = { right = true } elseif t == 112 then pulse[0] = nil end
  if t == 130 then snap("after-damage-on", t) end
  -- close menu
  if t >= 140 and t <= 142 then pulse[0] = { l = true, r = true } elseif t == 143 then pulse[0] = nil end
  if t == 160 then snap("menu-closed", t); wr(0x10C9, 0x02); wr(0x801, 0x02) end
  -- walk close then jab till KO
  if t >= 165 and t < 260 and ram(0x10C9) > 0 and ram(0x10C9) < 0x90 then
    local vx = ram(0x1021) + 256 * ram(0x1022)
    local dx = ram(0x10A1) + 256 * ram(0x10A2)
    local dist = math.abs(dx - vx)
    if dist > 30 then
      pulse[0] = (vx < dx) and { right = true } or { left = true }
    else
      pulse[0] = (t % 10 < 2) and { y = true } or nil
    end
  end
  if t >= 260 and t <= 500 and t % 40 == 0 then snap("post-ko-wait", t) end
  -- L+R attempt #1 after KO settle
  if t >= 520 and t <= 522 then pulse[0] = { l = true, r = true } elseif t == 523 then pulse[0] = nil end
  if t == 600 then snap("LR-after-KO-1", t) end
  -- toggle back, attempt #2
  if t >= 620 and t <= 622 then pulse[0] = { l = true, r = true } elseif t == 623 then pulse[0] = nil end
  if t == 700 then snap("LR-after-KO-2", t) end
  if t == 720 then
    local sp = io.open(TRACE .. "p11_ko_lr.png", "wb"); sp:write(emu.takeScreenshot()); sp:close()
    snap("DONE", t); emu.stop(0)
  end
end, emu.eventType.endFrame)
print("probe_p11_ko_lr loaded")
