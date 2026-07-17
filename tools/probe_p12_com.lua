-- probe_p12_com.lua (patch 12, P3): does the CPU opponent's pad word ever carry L/R bits?
-- Boots to title, enters 1P-vs-COM (left column row 2), autopilots char select, then
-- watches $5E (P2=CPU held) and $5C for 0x30 bits over 900 in-match frames.
-- Output: traces/p12_com.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p12_com.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)
local function slowbeat(on) return (frames % 16) < 4 and on or {} end
local function beat(on) return (frames % 7) < 3 and on or {} end

local lrHits, watched = 0, 0
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=slowbeat({down=true}); return ram(0x1B10)==2 end,   -- left col row 3 = 1P-vs-Com
  function() pulse[0]={}; return sf>10 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() pulse[0]={}; return sf>240 end,
  function() emu.write(0x1B40, 6, emu.memType.snesWorkRam); return sf>20 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>90 end,
  function() pulse[0]={}; return sf>60 end,
  function() pulse[0]=beat({start=true}); return (ram(0x1000)~=0 and ram(0x1080)~=0 and ram(0x70)==4) or sf>600 end,
  function()  -- in-match: watch CPU pad for L/R while poking P1 around a bit
    watched = watched + 1
    if ram(0x5E) % 64 >= 16 then lrHits = lrHits + 1 end   -- bits 0x10/0x20
    if watched % 40 < 3 then pulse[0]={down=true,y=true} else pulse[0]=nil end
    if watched == 1 then log(string.format("in-match: mode=%02X f70=%02X p1=%02X p2=%02X",
      ram(0x8D), ram(0x70), ram(0x1000), ram(0x1080))) end
    return watched >= 900
  end,
  function()
    log(string.format("CPU pad L/R-bit frames: %d / %d", lrHits, watched))
    log("done"); emu.stop(0); return true
  end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if frames > 5000 then log("TIMEOUT step="..step.." 1B10="..string.format("%02X",ram(0x1B10))); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_p12_com loaded")
