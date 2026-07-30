-- probe_sms_charsel10.lua — validate the v0.10.0 char-select 10th slot on the
-- saturn-smoke ROM. Modes via tools/saturn/charsel_cfg.lua:
--   "vs"       P1 and P2 both navigate to slot 10 by dpad, confirm -> mirror match
--   "practice" P1 picks Moon, dummy cursor to slot 10 -> Moon vs Saturn dummy
--   "vscpu"    story select (move-t2/draw-blk3 reimpls) to slot 10 -> P1 Saturn
-- Checks: dpad reachability (nav rows), cursor translation to shell 6 on
-- confirm, flags $1F60/$1F61, flag-clear while browsing, marker OAM slot 0x7B,
-- and the in-match transform (struct id 0x1C).
-- ROM=build/saturn/SailorMoonS_saturn_v0.10.0.sfc tools/run.sh tools/saturn/probe_sms_charsel10.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = "vs"
pcall(function() MODE = dofile(ENV.TOOLS .. "saturn/charsel_cfg.lua") end)
local LOG = assert(io.open(ENV.TRACE .. "saturn/charsel10_" .. MODE .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local fails = 0

local function chk(cond, msg)
  if cond then log("PASS " .. msg) else fails = fails + 1; log("FAIL " .. msg) end
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

-- one tap (2 frames) then a 12-frame gap, retried until cursor var == want
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

local function confirmstep(pad, cur, confvar, flagaddr, tag)
  return function()
    local ph = sf % 14
    pulse[pad] = (ph < 2) and {a = true} or {}
    if ram(confvar) == 1 or sf > 200 then
      pulse[pad] = {}
      chk(ram(confvar) == 1, tag .. " confirmed")
      if cur then
        chk(ram(cur) == 6, string.format("%s cursor translated to shell 6 (=%02X)", tag, ram(cur)))
      end
      if flagaddr then
        chk(ram(flagaddr) == 1, string.format("%s flag set (=%02X)", tag, ram(flagaddr)))
      end
      return true
    end
    return false
  end
end

local function markercheck(tag)
  return function()
    local found = nil
    for slot = 0, 127 do
      local base = 0x200 + slot * 4
      if ram(base) == 0xAA and ram(base + 1) == 0xA2 then found = slot; break end
    end
    chk(found ~= nil, string.format("%s marker sprite enqueued (slot %s)",
      tag, found and string.format("0x%02X", found) or "none"))
    if found then
      log(string.format("%s marker slot 0x%02X tile=%02X attr=%02X", tag, found,
        ram(0x200 + found * 4 + 2), ram(0x200 + found * 4 + 3)))
    end
    return true
  end
end

local STEPS = { function() return frames >= 900 end }
local function add(fn) STEPS[#STEPS + 1] = fn end

if MODE == "vs" then
  add(function() pulse[0]=PL.pad_beat and {} or ((frames % 9 < 3) and {down=true} or {}); return ram(0x1B10)==1 end)
  add(function() pulse[0]=(frames % 9 < 3) and {start=true} or {}; return sf>40 end)
  add(function() return sf>300 end)
  add(function()
    chk(ram(0x1B40) == 1 and ram(0x1B80) == 1, "at charselect")
    chk(ram(0x1F60) == 0 and ram(0x1F61) == 0, "flags clear at entry")
    return true
  end)
  -- P1: 1 -down-> 9 -right-> 10, nav sanity up/down, then confirm
  add(navstep(0, "down", 0x1B40, 9))
  add(navstep(0, "right", 0x1B40, 10))
  add(markercheck("vs"))
  add(navstep(0, "up", 0x1B40, 5))       -- row-10 up -> Venus
  add(navstep(0, "down", 0x1B40, 10))    -- Venus down -> 10
  add(navstep(0, "left", 0x1B40, 9))     -- row-10 left -> Chibimoon
  add(function() chk(ram(0x1F60) == 0, "P1 flag cleared while browsing"); return true end)
  add(navstep(0, "right", 0x1B40, 10))
  add(confirmstep(0, 0x1B40, 0x1B42, 0x1F60, "P1"))
  -- P2: same trip
  add(navstep(1, "down", 0x1B80, 9))
  add(navstep(1, "right", 0x1B80, 10))
  add(confirmstep(1, 0x1B80, 0x1B82, 0x1F61, "P2"))
  add(function()  -- through VS config into the match
    pulse[0] = (sf % 20 < 3) and {start=true} or {}
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 900 then chk(false, "match load"); emu.stop(1) end
    return false
  end)
  add(function() return sf > 300 end)
  add(function()
    chk(ram(0x1000) == 0x1C, string.format("P1 in-match id 0x1C (=%02X)", ram(0x1000)))
    chk(ram(0x1080) == 0x1C, string.format("P2 in-match id 0x1C (=%02X)", ram(0x1080)))
    return true
  end)
elseif MODE == "practice" then
  add(function() pulse[0]=(frames % 9 < 3) and {down=true} or {}; return ram(0x1B10)==1 end)
  add(function() pulse[0]=(frames % 9 < 3) and {right=true} or {}; return ram(0x1B10)==4 end)
  add(function() pulse[0]=(frames % 9 < 3) and {start=true} or {}; return sf>40 end)
  add(function() return sf>300 end)
  -- P1 stays on Moon (cursor 1) and confirms -> regression: no translation
  add(confirmstep(0, nil, 0x1B42, nil, "P1(Moon)"))
  add(function()
    chk(ram(0x1B40) == 1, string.format("P1 cursor stays Moon (=%02X)", ram(0x1B40)))
    chk(ram(0x1F60) == 0, "P1 flag stays clear")
    return true
  end)
  -- dummy cursor (Y=1B80, P1 pad): to slot 10
  add(navstep(0, "down", 0x1B80, 9))
  add(navstep(0, "right", 0x1B80, 10))
  add(markercheck("practice"))
  add(confirmstep(0, 0x1B80, 0x1B82, 0x1F61, "dummy"))
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
else -- vscpu / story: slot 10 must stay UNREACHABLE (outer-senshi policy),
       -- and a normal story pick must still load its fight cleanly
  add(function() pulse[0]=(frames % 9 < 3) and {start=true} or {}; return sf>40 end)
  add(function()
    pulse[0] = (sf % 20 < 3) and {start=true} or {}
    if ram(0x1B40) ~= 0 then return sf > 60 end
    if sf > 1200 then chk(false, "reach story charselect"); emu.stop(1) end
    return false
  end)
  add(function()
    chk(ram(0x1B40) ~= 0, "at story charselect")
    log(string.format("story cursor start=%02X", ram(0x1B40)))
    return true
  end)
  add(navstep(0, "down", 0x1B40, 9))
  add(function()  -- press right repeatedly: cursor must STAY 9 (no slot 10)
    local ph = sf % 14
    pulse[0] = (ph < 2) and {right = true} or {}
    if ram(0x1B40) ~= 9 then
      chk(false, string.format("slot 10 leaked into story nav (cur=%02X)", ram(0x1B40)))
      return true
    end
    if sf > 80 then chk(true, "slot 10 unreachable in story"); pulse[0] = {}; return true end
    return false
  end)
  add(confirmstep(0, nil, 0x1B42, nil, "P1(story Chibimoon)"))
  add(function()
    chk(ram(0x1F60) == 0, "story flag stays clear")
    return true
  end)
  add(function()  -- into the story fight
    pulse[0] = (sf % 14 < 3) and {a = true}
      or ((sf % 14 >= 7 and sf % 14 < 10) and {start = true} or {})
    local ok, st = pcall(emu.getState)
    local pc = st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1
    local k = st and (st["cpu.k"] or st["snes.cpu.k"]) or -1
    if k == 0 and pc >= 0xFF00 then chk(false, "story fight crashed"); emu.stop(1) end
    if ram(0x70) == 4 and ram(0x1000) ~= 0 and ram(0x1080) ~= 0 then return true end
    if sf > 3000 then chk(false, "fight load"); emu.stop(1) end
    return false
  end)
  add(function() return sf > 300 end)
  add(function()
    chk(ram(0x1000) == 0x09, string.format("P1 in-match Chibimoon (=%02X)", ram(0x1000)))
    log(string.format("opponent id=%02X", ram(0x1080)))
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
print("probe_sms_charsel10 loaded: " .. MODE)
