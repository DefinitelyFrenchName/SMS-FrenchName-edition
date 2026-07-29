-- probe_combo.lua — visual check of hud_combo: run the v0.7 infinite rep, screenshot the
-- gold 2-hit counter (t=92) and the magenta 3-hit 1F counter after the meaty (t=126).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local ROOT = ENV.TOOLS
local TRACE = ENV.TRACE
local C0 = dofile(ROOT .. "training/const.lua")
local FALSE = C0.FALSE_PAD
local FV = 115
local function plan(t)
  local kf = { {10,{down=true}}, {60,{down=true,y=true}}, {62,{down=true}},
               {77,{down=true,x=true}}, {80,{down=true}},
               {95,{}}, {97,{right=true}}, {98,{}}, {99,{right=true}}, {101,{}},
               {FV,{down=true,y=true}}, {FV+2,{down=true}} }
  local best = {}
  for _, e in ipairs(kf) do if e[1] <= t then best = e[2] end end
  local out = {}
  for k, v in pairs(FALSE) do out[k] = v end
  for k, v in pairs(best) do out[k] = v end
  return out
end
local ctxRef
local main = dofile(ROOT .. "training/main.lua")
ctxRef = main.run(ROOT, {
  headless = true,
  padSource = function(port)
    local t = ctxRef and ctxRef.t or -1
    if port == 0 and t >= 0 then return plan(t) end
    return FALSE
  end,
})
ctxRef.onFirstExec = function(ctx)
  local f = io.open(TRACE .. "uranus_vs_jupiter_v07.mss", "rb")
  ctx.anchor.loadreq = f:read("*a"); f:close()
end
table.insert(ctxRef.hooks.frame, function(ctx)
  if ctx.t == 5 then emu.write(0x1021, 0xE8, ctx.C.WRAM) end
  if ctx.t == 2 then
    ctx.mod.dummy.pose = "crouch"; ctx.mod.dummy.guard = "off"; ctx.mod.dummy.wakeup = "off"
  end
  if ctx.t == 100 then ctx.mod.dummy.guard = "all" end
end)
table.insert(ctxRef.hooks.draw, function(ctx)
  if ctx.t == 92 or ctx.t == 126 then
    local shot = emu.takeScreenshot()
    local f = io.open(TRACE .. "probe_combo_" .. ctx.t .. ".png", "wb")
    f:write(shot); f:close()
  end
  if ctx.t == 130 then emu.stop(0) end
end)
print("probe_combo loaded")
