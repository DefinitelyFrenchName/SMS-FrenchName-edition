-- probe_p12_ochame.lua (patch 12, P2): hunt the native misfire. Loads the Neptune-as-P1
-- state, pokes P1 ochame ($1075) per cfg, performs 214LP repeatedly (ds_hittest plan),
-- read-watches $1075 (roll PC) and logs P1 act after each attempt (0x62 = Deep Submerge,
-- anything else = the native whiff act). Config probe_p12_ochame_cfg.lua: OCHAME (0-255).
-- Output: appends traces/p12_ochame.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
dofile(ENV.TOOLS .. "probe_p12_ochame_cfg.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p12_ochame.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
local reads = {}
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "neptune_vs_jupiter.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function()
  if t and t >= 0 then
    local st = emu.getState()
    local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
    reads[pc] = (reads[pc] or 0) + 1
  end
end, emu.callbackType.read, 0x1075, 0x1075, emu.cpuType.snes, emu.memType.snesWorkRam)

local pulse = {}
emu.addEventCallback(function()
  local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
  local p1 = {}
  for k, v in pairs(base) do p1[k] = v end
  for k, v in pairs(pulse) do p1[k] = v end
  emu.setInput(p1, 0, 0); emu.setInput(base, 0, 1)
end, emu.eventType.inputPolled)

-- 12 attempts, one every 120f: 214LP = down(3f), down-left(3f), left+LP(3f)
local attempts, acts = 0, {}
emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  if t == 5 then wr(0x1075, OCHAME); log(string.format("=== OCHAME=%02X", OCHAME)) end
  local ph = t % 120
  if ph == 20 then pulse = { down = true }
  elseif ph == 23 then pulse = { down = true, left = true }
  elseif ph == 26 then pulse = { left = true, y = true }
  elseif ph == 29 then pulse = {}
  elseif ph == 45 then
    attempts = attempts + 1
    local a = ram(0x1001)
    acts[#acts + 1] = a
    if attempts >= 12 then
      local s = ""
      for _, v in ipairs(acts) do s = s .. string.format(" %02X", v) end
      log("acts@+16f:" .. s)
      local n = 0
      for pc, c in pairs(reads) do log(string.format("  $1075 read pc=%06X x%d", pc, c)); n = n + 1; if n > 8 then break end end
      if n == 0 then log("  no $1075 reads observed") end
      log("done"); emu.stop(0)
    end
  end
end, emu.eventType.endFrame)
print("probe_p12_ochame loaded")
