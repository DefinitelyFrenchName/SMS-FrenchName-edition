local ROOT="/Users/koneko/Developer/SailorMoonS/tools/"; local TRACE=ROOT.."../traces/"
pcall(dofile, ROOT.."test_labels_cfg.lua")
local C0=dofile(ROOT.."training/const.lua"); local FALSE=C0.FALSE_PAD
local WRAM=emu.memType.snesWorkRam
-- ROM label id -> name (id 4 was MEATY; removed 2026-07-20)
local IDN={[1]="GC",[2]="REVERSAL",[3]="PUNISH",[5]="TECH"}
-- map Lua label text -> our set
local function luaToId(txt)
  if txt:find("GC") then return 1 elseif txt:find("REVERSAL") then return 2
  elseif txt:find("PUNISH") then return 3
  elseif txt:find("THROW TECH") then return 5 end
  return nil
end
local ctxRef
local main=dofile(ROOT.."training/main.lua")
ctxRef=main.run(ROOT,{headless=true, modules={"gamestate","input","recorder","dummy","framedata","combo","labels"},
  padSource=function(port) return SCEN and SCEN.pad(ctxRef,port) or FALSE end})
ctxRef.onFirstExec=function(ctx) local f=io.open(TRACE..SCEN.state,"rb")
  ctx.anchor.loadreq=f:read("*a"); f:close() end
local log=io.open(TRACE.."test_labels.txt","a")
local romFired, luaFired = {}, {}
table.insert(ctxRef.hooks.frame, function(ctx)
  if ctx.t==1 or ctx.t==50 or ctx.t==150 then print("HB t="..ctx.t) end
  if ctx.t>=SCEN.to+50 then log:write("TIMEOUT no stop\n"); log:close(); emu.stop(1) end
  local t=ctx.t
  if SCEN.pokes then for _,pk in ipairs(SCEN.pokes) do if t==pk[1] then emu.write(pk[2],pk[3],WRAM) end end end
  if SCEN.setup then SCEN.setup(ctx,t) end
  if t>=SCEN.from and t<=SCEN.to then
    -- ROM: which label ids are active this frame (per player)
    for p=0,1 do local id=emu.read(0x0900+p*8+5,WRAM); if id>0 and IDN[id] then romFired[IDN[id]]=true end end
    -- Lua: labels fired
    for _,f in ipairs(ctx.mod.labels.fired) do local id=luaToId(f.text); if id then luaFired[IDN[id]]=true end end
  end
  if t==SCEN.to+1 then
    local want=SCEN.expect
    local rom = romFired[want] and "yes" or "no"
    local lua = luaFired[want] and "yes" or "no"
    log:write(string.format("%s: expect=%s ROM=%s Lua=%s %s\n", SCEN.name, want, rom, lua,
      (romFired[want] and luaFired[want]) and "PASS" or "FAIL"))
    log:close(); emu.stop((romFired[want] and luaFired[want]) and 0 or 1)
  end
end)
print("test_labels loaded")
