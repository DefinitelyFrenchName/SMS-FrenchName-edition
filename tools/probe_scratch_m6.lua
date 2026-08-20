-- probe_scratch_m6.lua — motion-state array dump: 44 taps then 66 taps (debug)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools dir")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CID = tonumber(os.getenv("SMS_CID") or "4")
local STATES = { [4]="char4_vs_uranus_clean.mss", [5]="venus_vs_jupiter_clean.mss" }
local t, loaded = -1, false
local function p1(o) return PL.ram(0x1000+o) end
local function pos(b) return PL.ram(b+0x21)+256*PL.ram(b+0x22) end
local function fwd() return pos(0x1000) < pos(0x1080) and "right" or "left" end
local function back() return pos(0x1000) < pos(0x1080) and "left" or "right" end
emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATES[CID], "rb"); if not f then print("no state"); emu.stop(1); return end
    emu.loadSavestate(f:read("*a")); f:close(); loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
local function taps(k, b, d)
  if k >= 4 and k < 9 or k >= 13 and k < 18 or k >= 22 and k < 27 then b[d] = true end
end
emu.addEventCallback(function()
  if t < 0 then return end
  local b = {}
  if t >= 80 and t < 115 then taps(t-80, b, back())
  elseif t >= 130 and t < 165 then taps(t-130, b, fwd()) end
  emu.setInput(PL.pad(b), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t < 0 then return end
  if (t >= 80 and t <= 112) or (t >= 130 and t <= 162) then
    local s = {}
    for o = 0x5B, 0x68 do s[#s+1] = string.format("%02X", p1(o)) end
    print(string.format("t=%3d %s act=%02X 51=%02X 50=%02X  [5B..68]=%s",
      t, t < 120 and "44" or "66", p1(1), p1(0x51), p1(0x50), table.concat(s, " ")))
  end
  if t > 165 then emu.stop(0) end
  t = t + 1
end, emu.eventType.endFrame)
print("scratch m6 v2 loaded")
