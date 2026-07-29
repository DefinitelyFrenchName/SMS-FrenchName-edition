-- probe_p13_dmg.lua (patch 13, D1): damage-apply census. Config probe_p13_dmg_cfg.lua:
--   STATE, SCEN = "melee" | "proj"
-- melee (training_p11 + $8D=5): 2LP hit, 2HP hit, blocked 2LP, blocked 2HP (chip?),
--   throw, tech'd throw (P2 mashes HK) -- all vs P2, logging every write to $10C9/$1049
--   with full PC + old->new values.
-- proj (neptune_vs_jupiter, VS): 214LP fireball hit, fireball blocked (chip?).
-- Output: appends traces/p13_dmg.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
dofile(ENV.TOOLS .. "probe_p13_dmg_cfg.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p13_dmg.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local marker = "?"
for _, a in ipairs({ 0x10C9, 0x1049 }) do
  emu.addMemoryCallback(function(addr, value)
    if t and t >= 0 then
      local st = emu.getState()
      local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
      log(string.format("  [%s] t=%d wr $%04X %02X->%02X pc=%06X D=%04X", marker, t, addr, ram(addr), value, pc, st["cpu.d"] or -1))
    end
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesWorkRam)
end

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local function p2close(gap)
  local p1x = ram(0x1021) + 256 * ram(0x1022)
  local x = p1x + (gap or 16)
  wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
end

emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  if SCEN == "melee" then
    if t == 5 then wr(0x8D, 5); log("=== melee census (mode 5) " .. STATE) end
    if t == 10 then p2close(); marker = "2LP-hit" end
    if t >= 14 and t <= 15 then pulse[0] = { down = true, y = true } elseif t == 16 then pulse[0] = nil end
    if t == 80 then p2close(); marker = "2HP-hit" end
    if t >= 84 and t <= 85 then pulse[0] = { down = true, x = true } elseif t == 86 then pulse[0] = nil end
    if t == 180 then p2close(); marker = "2LP-blocked" end
    if t >= 182 and t <= 210 then pulse[1] = { right = true, down = true } end
    if t >= 186 and t <= 187 then pulse[0] = { down = true, y = true } elseif t == 188 then pulse[0] = nil end
    if t == 211 then pulse[1] = nil end
    if t == 260 then p2close(); marker = "2HP-blocked" end
    if t >= 262 and t <= 310 then pulse[1] = { right = true, down = true } end
    if t >= 266 and t <= 267 then pulse[0] = { down = true, x = true } elseif t == 268 then pulse[0] = nil end
    if t == 311 then pulse[1] = nil end
    if t == 360 then p2close(14); marker = "throw" end
    if t >= 364 and t <= 367 then pulse[0] = { right = true, x = true } elseif t == 368 then pulse[0] = nil end
    if t == 520 then p2close(14); marker = "throw-teched" end
    if t >= 524 and t <= 527 then pulse[0] = { right = true, x = true } elseif t == 528 then pulse[0] = nil end
    if t >= 528 and t <= 580 then
      if t % 2 == 0 then pulse[1] = { a = true } else pulse[1] = nil end
    end
    if t == 581 then pulse[1] = nil end
    if t == 700 then
      log(string.format("=== melee done: p2hp=%02X p1hp=%02X", ram(0x10C9), ram(0x1049)))
      emu.stop(0)
    end
  else -- proj
    if t == 5 then log("=== projectile census (VS) " .. STATE) end
    if t == 10 then marker = "fireball-hit" end
    -- Neptune P1 214LP: down, down-left, left+LP (P1 on left faces right)
    if t == 14 then pulse[0] = { down = true } end
    if t == 17 then pulse[0] = { down = true, left = true } end
    if t == 20 then pulse[0] = { left = true, y = true } end
    if t == 23 then pulse[0] = nil end
    if t == 120 then marker = "fireball-blocked" end
    if t >= 122 and t <= 190 then pulse[1] = { right = true, down = true } end  -- P2 on right: back=right
    if t == 124 then pulse[0] = { down = true } end
    if t == 127 then pulse[0] = { down = true, left = true } end
    if t == 130 then pulse[0] = { left = true, y = true } end
    if t == 133 then pulse[0] = nil end
    if t == 191 then pulse[1] = nil end
    if t == 300 then
      log(string.format("=== proj done: p2hp=%02X", ram(0x10C9)))
      emu.stop(0)
    end
  end
end, emu.eventType.endFrame)
print("probe_p13_dmg loaded")
