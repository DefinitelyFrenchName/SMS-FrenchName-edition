-- probe_p11_adv.lua (patch 11): per-frame act/hitstop timeline for a 2LP on idle dummy,
-- to calibrate the advantage approximation. Output: traces/p11_adv.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p11_adv.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

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
  if t < 0 then return end
  t = t + 1
  if t == 10 then
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    wr(0x10A1, (p1x + 16) % 256); wr(0x10A2, math.floor((p1x + 16) / 256))
  end
  if t >= 24 and t <= 25 then pulse[0] = { down = true, y = true } elseif t == 26 then pulse[0] = nil end
  if t >= 24 and t <= 90 then
    log(string.format("t=%d p1act=%02X p1stop=%02X p2act=%02X p2stop=%02X", t,
      ram(0x1001), ram(0x104D), ram(0x1081), ram(0x10CD)))
  end
  if t == 91 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_p11_adv loaded")
