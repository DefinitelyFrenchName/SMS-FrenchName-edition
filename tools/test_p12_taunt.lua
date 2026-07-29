-- test_p12_taunt.lua (patch 12): taunt suite. Config test_p12_taunt_cfg.lua:
--   MODE = "solo"    -> run on a patch-12 ROM (build/sms_taunt.sfc): core behavior
--   MODE = "coexist" -> run on a p11+p12 stacked ROM: chord/menu interaction phases
-- Output: traces/p12_taunt.txt; exit 0 = all pass.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
dofile(ENV.TOOLS .. "test_p12_taunt_cfg.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p12_taunt.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end
local fails = 0
local function check(name, ok, detail)
  log((ok and "PASS " or "FAIL ") .. name .. (detail and (" " .. detail) or ""))
  if not ok then fails = fails + 1 end
end

local CUR_STATE = "training_p11.mss"
local phase, pt, needLoad = 1, nil, true
local saw = {}
local pulse = {}

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. CUR_STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; pt = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local SOLO = {
  { name = "taunt-p1", state = "training_p11.mss", dur = 200,
    tick = function(pt)
      if pt >= 20 and pt <= 22 then pulse[0] = { l = true } elseif pt == 23 then pulse[0] = nil end
      local a = ram(0x1001)
      if a == 0x65 then saw.taunt = true end
      if saw.taunt and a == 0x2A then saw.embar = true end
      if saw.embar and a == 0x00 then saw.back = true end
      if ram(0x1081) ~= 0 then saw.p2moved = true end
    end,
    fin = function()
      check("p1-taunts-0x65", saw.taunt)
      check("p1-chains-embarrassed", saw.embar)
      check("p1-recovers", saw.back)
      check("p2-unaffected", not saw.p2moved)
    end },
  { name = "taunt-p2", state = "training_p11.mss", dur = 200,
    tick = function(pt)
      if pt >= 20 and pt <= 22 then pulse[1] = { l = true } elseif pt == 23 then pulse[1] = nil end
      if ram(0x1081) == 0x63 then saw.taunt = true end
      if saw.taunt and ram(0x1081) == 0x00 then saw.back = true end
    end,
    fin = function()
      check("p2-taunts-0x63", saw.taunt)
      check("p2-recovers", saw.back)
    end },
  { name = "edge-only", state = "training_p11.mss", dur = 300,
    tick = function(pt)
      if pt >= 20 and pt <= 280 then pulse[0] = { l = true } else pulse[0] = nil end
      local a = ram(0x1001)
      if a == 0x65 and not saw.inT then saw.inT = true; saw.count = (saw.count or 0) + 1 end
      if a ~= 0x65 then saw.inT = false end
    end,
    fin = function()
      check("held-L-one-taunt", saw.count == 1, string.format("count=%s", tostring(saw.count)))
    end },
  { name = "r-blocks", state = "training_p11.mss", dur = 100,
    tick = function(pt)
      if pt >= 20 and pt <= 23 then pulse[0] = { l = true, r = true } elseif pt == 24 then pulse[0] = nil end
      if ram(0x1001) == 0x65 then saw.taunt = true end
    end,
    fin = function() check("L+R-no-taunt", not saw.taunt) end },
  { name = "air-blocks", state = "training_p11.mss", dur = 120,
    tick = function(pt)
      if pt >= 20 and pt <= 24 then pulse[0] = { up = true } end
      if pt >= 28 and pt <= 30 then pulse[0] = { l = true } elseif pt == 31 then pulse[0] = nil end
      if ram(0x1001) == 0x65 then saw.taunt = true end
    end,
    fin = function() check("air-no-taunt", not saw.taunt) end },
  { name = "vulnerable", state = "training_p11.mss", dur = 260,
    tick = function(pt)
      if pt == 10 then
        local p1x = ram(0x1021) + 256 * ram(0x1022)
        wr(0x10A1, (p1x + 16) % 256); wr(0x10A2, math.floor((p1x + 16) / 256))
      end
      if pt >= 20 and pt <= 22 then pulse[0] = { l = true } elseif pt == 23 then pulse[0] = nil end
      if pt >= 40 and pt <= 42 then pulse[1] = { down = true, y = true } elseif pt == 43 then pulse[1] = nil end
      local a = ram(0x1001)
      if a == 0x65 then saw.taunt = true end
      if saw.taunt and a >= 0x10 and a <= 0x16 then saw.hit = true end
    end,
    fin = function()
      check("vuln-taunted", saw.taunt)
      check("vuln-interrupted-by-hit", saw.hit)
    end },
  { name = "chibi+pluto+vsmode", state = "pluto_vs_chibi_v07.mss", dur = 260,
    tick = function(pt)
      if pt >= 20 and pt <= 22 then pulse[1] = { l = true } elseif pt == 23 then pulse[1] = nil end
      if pt >= 160 and pt <= 162 then pulse[0] = { l = true } elseif pt == 163 then pulse[0] = nil end
      if ram(0x1081) == 0x63 then saw.chibi = true end
      if ram(0x1001) == 0x62 then saw.pluto = true end
    end,
    fin = function()
      check("chibi-0x63-in-VS", saw.chibi)
      check("pluto-0x62-in-VS", saw.pluto)
    end },
}

local COEX = {
  { name = "chord-opens-menu-no-taunt", state = "training_p11.mss", dur = 120,
    tick = function(pt)
      if pt >= 20 and pt <= 22 then pulse[0] = { l = true, r = true } elseif pt == 23 then pulse[0] = nil end
      if ram(0x1001) == 0x65 then saw.taunt = true end
      if pt == 60 then saw.menu = (ram(0x1F005) == 1) end
    end,
    fin = function()
      check("coex-menu-opened", saw.menu)
      check("coex-no-taunt", not saw.taunt)
    end },
  { name = "menu-open-L-eaten", state = "training_p11.mss", dur = 200,
    tick = function(pt)
      if pt >= 10 and pt <= 12 then pulse[0] = { l = true, r = true } elseif pt == 13 then pulse[0] = nil end
      if pt >= 60 and pt <= 63 then pulse[0] = { l = true } elseif pt == 64 then pulse[0] = nil end
      if pt > 30 and ram(0x1001) == 0x65 then saw.taunt = true end
    end,
    fin = function() check("coex-menu-eats-L", not saw.taunt) end },
  { name = "solo-L-taunts-with-p11", state = "training_p11.mss", dur = 160,
    tick = function(pt)
      if pt >= 20 and pt <= 22 then pulse[0] = { l = true } elseif pt == 23 then pulse[0] = nil end
      if ram(0x1001) == 0x65 then saw.taunt = true end
      if pt == 100 then saw.menuStayed = (ram(0x1F005) == 0) end
    end,
    fin = function()
      check("coex-L-taunts", saw.taunt)
      check("coex-menu-stays-closed", saw.menuStayed)
    end },
}

local PHASES = (MODE == "coexist") and COEX or SOLO

emu.addEventCallback(function()
  if not pt then return end
  pt = pt + 1
  local P = PHASES[phase]
  P.tick(pt)
  if pt >= P.dur then
    P.fin()
    log("--- phase done: " .. P.name .. " (" .. MODE .. ")")
    phase = phase + 1
    saw = {}; pulse = {}
    if phase > #PHASES then
      log(fails == 0 and ("ALL PASS (" .. MODE .. ")") or (fails .. " FAILURES (" .. MODE .. ")"))
      emu.stop(fails == 0 and 0 or 1)
      return
    end
    CUR_STATE = PHASES[phase].state
    needLoad = true; pt = nil
  end
end, emu.eventType.endFrame)
print("test_p12_taunt loaded " .. MODE)
