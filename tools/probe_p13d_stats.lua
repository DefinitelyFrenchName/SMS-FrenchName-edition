-- probe_p13d_stats.lua: CONTROLLED ACS stat measurements. Each sample reloads the
-- savestate and performs the move at identical timing => identical RNG roll; any damage
-- delta is pure stat effect. Config probe_p13d_stats_cfg.lua:
--   MEASURES = { {addr=0xXXXX|0, val=N, move="jab"|"fb"}, ... }   (addr 0 = baseline)
-- State: neptune_vs_jupiter (P1 Neptune: jab = 5LP close, fb = 214LP).
-- Output: appends traces/p13d_stats.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
dofile(ENV.TOOLS .. "probe_p13d_stats_cfg.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p13d_stats.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local mi, pt, needLoad = 1, nil, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "neptune_vs_jupiter.mss", "rb"))
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

emu.addEventCallback(function()
  if not pt then return end
  pt = pt + 1
  local M = MEASURES[mi]
  if not M then log("done"); emu.stop(0); return end
  if pt == 5 and M.addr ~= 0 then wr(M.addr, M.val) end
  if M.move == "jab" then
    if pt == 10 then
      local p1x = ram(0x1021) + 256 * ram(0x1022)
      wr(0x10A1, (p1x + 16) % 256); wr(0x10A2, math.floor((p1x + 16) / 256))
    end
    if pt >= 14 and pt <= 15 then pulse[0] = { y = true } elseif pt == 16 then pulse[0] = nil end
  else
    if pt == 14 then pulse[0] = { down = true } end
    if pt == 17 then pulse[0] = { down = true, left = true } end
    if pt == 20 then pulse[0] = { left = true, y = true } end
    if pt == 23 then pulse[0] = nil end
  end
  if pt == 100 then
    log(string.format("%s addr=%04X val=%3d -> dealt=%d",
      M.move, M.addr, M.val or 0, 0x60 - ram(0x10C9)))
    mi = mi + 1
    pt = nil; needLoad = true; pulse = {}
  end
end, emu.eventType.endFrame)
print("probe_p13d_stats loaded")
