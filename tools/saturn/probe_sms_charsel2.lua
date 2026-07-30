-- probe_sms_charsel2.lua — map the char-select engine on vanilla SMS:
--  (a) which movement routine (C0:A58E t1 / C0:A5DF t2) runs for which cursor (Y),
--  (b) which cursor-draw routines run (A77D/A7A4/A7CB/A7F2/A819),
--  (c) DB + [$FE] pad pointer at confirm (C0:A630),
--  (d) UI behavior with cursor poked to 10 (crash check) + shadow-OAM dump.
-- ROM=<clean SMS> tools/run.sh tools/saturn/probe_sms_charsel2.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = "practice"
pcall(function() MODE = dofile(ENV.TOOLS .. "saturn/charsel_cfg.lua") end)
local LOG = assert(io.open(ENV.TRACE .. "saturn/charsel2_" .. MODE .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}

local function beat(on) return (frames % 9) < 3 and on or {} end

local seen = {}
local function once(key, msg)
  if not seen[key] then seen[key] = true; log(msg) end
end

local function st(field)
  local ok, s = pcall(emu.getState)
  return s and (s["cpu." .. field] or s["snes.cpu." .. field]) or -1
end

local watching = false
local EXECS = {
  { 0x80A58E, "move-t1(AA4D)" },
  { 0x80A5DF, "move-t2(AA75)" },
  { 0x80A77D, "draw-blk1(AA9D)" },
  { 0x80A7A4, "draw-blk2a(AAB1)" },
  { 0x80A7CB, "draw-blk3(AAC5)" },
  { 0x80A7F2, "draw-blk2b(AAB1)" },
  { 0x80A819, "draw-blk2c(AAB1)" },
  { 0x80A630, "confirm" },
}
for _, e in ipairs(EXECS) do
  local addr, name = e[1], e[2]
  emu.addMemoryCallback(function()
    if not watching then return end
    local y, db = st("y"), st("db")
    once(string.format("%s-%04X", name, y),
      string.format("f=%d EXEC %s Y=%04X DB=%02X FE=%02X%02X%02X", frames, name, y, db,
        ram(0x100), ram(0xFF), ram(0xFE)))
  end, emu.callbackType.exec, addr, addr, emu.cpuType.snes, emu.memType.snesMemory)
end

local function oamdump(tag)
  for row = 0, 15 do
    local base = 0x200 + row * 0x20
    local t = {}
    for i = 0, 0x1F do t[#t + 1] = string.format("%02X", ram(base + i)) end
    log(string.format("OAM%s %04X: %s", tag, base, table.concat(t, " ")))
  end
  local t = {}
  for i = 0, 0x1F do t[#t + 1] = string.format("%02X", ram(0x400 + i)) end
  log(string.format("OAM%s high: %s", tag, table.concat(t, " ")))
  local u = {}
  for i = 0, 0x1F do u[#u + 1] = string.format("%02X", ram(0x420 + i)) end
  log(string.format("OAM%s 420+: %s", tag, table.concat(u, " ")))
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local dirseq = { {right=true}, {up=true}, {left=true}, {down=true} }
local STEPS = {
  function() return frames >= 900 end,
  function()
    if MODE == "vscpu" then return sf > 30 end
    pulse[0]=beat({down=true}); return ram(0x1B10)==1
  end,
  function()
    if MODE == "vscpu" then return true end
    pulse[0]=beat({right=true}); return ram(0x1B10)==4
  end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function()  -- vscpu/story: mash start through intro screens until charselect cursor goes live
    if MODE == "vscpu" then
      pulse[0] = (sf % 20 < 3) and {start=true} or {}
      if ram(0x1B40) ~= 0 then return sf > 60 end
      if sf > 1200 then log("NO-CHARSEL"); emu.stop(1) end
      return false
    end
    return sf>300
  end,                       -- now at char select
  function() watching = true
             log(string.format("f=%d AT-CHARSEL p1cur=%02X p2cur=%02X mode8D=%02X",
               frames, ram(0x1B40), ram(0x1B80), ram(0x8D)))
             oamdump("-idle"); return true end,
  function()  -- P1 wanders
    pulse[0] = beat(dirseq[(math.floor(sf/30) % 4) + 1])
    if sf % 30 == 0 then log(string.format("f=%d p1cur=%02X p2cur=%02X", frames, ram(0x1B40), ram(0x1B80))) end
    return sf > 120
  end,
  function()  -- P2 wanders
    pulse[0] = {}
    pulse[1] = beat(dirseq[(math.floor(sf/30) % 4) + 1])
    if sf % 30 == 0 then log(string.format("f=%d p1cur=%02X p2cur=%02X", frames, ram(0x1B40), ram(0x1B80))) end
    return sf > 120
  end,
  function() pulse[1] = {}; oamdump("-live"); return true end,
  function()  -- P1 confirms own char
    pulse[0] = beat({a = true})
    if ram(0x1B42) == 1 then log(string.format("f=%d P1-CONFIRMED p1cur=%02X", frames, ram(0x1B40))); return true end
    return sf > 120
  end,
  function()  -- post-confirm: in practice/vscpu, P1 now drives second/dummy cursor
    pulse[0] = beat(dirseq[(math.floor(sf/30) % 4) + 1])
    if sf % 30 == 0 then log(string.format("f=%d POST p1cur=%02X p2cur=%02X conf=%02X %02X",
      frames, ram(0x1B40), ram(0x1B80), ram(0x1B42), ram(0x1B82))) end
    return sf > 120
  end,
  function() oamdump("-post"); return true end,
  function()  -- confirm the second selection too
    pulse[0] = beat({a = true})
    if sf % 30 == 0 then log(string.format("f=%d CONF2 p1cur=%02X p2cur=%02X conf=%02X %02X",
      frames, ram(0x1B40), ram(0x1B80), ram(0x1B42), ram(0x1B82))) end
    return ram(0x1B82) == 1 or sf > 150
  end,
  function() pulse[0] = {}
             log(string.format("FINAL p1cur=%02X p2cur=%02X conf=%02X %02X pc=%02X:%04X",
               ram(0x1B40), ram(0x1B80), ram(0x1B42), ram(0x1B82), st("k"), st("pc")))
             return true end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 4500 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_sms_charsel loaded")
