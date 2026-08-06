-- probe_p11_demo.lua (patch 11): grab demo screenshots — SHOW display live (inputs + ADV).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
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
  if t == 5 then wr(0x1F029, 1) end          -- SET_SHOW
  if t == 40 then
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    wr(0x10A1, (p1x + 16) % 256); wr(0x10A2, math.floor((p1x + 16) / 256))
  end
  if t >= 60 and t <= 61 then pulse[0] = { down = true, y = true } end
  if t >= 62 and t <= 110 then pulse[0] = { down = true } end
  if t == 111 then pulse[0] = nil end
  if t == 95 then
    local f = io.open(TRACE .. "p11_demo_show.png", "wb")
    if not f then print("probe_p11_demo.lua: cannot open " .. (TRACE .. "p11_demo_show.png")) emu.stop(1) return end
    f:write(emu.takeScreenshot()); f:close()
  end
  if t == 115 then
    local f = io.open(TRACE .. "p11_demo_adv.png", "wb")
    if not f then print("probe_p11_demo.lua: cannot open " .. (TRACE .. "p11_demo_adv.png")) emu.stop(1) return end
    f:write(emu.takeScreenshot()); f:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("demo loaded")
