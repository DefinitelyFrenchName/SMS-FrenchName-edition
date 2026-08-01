-- probe_sms_charselhidden.lua — validate the v0.11.0 HIDDEN variant (Gouki-
-- style code) on SailorMoonS_saturn_v<ver>-hidden.sfc. Modes via
-- tools/saturn/charsel_cfg.lua: "vs" or "practice".
--   vs:       no slot 10 (right-from-Chibimoon stays 9), no marker sprite;
--             P1 confirms Uranus WITH L+R held (released right after) -> P1
--             becomes Saturn; P2 confirms Jupiter without the code -> stays
--             Jupiter. Match: P1 id 0x1C, P2 id 0x04.
--   practice: P1 confirms Moon without code -> stays Moon; dummy confirmed
--             with L+R held on the P1 pad -> dummy becomes Saturn.
-- ROM=build/saturn/SailorMoonS_saturn_v0.11.0-hidden.sfc tools/run.sh tools/saturn/probe_sms_charselhidden.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = "vs"
pcall(function() MODE = dofile(ENV.TOOLS .. "saturn/charsel_cfg.lua") end)
local LOG = assert(io.open(ENV.TRACE .. "saturn/charselhidden_" .. MODE .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local fails = 0
local code = {}          -- per-pad L+R hold overlay

local function flag(a) return emu.read(a, emu.memType.snesMemory) end

for _, r in ipairs({{0x7FF100, 0x7FF103, "mem"}}) do
  emu.addMemoryCallback(function(addr, value)
    local ok, st = pcall(emu.getState)
    local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
    local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
    log(string.format("f=%d WFLAG %06X <= %02X @ %02X:%04X", frames, addr, value or -1, k, pc))
  end, emu.callbackType.write, r[1], r[2], emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addMemoryCallback(function(addr, value)
  local ok, st = pcall(emu.getState)
  local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
  local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
  log(string.format("f=%d WRAMW %05X <= %02X @ %02X:%04X", frames, addr, value or -1, k, pc))
end, emu.callbackType.write, 0x1F100, 0x1F103, emu.cpuType.snes, emu.memType.snesWorkRam)

local function chk(cond, msg)
  if cond then log("PASS " .. msg) else fails = fails + 1; log("FAIL " .. msg) end
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if code[p] then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local function navstep(pad, dir, cur, want)
  return function()
    local ph = sf % 14
    pulse[pad] = (ph < 2) and {[dir] = true} or {}
    if ram(cur) == want then pulse[pad] = {}; return true end
    if sf > 240 then
      chk(false, string.format("nav %s -> %02X (stuck at %02X)", dir, want, ram(cur)))
      pulse[pad] = {}
      return true
    end
    return false
  end
end

-- confirm with/without the L+R code; code released right after confirmation so
-- the LOAD-time L+R path can't be what sets the flag
local function confirmstep(pad, cur, confvar, withcode, flagaddr, flagwant, tag)
  return function()
    code[pad] = withcode or nil
    local ph = sf % 14
    pulse[pad] = (ph < 2) and {a = true} or {}
    if ram(confvar) == 1 or sf > 240 then
      pulse[pad] = {}
      code[pad] = nil
      chk(ram(confvar) == 1, tag .. " confirmed")
      chk(flag(flagaddr) == (flagwant == 1 and 0xA5 or flagwant),
        string.format("%s flag=%02X (want %02X)", tag, flag(flagaddr), (flagwant == 1 and 0xA5 or flagwant)))
      return true
    end
    return false
  end
end

local function nomarker(tag)
  return function()
    local found = nil
    for slot = 0, 127 do
      local base = 0x200 + slot * 4
      if ram(base) == 0xAA and ram(base + 1) == 0xA2 then found = slot; break end
    end
    chk(found == nil, string.format("%s no marker sprite (slot %s)",
      tag, found and string.format("0x%02X", found) or "none"))
    return true
  end
end

local STEPS = { function() return frames >= 900 end }
local function add(fn) STEPS[#STEPS + 1] = fn end

if MODE == "vs" then
  add(function() pulse[0]=(frames % 9 < 3) and {down=true} or {}; return ram(0x1B10)==1 end)
  add(function() pulse[0]=(frames % 9 < 3) and {start=true} or {}; return sf>40 end)
  add(function() return sf>300 end)
  add(function()
    chk(ram(0x1B40) == 1 and ram(0x1B80) == 1, "at charselect")
    return true
  end)
  add(nomarker("vs"))
  -- no slot 10: down to Chibimoon, then RIGHT must keep cursor at 9
  add(navstep(0, "down", 0x1B40, 9))
  add(function()
    local ph = sf % 14
    pulse[0] = (ph < 2) and {right = true} or {}
    if ram(0x1B40) ~= 9 then
      chk(false, string.format("slot 10 leaked into hidden build (cur=%02X)", ram(0x1B40)))
      return true
    end
    if sf > 80 then chk(true, "no navigable slot 10"); pulse[0] = {}; return true end
    return false
  end)
  -- P1 to Uranus (t1: 9 up->1, 1 up->7, 7 right? t1 row7 right=6): 1 -up-> 7 -right? use up,up,right
  add(navstep(0, "up", 0x1B40, 1))
  add(navstep(0, "up", 0x1B40, 7))
  add(navstep(0, "right", 0x1B40, 6))
  add(confirmstep(0, nil, 0x1B42, true, 0x7FF100, 1, "P1(Uranus+code)"))
  add(function()
    chk(ram(0x1B40) == 6, string.format("P1 cursor stays Uranus (=%02X)", ram(0x1B40)))
    return true
  end)
  -- P2 to Jupiter (1 left->3, 3 left->4) without code
  add(navstep(1, "left", 0x1B80, 3))
  add(navstep(1, "left", 0x1B80, 4))
  add(confirmstep(1, nil, 0x1B82, false, 0x7FF101, 0, "P2(Jupiter nocode)"))
  add(function()  -- through VS config into the match (no L+R held anywhere)
    pulse[0] = (sf % 20 < 3) and {start=true} or {}
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 900 then chk(false, "match load"); emu.stop(1) end
    return false
  end)
  add(function() return sf > 300 end)
  add(function()
    chk(ram(0x1000) == 0x1C, string.format("P1 in-match id 0x1C (=%02X)", ram(0x1000)))
    chk(ram(0x1080) == 0x04, string.format("P2 in-match Jupiter (=%02X)", ram(0x1080)))
    return true
  end)
elseif MODE == "vscpu" then
  -- 1P vs CPU: from the title, mash Start through to the char select, then
  -- confirm any character WITH the code held.
  add(function() pulse[0]=(frames % 9 < 3) and {start=true} or {}; return sf>40 end)
  add(function()
    pulse[0] = (sf % 20 < 3) and {start=true} or {}
    if ram(0x1B40) ~= 0 then return sf > 60 end
    if sf > 1200 then chk(false, "reach 1P charselect"); emu.stop(1) end
    return false
  end)
  add(function()
    chk(ram(0x1B40) ~= 0, "at 1P charselect")
    log(string.format("1P cursor=%02X 8D=%02X", ram(0x1B40), ram(0x8D)))
    return true
  end)
  add(nomarker("vscpu"))
  add(confirmstep(0, nil, 0x1B42, true, 0x7FF100, 1, "P1(1P+code)"))
  add(function()
    log(string.format("post-confirm: cur=%02X flag=%02X latch=%02X",
      ram(0x1B40), flag(0x7FF100), flag(0x7FF102)))
    return true
  end)
  add(function()  -- into the fight
    pulse[0] = (sf % 14 < 3) and {a = true}
      or ((sf % 14 >= 7 and sf % 14 < 10) and {start = true} or {})
    if sf % 60 == 0 then
      log(string.format("f=%d load: 70=%02X 1000=%02X 1080=%02X flag=%02X latch=%02X",
        frames, ram(0x70), ram(0x1000), ram(0x1080), flag(0x7FF100), flag(0x7FF102)))
    end
    if ram(0x70) == 4 and ram(0x1000) ~= 0 and ram(0x1080) ~= 0 then return true end
    if sf > 3000 then chk(false, "fight load"); emu.stop(1) end
    return false
  end)
  add(function() return sf > 300 end)
  add(function()
    chk(ram(0x1000) == 0x1C, string.format("P1 in-match id 0x1C (=%02X)", ram(0x1000)))
    log(string.format("opponent=%02X flag=%02X latch=%02X", ram(0x1080), flag(0x7FF100), flag(0x7FF102)))
    return true
  end)
else -- practice
  add(function() pulse[0]=(frames % 9 < 3) and {down=true} or {}; return ram(0x1B10)==1 end)
  add(function() pulse[0]=(frames % 9 < 3) and {right=true} or {}; return ram(0x1B10)==4 end)
  add(function() pulse[0]=(frames % 9 < 3) and {start=true} or {}; return sf>40 end)
  add(function() return sf>300 end)
  add(nomarker("practice"))
  add(confirmstep(0, nil, 0x1B42, false, 0x7FF100, 0, "P1(Moon nocode)"))
  -- dummy: move to Jupiter (1 left->3 left->4), confirm with code on the P1 pad
  add(navstep(0, "left", 0x1B80, 3))
  add(navstep(0, "left", 0x1B80, 4))
  add(confirmstep(0, nil, 0x1B82, true, 0x7FF101, 1, "dummy(Jupiter+code)"))
  add(function()  -- into the match
    pulse[0] = (sf % 14 < 3) and {a = true}
      or ((sf % 14 >= 7 and sf % 14 < 10) and {start = true} or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then chk(false, "match load"); emu.stop(1) end
    return false
  end)
  add(function() return sf > 300 end)
  add(function()
    chk(ram(0x1000) == 0x01, string.format("P1 in-match stays Moon (=%02X)", ram(0x1000)))
    chk(ram(0x1080) == 0x1C, string.format("dummy in-match id 0x1C (=%02X)", ram(0x1080)))
    return true
  end)
end

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
    emu.stop(fails == 0 and 0 or 1)
  end
  if frames > 8000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_sms_charselhidden loaded: " .. MODE)
