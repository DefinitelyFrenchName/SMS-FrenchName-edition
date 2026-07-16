-- probe_boxes.lua — visual check of hud_boxes: load the training modules, Venus 5LP at
-- point blank, screenshot at the active frame + idle. traces/probe_boxes_*.png
local ROOT = "/Users/koneko/Developer/SailorMoonS/tools/"
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local C0 = dofile(ROOT .. "training/const.lua")
local ctxRef
local main = dofile(ROOT .. "training/main.lua")
ctxRef = main.run(ROOT, {
  headless = true,
  padSource = function(port)
    local t = ctxRef and ctxRef.t or -1
    local out = {}
    for k, v in pairs(C0.FALSE_PAD) do out[k] = v end
    if port == 0 and t >= 60 and t < 63 then out.y = true end
    return out
  end,
})
ctxRef.onFirstExec = function(ctx)
  local f = io.open(TRACE .. "venus_vs_jupiter_clean.mss", "rb")
  ctx.anchor.loadreq = f:read("*a"); f:close()
end
table.insert(ctxRef.hooks.frame, function(ctx)
  
end)
-- screenshots must happen AFTER the draw hooks run; take them next frame via draw hook
table.insert(ctxRef.hooks.draw, function(ctx)
  if ctx.t == 64 or ctx.t == 30 then
    local shot = emu.takeScreenshot()
    local f = io.open(TRACE .. "probe_boxes_" .. ctx.t .. ".png", "wb")
    f:write(shot); f:close()
  end
  if ctx.t == 70 then emu.stop(0) end
end)
print("probe_boxes loaded")
