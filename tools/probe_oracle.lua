-- Oracle test: ROM combo counter ($08B0 = combo-on-P2) vs Lua combo module, infinite rep.
local ROOT = "/Users/koneko/Developer/SailorMoonS/tools/"
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local C0 = dofile(ROOT .. "training/const.lua")
local FALSE = C0.FALSE_PAD
local WRAM = emu.memType.snesWorkRam
local FV = 115
local function plan(t)
  local kf = { {10,{down=true}}, {60,{down=true,y=true}}, {62,{down=true}},
               {77,{down=true,x=true}}, {80,{down=true}},
               {95,{}}, {97,{right=true}}, {98,{}}, {99,{right=true}}, {101,{}},
               {FV,{down=true,y=true}}, {FV+2,{down=true}} }
  local best = {}
  for _, e in ipairs(kf) do if e[1] <= t then best = e[2] end end
  local out = {}; for k,v in pairs(FALSE) do out[k]=v end
  for k,v in pairs(best) do out[k]=v end
  return out
end
local ctxRef
local main = dofile(ROOT .. "training/main.lua")
ctxRef = main.run(ROOT, {
  headless = true,
  modules = { "gamestate", "framedata", "combo" },   -- passive observers only
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
local log = io.open(TRACE .. "probe_oracle.txt", "w")
local mism = 0
table.insert(ctxRef.hooks.frame, function(ctx)
  local t = ctx.t
  if t == 5 then emu.write(0x1021, 0xE8, WRAM) end
  if t == 2 then ctx.mod.gamestate = ctx.mod.gamestate end
  if t >= 60 and t <= 150 then
    local romHits = emu.read(0x08B0, WRAM)
    local luaHits = ctx.combo[2].active and ctx.combo[2].hits or 0
    if romHits ~= luaHits then
      mism = mism + 1
      if mism <= 12 then
        log:write(string.format("t=%d MISMATCH rom=%d lua=%d (p2act=%02X p2hp=%02X)\n",
          t, romHits, luaHits, emu.read(0x1081,WRAM), emu.read(0x10C9,WRAM)))
      end
    end
  end
  if t == 130 then local f=io.open(TRACE.."cc_oracle_shot.png","wb"); f:write(emu.takeScreenshot()); f:close() end
  if t == 150 then
    log:write(string.format("total mismatches: %d\n", mism))
    log:write(string.format("final rom_hits=%d lua_hits=%d\n",
      emu.read(0x08B0,WRAM), ctx.combo[2].active and ctx.combo[2].hits or 0))
    log:close(); emu.stop(0)
  end
end)
print("probe_oracle loaded")
