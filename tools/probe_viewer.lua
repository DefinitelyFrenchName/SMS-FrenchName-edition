-- run the REAL training hitbox viewer on the Neptune fireball; screenshot at the transition
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
pcall(dofile,ENV.TOOLS .. "probe_viewer_cfg.lua")
local ROOT=ENV.TOOLS; local TRACE=ROOT.."../traces/"
local C0=dofile(ROOT.."training/const.lua"); local FALSE=C0.FALSE_PAD
local WRAM=emu.memType.snesWorkRam
local function pl1(t) local o={}; for k,v in pairs(FALSE) do o[k]=v end
  if t==60 then o.down=true elseif t==63 then o.down=true;o.left=true
  elseif t==66 then o.left=true elseif t==68 then o.left=true;o.y=true elseif t==70 then o.y=true end
  return o end
local ctxRef
local main=dofile(ROOT.."training/main.lua")
ctxRef=main.run(ROOT,{headless=true, modules={"gamestate","input","hud","hud_panel","hud_boxes"},
  padSource=function(port) local t=ctxRef and ctxRef.t or -1; if port==0 and t>=0 then return pl1(t) end; return FALSE end})
ctxRef.onFirstExec=function(ctx) local f=io.open(TRACE.."neptune_vs_jupiter.mss","rb"); ctx.anchor.loadreq=f:read("*a"); f:close() end
table.insert(ctxRef.hooks.frame, function(ctx)
  local t=ctx.t
  if t>=1 and t<95 then emu.write(0x10A1,0x30,WRAM) end   -- whiff (P2 far) so the fireball fully flies
  if t==(SHOT_AT or 100) then local f=io.open(TRACE..(SHOT_OUT or "viewer.png"),"wb"); f:write(emu.takeScreenshot()); f:close(); emu.stop(0) end
end)
print("viewer loaded")
