local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local ROOT=ENV.TOOLS; local TRACE=ROOT.."../traces/"
local C0=dofile(ROOT.."training/const.lua"); local FALSE=C0.FALSE_PAD
local WRAM=emu.memType.snesWorkRam; local VRAM=emu.memType.snesVideoRam
local ctxRef
local main=dofile(ROOT.."training/main.lua")
ctxRef=main.run(ROOT,{headless=true, modules={"gamestate","input","framedata","combo","regen"},
  padSource=function() return FALSE end})
ctxRef.onFirstExec=function(ctx) local f=io.open(TRACE.."uranus_vs_jupiter_v07.mss","rb"); ctx.anchor.loadreq=f:read("*a"); f:close() end
local function cw(w) return emu.read(w*2,VRAM)+emu.read(w*2+1,VRAM)*256 end
local function p2bar() local o={}; for i=18,29 do o[#o+1]=string.format("%04X",cw(0x1060+i)) end; return table.concat(o," ") end
local log=io.open(TRACE.."probe_regen.txt","w")
table.insert(ctxRef.hooks.frame, function(ctx)
  local t=ctx.t
  if t==30 then emu.write(0x10C9,0x26,WRAM) end     -- damage P2 (struct) -> bar drains red
  if t==75 then log:write("damaged: "..p2bar().." hp="..string.format("%02X",emu.read(0x10C9,WRAM)).."\n") end
  -- regen heals after 120 idle frames (~t=195); dump + shot after
  if t==210 then log:write("after regen: "..p2bar().." hp="..string.format("%02X",emu.read(0x10C9,WRAM)).."\n")
    local f=io.open(TRACE.."regen_fixed.png","wb"); f:write(emu.takeScreenshot()); f:close(); log:close(); emu.stop(0) end
end)
print("regen loaded")
