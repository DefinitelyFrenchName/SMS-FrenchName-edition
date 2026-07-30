-- probe_supers_coverage.lua — measure Saturn-exclusive CODE in Super S bank $C1.
-- Collects unique exec addresses in $C1:0000-FFFF over three phases on the fixture:
--   baseline (both idle) / A: Saturn attacks (5LP,5LK,5HK,close 5HP + qcf+LP special)
--   / B: Uranus (P2) attacks (LP,LK,HK,HP + a qcf+LP attempt).
-- Saturn-exclusive = A - baseline - B. If the engine is data-driven, this should be
-- tiny (projectile/special procs at most) — the Route A code-port budget.
-- ROM=<Super S> tools/run.sh tools/probe_supers_coverage.lua 400 -> traces/supers_coverage.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "supers_coverage.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram

local t, needLoad = -1, true
local phase = "warm"
local cov = { base = {}, A = {}, B = {} }

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr)
  local ph = phase
  if ph == "base" or ph == "A" or ph == "B" then cov[ph][addr & 0xFFFF] = true end
end, emu.callbackType.exec, 0xC10000, 0xC1FFFF, emu.cpuType.snes, emu.memType.snesMemory)

-- input plans: seq of {frame, padtable, port}
local function qcf(q, btn, port)
  return { {q, {down=true}, port}, {q+1, {down=true}, port},
           {q+2, {down=true, right=true}, port}, {q+3, {down=true, right=true}, port},
           {q+4, {right=true}, port}, {q+5, {right=true}, port},
           {q+6, {right=true, [btn]=true}, port}, {q+7, {right=true, [btn]=true}, port} }
end
local PLAN = {}
local function addplan(list) for _, e in ipairs(list) do PLAN[#PLAN+1] = e end end
-- phase A: Saturn (P1, port 0): t=260 5LP, 300 5LK, 340 5HK, 380 5HP, 420 qcf+LP
for _, e in ipairs({ {260,"y"}, {300,"b"}, {340,"a"}, {380,"x"} }) do
  addplan({ {e[1], {[e[2]]=true}, 0}, {e[1]+1, {[e[2]]=true}, 0} })
end
addplan(qcf(420, "y", 0))
-- phase B: Uranus (P2, port 1): t=560 LP, 600 LK, 640 HK, 680 HP, 720 qcf+LP attempt
for _, e in ipairs({ {560,"y"}, {600,"b"}, {640,"a"}, {680,"x"} }) do
  addplan({ {e[1], {[e[2]]=true}, 1}, {e[1]+1, {[e[2]]=true}, 1} })
end
addplan({ {718, {down=true}, 1}, {719, {down=true}, 1},
          {720, {down=true, left=true}, 1}, {721, {down=true, left=true}, 1},
          {722, {left=true}, 1}, {723, {left=true}, 1},
          {724, {left=true, y=true}, 1}, {725, {left=true, y=true}, 1} })  -- P2 faces left: mirrored qcf

emu.addEventCallback(function()
  local p1, p2 = PL.pad(), PL.pad()
  for _, e in ipairs(PLAN) do
    if e[1] == t then
      if e[3] == 0 then p1 = PL.pad(e[2]) else p2 = PL.pad(e[2]) end
    end
  end
  emu.setInput(p1, 0, 0); emu.setInput(p2, 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 200 then phase = "base"
  elseif t == 250 then phase = "A"
  elseif t == 500 then phase = "idleAB"   -- gap: let everything settle
  elseif t == 548 then
    -- park P2 30px from P1 so her phase-B attacks CONNECT (hit paths -> shared)
    local px = ram(0x1021) + 256 * ram(0x1022)
    local x = px + 30
    PL.wr(0x10A1, x % 256); PL.wr(0x10A2, math.floor(x / 256))
  elseif t == 550 then phase = "B"
  elseif t == 800 then
    phase = "done"
    local nb, na, nbb = 0, 0, 0
    for _ in pairs(cov.base) do nb = nb + 1 end
    for _ in pairs(cov.A) do na = na + 1 end
    for _ in pairs(cov.B) do nbb = nbb + 1 end
    log(string.format("unique $C1 exec addrs: base=%d A(Saturn)=%d B(Uranus)=%d", nb, na, nbb))
    local excl = {}
    for a in pairs(cov.A) do
      if not cov.base[a] and not cov.B[a] then excl[#excl+1] = a end
    end
    table.sort(excl)
    log(string.format("Saturn-exclusive addrs: %d", #excl))
    -- compress to runs
    local i = 1
    while i <= #excl do
      local j = i
      while j < #excl and excl[j+1] - excl[j] <= 4 do j = j + 1 end
      log(string.format("  $C1:%04X-%04X (%d bytes)", excl[i], excl[j], excl[j] - excl[i] + 1))
      i = j + 1
    end
    log("DONE"); emu.stop(0)
  end
end, emu.eventType.endFrame)
print("probe_supers_coverage loaded")
