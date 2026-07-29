-- probe_p13c_desp.lua: trigger a REAL desperation (a44 >= 0x12) and verify the nerf
-- covers it. Neptune P1 at hp 0x10 in VS, tries super motions with all buttons; when a
-- hit lands, logs apply PC + attacker a44 + damage, with LV2 poked to 3.
-- Output: appends traces/p13c_desp.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p13c_desp.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "neptune_vs_jupiter.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr, value)
  if t and t >= 0 then
    local st = emu.getState()
    local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
    log(string.format("  hp->%02X pc=%06X p1act=%02X p1a44=%02X j1a44=%02X LV2=%d",
      value, pc, ram(0x1001), ram(0x1044), ram(0x1144), ram(0x1F802)))
  end
end, emu.callbackType.write, 0x10C9, 0x10C9, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

-- motion battery x buttons, one attempt per 120f; act log
local MOT = {
  { name = "236236", dirs = { {down=true},{down=true,right=true},{right=true},{down=true},{down=true,right=true},{right=true} } },
  { name = "214214", dirs = { {down=true},{down=true,left=true},{left=true},{down=true},{down=true,left=true},{left=true} } },
  { name = "632146", dirs = { {right=true},{down=true,right=true},{down=true},{down=true,left=true},{left=true},{right=true} } },
}
local BT = { "y", "x", "b", "a" }
local seen = {}
emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  if t == 2 then log("=== desperation hunt (hp 0x10, LV2=3)") end
  if t == 5 then wr(0x1049, 0x10); wr(0x1F802, 3) end
  local slot = math.floor((t - 10) / 120)
  local ph = (t - 10) % 120
  local mi = math.floor(slot / #BT) + 1
  local bi = (slot % #BT) + 1
  local m = MOT[mi]
  if not m then
    local s = ""
    for a in pairs(seen) do s = s .. string.format(" %02X", a) end
    log("acts seen:" .. s); log("done"); emu.stop(0); return
  end
  if ph == 0 then wr(0x1049, 0x10); wr(0x10C9, 0x60) end
  local sd = math.floor(ph / 3) + 1
  if ph >= 3 and sd <= #m.dirs + 1 then
    if sd <= #m.dirs then pulse[0] = m.dirs[sd]
    else
      local p = {}
      for k, v in pairs(m.dirs[#m.dirs]) do p[k] = v end
      p[BT[bi]] = true
      pulse[0] = p
    end
  elseif sd == #m.dirs + 2 then pulse[0] = {}
  end
  local a = ram(0x1001)
  if a >= 0x2B then
    if not seen[a] then
      seen[a] = true
      log(string.format("  act %02X (motion %s+%s) a44=%02X", a, m.name, BT[bi], ram(0x1044)))
    end
  end
end, emu.eventType.endFrame)
print("probe_p13c_desp loaded")
