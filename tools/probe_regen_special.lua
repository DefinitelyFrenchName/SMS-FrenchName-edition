-- probe_regen_special.lua — repro for "HP regen doesn't fire after special-move damage".
-- Loads neptune_vs_jupiter.mss, scripts one 214LP Deep Submerge (hits standing Jupiter
-- ~t=45), then idles and logs every regen gate per frame: P2 hp/maxhp/act/cls,
-- combo[2].active/freeFrames, proj slot id / alive, until MAXT.
-- Out: traces/probe_regen_special.txt
local ROOT = "/Users/koneko/Developer/SailorMoonS/tools/"
local TRACE = ROOT .. "../traces/"
local main = dofile(ROOT .. "training/main.lua")

local PLAN = {                     -- 214LP, ds_trace.lua timings
  [8]  = { down = true },
  [11] = { down = true, left = true },
  [14] = { left = true, y = true },
  [17] = {},
}
local cur, applied = {}, -1
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

local ctx = main.run(ROOT, {
  headless = true,
  modules = { "gamestate", "input", "framedata", "combo", "regen" },
  padSource = function(port)
    if port == 0 then return cur end
    return FALSE
  end,
})

ctx.onFirstExec = function(c)
  local f = io.open(TRACE .. "neptune_vs_jupiter.mss", "rb")
  c.anchor.loadreq = f:read("*a"); f:close()
end

local CLSNAME = {}
for k, v in pairs(ctx.C.CLS) do CLSNAME[v] = k end

local MAXT = 620
local log = io.open(TRACE .. "probe_regen_special.txt", "w")
local prevHp = nil

table.insert(ctx.hooks.frame, function(c)
  local t = c.t
  for k, v in pairs(PLAN) do
    if k <= t and k > applied then cur = v; applied = k end
  end
  local s = c.snap
  if not s then return end
  local p = s.p[2]
  local co = c.combo and c.combo[2] or {}
  local pid = emu.read(0x1100, emu.memType.snesWorkRam)
  local line = string.format(
    "t=%03d p2[hp=%02X max=%02X act=%02X cls=%-9s] combo[act=%s ff=%s] proj[id=%02X alive=%s hb=%02X]",
    t, p.hp, p.maxhp, p.act, CLSNAME[p.cls] or "?", tostring(co.active),
    tostring(co.freeFrames), pid, tostring(s.proj[1].alive), s.proj[1].hb)
  log:write(line .. "\n")
  if prevHp and p.hp > prevHp then
    log:write(string.format(">>> REFILL at t=%d (hp %02X -> %02X)\n", t, prevHp, p.hp))
  end
  prevHp = p.hp
  if t >= MAXT then log:close(); emu.stop(0) end
end)
print("probe_regen_special loaded")
