-- probe_saturn_palshot.lua — screenshot Saturn in a real match on a chosen
-- palette slot, so a palette can be judged against the ACTUAL backgrounds.
--
-- The field note on the gold variant is about CONTRAST against some stages, and
-- that cannot be judged from swatches or from a sprite composed on a flat
-- backdrop: it needs the real BG layers behind her. emu.takeScreenshot() gives
-- the console surface, which is exactly that.
--
--   PALBTN=x TAG=gold ROM=<build> tools/run.sh tools/saturn/probe_saturn_palshot.lua 600
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n,d) return tonumber(os.getenv(n) or "") or d end
local SHELL=num("SHELL_ID",7)
local BTN=(os.getenv("PALBTN") or "x"):lower()
local TAG=os.getenv("TAG") or BTN
local OUT=os.getenv("SHOTDIR") or ENV.TRACE.."saturn/"
local LOG=assert(io.open(ENV.TRACE.."saturn/palshot_"..TAG..".txt","w"))
local function log(s) LOG:write(s.."\n"); LOG:flush(); print(s) end
local frames,step,sf=0,1,0
local pulse,hold,done={},false,false
local function beat(on) return (frames%7)<3 and on or {} end
local function confirm() local t={}; t[BTN]=true; return t end
local STAGE=tonumber(os.getenv("STAGE") or "")
-- $7E:1838 is the selected stage (docs/saturn: stage-name work). Poking it during
-- the load lets one palette be judged on more than one background -- which is the
-- whole question, since a DARK variant can solve contrast on a bright stage and
-- lose it on a dark one.
local function poke()
  wr(0x1B40,SHELL); wr(0x1B80,4)
  if STAGE then wr(0x1838,STAGE); wr(0x8E,STAGE) end
end
emu.addEventCallback(function()
  for p=0,1 do
    local b=pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and p==0 then b.l=true; b.r=true end
    emu.setInput(b,0,p)
  end
end, emu.eventType.inputPolled)
local function shoot()
  done=true
  if ram(0x1000)~=0x1C then log("NOT-SATURN char="..ram(0x1000)); LOG:close(); emu.stop(1) end
  local f=io.open(OUT.."palshot_"..TAG..".png","wb")
  if f then f:write(emu.takeScreenshot()); f:close() end
  log(string.format("SHOT tag=%s slot=%d char=%02X frame=%d",TAG,ram(0x1D02),ram(0x1000),frames))
end
local STEPS={
  function() return frames>=900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({right=true}); return ram(0x1B10)==4 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() pulse[0]={}; return sf>240 end,
  function() poke(); hold=true; return sf>20 end,
  function() poke(); pulse[0]=beat(confirm()); return ram(0x1B42)==1 or sf>90 end,
  function() pulse[0]={}; return sf>30 end,
  function() poke()
    local m=frames%14
    pulse[0]=(m<3) and {a=true} or ((m>=7 and m<10) and {start=true} or {})
    if ram(0x70)==4 and ram(0x1000)~=0 then return true end
    if sf>1500 then log("MATCH-LOAD-FAIL"); LOG:close(); emu.stop(1) end
    return false end,
  function() pulse[0]={}; return ram(0x1FA)==0x80 and sf>150 end,
  function() pulse[0]={}; if sf>60 then shoot(); return true end; return false end,
}
emu.addEventCallback(function()
  frames=frames+1; sf=sf+1
  local fn=STEPS[step]
  if fn and fn() then step=step+1; sf=0; pulse={} end
  if not STEPS[step] then LOG:close(); emu.stop(done and 0 or 1) end
  if frames>6000 then log("TIMEOUT "..step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
