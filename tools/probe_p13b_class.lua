-- probe_p13b_class.lua (patch 13 v3, P1): find the special-class discriminator at the
-- damage-apply sites. Logs, at every $10C9 write: PC (site), DP $0000-$0007, and the
-- +0x44 attackID of both fighters and both projectile slots. Config probe_p13b_class_cfg:
--   STATE, SCEN = "melee" (2LP light + 2HP heavy, mode 5) | "proj" (214LP hit + chip)
--                | "desp" (attacker hp poked low, tries super motions)
-- Output: appends traces/p13b_class.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
dofile(ENV.TOOLS .. "probe_p13b_class_cfg.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p13b_class.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
local marker = "?"
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr, value)
  if t and t >= 0 then
    local st = emu.getState()
    local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
    local dp = ""
    for i = 0, 7 do dp = dp .. string.format(" %02X", ram(i)) end
    log(string.format("  [%s] t=%d pc=%06X dp=%s | a44: p1=%02X p2=%02X j1=%02X j2=%02X",
      marker, t, pc, dp, ram(0x1044), ram(0x10C4), ram(0x1144), ram(0x11C4)))
  end
end, emu.callbackType.write, 0x10C9, 0x10C9, emu.cpuType.snes, emu.memType.snesWorkRam)

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
    if t == 5 then wr(0x8D, 5); log("=== melee " .. STATE) end
    if t == 10 then p2close(); marker = "2LP" end
    if t >= 14 and t <= 15 then pulse[0] = { down = true, y = true } elseif t == 16 then pulse[0] = nil end
    if t == 80 then p2close(); marker = "2HP" end
    if t >= 84 and t <= 85 then pulse[0] = { down = true, x = true } elseif t == 86 then pulse[0] = nil end
    if t == 160 then p2close(); marker = "5HP" end
    if t >= 164 and t <= 165 then pulse[0] = { x = true } elseif t == 166 then pulse[0] = nil end
    if t == 240 then log("=== melee done"); emu.stop(0) end
  elseif SCEN == "proj" then
    if t == 5 then log("=== proj " .. STATE) end
    if t == 10 then marker = "214LP-hit" end
    if t == 14 then pulse[0] = { down = true } end
    if t == 17 then pulse[0] = { down = true, left = true } end
    if t == 20 then pulse[0] = { left = true, y = true } end
    if t == 23 then pulse[0] = nil end
    if t == 120 then marker = "214LP-chip" end
    if t >= 122 and t <= 190 then pulse[1] = { right = true, down = true } end
    if t == 124 then pulse[0] = { down = true } end
    if t == 127 then pulse[0] = { down = true, left = true } end
    if t == 130 then pulse[0] = { left = true, y = true } end
    if t == 133 then pulse[0] = nil end
    if t == 191 then pulse[1] = nil end
    if t == 260 then log("=== proj done"); emu.stop(0) end
  else -- desp: Neptune P1, hp low, try super motions
    if t == 5 then wr(0x1049, 0x10); log("=== desp " .. STATE .. " (p1 hp=0x10)") end
    if t == 8 then p2close(40) end
    -- attempt 1: 236236+P
    if t == 14 then marker = "desp-236236P" end
    for i, d in ipairs({ { down = true }, { down = true, right = true }, { right = true },
                         { down = true }, { down = true, right = true }, { right = true, y = true } }) do
      if t == 12 + i * 3 then pulse[0] = d end
    end
    if t == 31 then pulse[0] = nil end
    -- attempt 2: 2141236+P (running each 3f)
    if t == 100 then marker = "desp-2141236P" end
    for i, d in ipairs({ { down = true }, { down = true, left = true }, { left = true },
                         { down = true, left = true }, { down = true }, { down = true, right = true },
                         { right = true, y = true } }) do
      if t == 98 + i * 3 then pulse[0] = d end
    end
    if t == 120 then pulse[0] = nil end
    if t >= 122 and t <= 200 then
      if ram(0x1001) >= 0x2B then
        if not marker:find("act") then marker = marker .. string.format("-act%02X", ram(0x1001)) end
      end
    end
    if t == 280 then
      log(string.format("=== desp done p1act-history-last=%02X p2hp=%02X", ram(0x1001), ram(0x10C9)))
      emu.stop(0)
    end
  end
end, emu.eventType.endFrame)
print("probe_p13b_class loaded")
