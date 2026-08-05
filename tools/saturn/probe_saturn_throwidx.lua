-- probe_saturn_throwidx.lua — log the INDEX the thrown-pose stub is handed.
--
-- The v0.14.7 fix replaced `lda ($0C),Y` with `tyx / lda EE_THROWLIST,X`, i.e.
-- it reads her 21-byte list at the index the THROWER's script supplies. With a
-- vanilla thrower the victim's pose comes out valid ($6F/$70/$73..). With SATURN
-- as the thrower the victim's pose is garbage ($55/$88/$B5), so the index is the
-- thing to look at: her list is only $15 bytes and the read is unbounded.
--
--   MIRROR=1 SHELL_ID=7 ROM=<build> tools/run.sh tools/saturn/probe_saturn_throwidx.lua 700
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local function num(n,d) return tonumber(os.getenv(n) or "") or d end
local SHELL=num("SHELL_ID",7); local P1CHAR=num("P1CHAR",4)
local MIRROR=os.getenv("MIRROR")=="1"
local TAG=os.getenv("TAG") or (MIRROR and "mirror" or "vanilla")
local LOG=assert(io.open(ENV.TRACE.."saturn/throwidx_"..TAG..".txt","w"))
local function log(s) LOG:write(s.."\n"); LOG:flush(); print(s) end
local MEM=emu.memType.snesMemory
local frames,step,sf=0,1,0
local pulse,hold={},false
local hits={}
local function beat(on) return (frames%7)<3 and on or {} end
local function poke() wr(0x1B40, MIRROR and SHELL or P1CHAR); wr(0x1B80, SHELL) end
emu.addEventCallback(function()
  for p=0,1 do
    local b=pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and (p==1 or MIRROR) then b.l=true; b.r=true end
    emu.setInput(b,0,p)
  end
end, emu.eventType.inputPolled)
-- the stub's entry: JSL target $F6:CC00
local function st() local ok,s=pcall(emu.getState); return ok and s or nil end
emu.addMemoryCallback(function()
  local s=st(); if not s then return end
  local y=s["cpu.y"] or -1
  local e=ram(0x0E)
  local k=string.format("victim_char=$%02X  index Y=$%04X %s", e, y,
    y>=0x15 and "  <== PAST THE END of her 21-byte list" or "")
  hits[k]=(hits[k] or 0)+1
end, emu.callbackType.exec, 0xF6CC00, 0xF6CC00, emu.cpuType.snes, MEM)
local STEPS={
  function() return frames>=900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({right=true}); return ram(0x1B10)==4 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() pulse[0]={}; return sf>240 end,
  function() poke(); hold=true; return sf>20 end,
  function() poke(); pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>120 end,
  function() pulse[0]={}; return sf>30 end,
  function() poke()
    local m=frames%14
    pulse[0]=(m<3) and {a=true} or ((m>=7 and m<10) and {start=true} or {})
    if ram(0x70)==4 and ram(0x1000)~=0 then return true end
    if sf>1500 then log("MATCH-LOAD-FAIL"); LOG:close(); emu.stop(1) end
    return false end,
  function() pulse[0]={}; return ram(0x1FA)==0x80 and sf>150 end,
  function()
    if sf<90 then pulse[0]={right=true}
    elseif sf%30<6 then pulse[0]={right=true,x=true}
    else pulse[0]={} end
    return sf>500 end,
}
emu.addEventCallback(function()
  frames=frames+1; sf=sf+1
  local fn=STEPS[step]
  if fn and fn() then step=step+1; sf=0; pulse={} end
  if not STEPS[step] then
    local ks={}
    for k,v in pairs(hits) do ks[#ks+1]=string.format("%s  x%d",k,v) end
    table.sort(ks)
    for _,l in ipairs(ks) do log("  "..l) end
    -- Verdict line for the gate. Two ways to fail, and the mirror case failed
    -- the FIRST one before v0.14.14: with Saturn as the thrower her proc ran out
    -- of the $C1 COPY, whose read was never hooked, so the substitution stub was
    -- never entered at all and the victim got a pose from 0x38 bytes past the
    -- ten-entry table.
    local worst = -1
    for k,_ in pairs(hits) do
      local y = tonumber(k:match("index Y=%$(%x+)"), 16) or 0
      if y > worst then worst = y end
    end
    if #ks == 0 then
      log("THROWIDX FAIL stub-never-entered")
    elseif worst >= 0x15 then
      log(string.format("THROWIDX FAIL index-past-list worst=$%04X", worst))
    else
      log(string.format("THROWIDX PASS entered, max index $%04X (< $15)", worst))
    end
    LOG:close(); emu.stop(0)
  end
  if frames>6000 then log("TIMEOUT "..step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
