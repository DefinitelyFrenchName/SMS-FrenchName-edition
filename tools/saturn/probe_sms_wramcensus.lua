
-- probe_sms_wramcensus.lua — POST-BOOT free-WRAM census over $7F:E000-$7F:FFFF:
-- run a full session (boot->charselect->config->PvC match->KO->win) and record
-- every address written after frame 60. Reports untouched runs.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/wramcensus.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local touched = {}
local function beat(on) return (frames % 10) < 2 and on or {} end
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function(addr, value)
  if frames > 60 then touched[addr] = (touched[addr] or 0) + 1 end
end, emu.callbackType.write, 0x1E000, 0x1FFFF, emu.cpuType.snes, emu.memType.snesWorkRam)
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,          -- 1P vs CPU
  function()
    pulse[0] = (sf % 20 < 3) and {start=true} or {}
    if ram(0x1B40) ~= 0 then return sf > 60 end
    if sf > 1200 then log("NO-CHARSEL"); emu.stop(1) end
    return false
  end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>150 end,
  function()
    pulse[0] = (sf % 14 < 3) and {a=true} or ((sf % 14 >= 7 and sf % 14 < 10) and {start=true} or {})
    if ram(0x70)==4 and ram(0x1000)~=0 and ram(0x1080)~=0 then return true end
    if sf > 2500 then log("NO-FIGHT"); emu.stop(1) end
    return false
  end,
  function() return sf > 200 end,
  function() wr(0x10C9, 1); pulse[0]=beat({y=true}); return ram(0x10C9)==0 or sf>300 end,
  function() pulse[0]={}; return sf>800 end,
  function() log("session complete"); return true end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    local runs, cur = {}, nil
    for a = 0x1E000, 0x1FFFF do
      if touched[a] then
        cur = nil
      else
        if cur and a == cur[2] + 1 then cur[2] = a
        else cur = {a, a}; runs[#runs+1] = cur end
      end
    end
    local big = {}
    for _, r in ipairs(runs) do if r[2] - r[1] + 1 >= 16 then big[#big+1] = r end end
    log(string.format("untouched runs >=16B after boot: %d", #big))
    for i = 1, math.min(#big, 30) do
      log(string.format("  $7F:%04X-$7F:%04X (%d B)", big[i][1] - 0x10000, big[i][2] - 0x10000, big[i][2]-big[i][1]+1))
    end
    emu.stop(0)
  end
  if frames > 7000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("wramcensus loaded")
