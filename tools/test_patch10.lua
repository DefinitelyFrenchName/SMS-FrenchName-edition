-- test_patch10.lua — verify the in-ROM combo counter (patch 10). Run on a patched ROM:
--   ROM=build/SailorMoonS_FrenchName_v0.7_all5_combo.sfc tools/run.sh tools/test_patch10.lua 200
-- Checks: (1) ROM counter WRAM ($08B0) == Lua combo oracle across the infinite rep;
--         (2) digit staging renders correct tile words for poked values (single + double).
-- Writes traces/test_patch10.txt (PASS/FAIL), exits 0/1.
local ROOT="/Users/koneko/Developer/SailorMoonS/tools/"
local TRACE=ROOT.."../traces/"
local C0=dofile(ROOT.."training/const.lua"); local FALSE=C0.FALSE_PAD
local WRAM=emu.memType.snesWorkRam
local FV=115
local function plan(t) local kf={{10,{down=true}},{60,{down=true,y=true}},{62,{down=true}},{77,{down=true,x=true}},{80,{down=true}},{95,{}},{97,{right=true}},{98,{}},{99,{right=true}},{101,{}},{FV,{down=true,y=true}},{FV+2,{down=true}}}
  local b={}; for _,e in ipairs(kf) do if e[1]<=t then b=e[2] end end
  local o={}; for k,v in pairs(FALSE) do o[k]=v end; for k,v in pairs(b) do o[k]=v end; return o end
local ctxRef
local main=dofile(ROOT.."training/main.lua")
ctxRef=main.run(ROOT,{headless=true, modules={"gamestate","input","framedata","combo"},
  padSource=function(port) local t=ctxRef and ctxRef.t or -1
    if port==0 and t>=0 then return plan(t) end; return FALSE end})
ctxRef.onFirstExec=function(ctx) local f=io.open(TRACE.."uranus_vs_jupiter_v07.mss","rb")
  ctx.anchor.loadreq=f:read("*a"); f:close() end
local log=io.open(TRACE.."test_patch10.txt","w")
local fails,mism,peak=0,0,0
local phase="oracle"
local function fail(s) fails=fails+1; log:write("FAIL: "..s.."\n") end
local function pass(s) log:write("PASS: "..s.."\n") end
table.insert(ctxRef.hooks.frame, function(ctx)
  local t=ctx.t
  if phase=="oracle" then
    if t==5 then emu.write(0x1021,0xE8,WRAM) end
    if t>=60 and t<=145 then
      local rom=emu.read(0x08B0,WRAM); local lua=ctx.combo[2].active and ctx.combo[2].hits or 0
      if rom>peak then peak=rom end
      if rom~=lua then mism=mism+1 end
    end
    if t==146 then
      if mism==0 then pass("oracle: ROM counter == Lua combo across the rep (0 mismatches)")
      else fail("oracle mismatches="..mism) end
      if peak>=2 then pass("counter reached "..peak.." hits (rendered)") else fail("counter peak only "..peak) end
      -- digit staging checks: poke values, read back staged tile words next frames
      phase="digit"; ctx._dpt=t
    end
  elseif phase=="digit" then
    -- poke P2-defender hits continuously in windows; verify LEFT staging tile words.
    -- shown=0xFF forces re-stage; ttl high keeps it alive.
    local base=ctx._dpt
    local function tw(a) return emu.read(a+1,WRAM)*256+emu.read(a,WRAM) end
    local function pokeHits(v) emu.write(0x08B0,v,WRAM); emu.write(0x08B2,90,WRAM); emu.write(0x08B3,0xFF,WRAM) end
    if t>=base+1 and t<base+6 then pokeHits(3)
    elseif t==base+6 then
      if tw(0x08D3)==0x2C53 and tw(0x08D1)==0x2000 then pass("digit 3 -> ones=2C53 tens=blank (leading-zero)")
      else fail(string.format("digit 3: ones=%04X tens=%04X",tw(0x08D3),tw(0x08D1))) end
    elseif t>=base+7 and t<base+12 then pokeHits(15)
    elseif t==base+12 then
      if tw(0x08D3)==0x2C55 and tw(0x08D1)==0x2C51 then pass("digit 15 -> tens=1(2C51) ones=5(2C55)")
      else fail(string.format("digit 15: ones=%04X tens=%04X",tw(0x08D3),tw(0x08D1))) end
    elseif t>=base+13 and t<base+18 then pokeHits(7)
    elseif t==base+18 then
      if tw(0x08D3)==0x2C57 then pass("digit 7 -> ones=2C57") else fail(string.format("digit 7: ones=%04X",tw(0x08D3))) end
      log:write(string.format("patch10 test: %d failed\n",fails)); log:close(); emu.stop(fails==0 and 0 or 1)
    end
  end
end)
print("test_patch10 loaded")
