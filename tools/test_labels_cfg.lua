-- test_labels scenario: PUNISH — P1 Uranus 2HP whiffs, P1 HP poked down during her
-- recovery (mph=2, hitbox gone) => P2 earns the in-ROM PUNISH label (id 3) and the Lua
-- oracle fires "P2 PUNISH". Run on a v0.7-family ROM + patch 10b (labels).
-- (Sampling window must overlap the label's 48f TTL — the hit lands ~t=82.)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local C0=dofile(ENV.TOOLS .. "training/const.lua"); local FALSE=C0.FALSE_PAD
local function pl1(t) local o={}; for k,v in pairs(FALSE) do o[k]=v end; if t>=60 and t<63 then o.down=true; o.x=true end; return o end
SCEN={ name="punish", state="uranus_vs_jupiter_v07.mss", expect="PUNISH", from=82, to=140,
  pokes={{5,0x1021,0x40},{6,0x10A1,0x60},{82,0x1049,0x5E}},
  pad=function(ctx,port) local t=ctx.t; if t<0 then return FALSE end; if port==0 then return pl1(t) end; return FALSE end }
