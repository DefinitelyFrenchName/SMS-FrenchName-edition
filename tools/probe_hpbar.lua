-- probe_hpbar.lua — find the HP-bar display variable: dump WRAM 0x0000-0x1FFF at
-- t=40 (pristine), t=130 (damaged, idle), t=260 (regen refilled internal HP, bar stale).
-- Diff(pristine, refilled) isolates display-only state. Screenshots at each point.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local ROOT = ENV.TOOLS
local TRACE = ENV.TRACE
local C0 = dofile(ROOT .. "training/const.lua")
local FALSE = C0.FALSE_PAD
local ctxRef
local main = dofile(ROOT .. "training/main.lua")
ctxRef = main.run(ROOT, {
  headless = true,
  padSource = function(port)
    local t = ctxRef and ctxRef.t or -1
    local out = {}
    for k, v in pairs(FALSE) do out[k] = v end
    if port == 0 and t >= 60 and t < 63 then out.y = true end
    return out
  end,
})
ctxRef.onFirstExec = function(ctx)
  local f = io.open(TRACE .. "venus_vs_jupiter_clean.mss", "rb")
  if not f then print("probe_hpbar.lua: cannot open " .. (TRACE .. "venus_vs_jupiter_clean.mss")) emu.stop(1) return end
  ctx.anchor.loadreq = f:read("*a"); f:close()
end
local function dump(name)
  local f = io.open(TRACE .. "hpbar_" .. name .. ".bin", "wb")
  if not f then print("probe_hpbar.lua: cannot open " .. (TRACE .. "hpbar_" .. name .. ".bin")) emu.stop(1) return end
  local t = {}
  for a = 0, 0x1FFF do t[#t + 1] = string.char(emu.read(a, emu.memType.snesWorkRam)) end
  f:write(table.concat(t)); f:close()
end
table.insert(ctxRef.hooks.frame, function(ctx)
  if ctx.t == 5 then emu.write(0x1021, 0xE8, ctx.C.WRAM) end
  if ctx.t == 40 then dump("full") end
  if ctx.t == 130 then dump("damaged") end
  if ctx.t == 260 then dump("refilled") end
end)
table.insert(ctxRef.hooks.draw, function(ctx)
  if ctx.t == 40 or ctx.t == 130 or ctx.t == 260 then
    local shot = emu.takeScreenshot()
    local f = io.open(TRACE .. "hpbar_" .. ctx.t .. ".png", "wb")
    if not f then print("probe_hpbar.lua: cannot open " .. (TRACE .. "hpbar_" .. ctx.t .. ".png")) emu.stop(1) return end
    f:write(shot); f:close()
  end
  if ctx.t == 265 then emu.stop(0) end
end)
print("probe_hpbar loaded")
