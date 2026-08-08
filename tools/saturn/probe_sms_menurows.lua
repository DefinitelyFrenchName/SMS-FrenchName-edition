-- probe_sms_menurows.lua — establish the title-menu row -> game-mode ($7E:008D)
-- map from the game itself, and which char-select nav routine each row uses.
--
-- Why this matters: `docs/game/annotations.md` carries BOTH "0=VS, 1=Story" and "VS
-- 1P-vs-2P = 01", and the Saturn story guard is a `$8D == 1` test — so if the
-- second reading is the right one, that guard blocks 2P VS and leaves story wide
-- open, which is exactly the pair of field bugs 2 and 3.
--
-- Two independent discriminators, both read off the running game:
--   * which cursor-move routine runs — `$C0:A58E` (move-t1) serves BOTH cursors
--     in VS and practice; `$C0:A5DF` (move-t2) is the story / single-cursor one
--     with the RESTRICTED roster (its rows never lead to charID 6/7/8)
--   * which charIDs the cursor can actually reach while mashing directions
--
--   ROW=1 ROM=<rom> tools/run.sh tools/saturn/probe_sms_menurows.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram = PL.ram

local ROW = tonumber(os.getenv("ROW") or "") or 0
local LOG = assert(io.open(ENV.TRACE .. "saturn/menurow_" .. ROW .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local frames, step, sf = 0, 1, 0
local pulse = {}
local t1, t2 = 0, 0
local seen1, seen2 = {}, {}
local function beat(on) return (frames % 7) < 3 and on or {} end

for _, a in ipairs({ 0xC0A58E, 0x80A58E }) do
  emu.addMemoryCallback(function() t1 = t1 + 1 end,
    emu.callbackType.exec, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end
for _, a in ipairs({ 0xC0A5DF, 0x80A5DF }) do
  emu.addMemoryCallback(function() t2 = t2 + 1 end,
    emu.callbackType.exec, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  for p = 0, 1 do
    emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p)
  end
end, emu.eventType.inputPolled)

-- walk the cursor around with both pads and record every charID each reaches
local DIRS = { { right = true }, { down = true }, { left = true }, { up = true } }
local function roam()
  local d = DIRS[(math.floor(frames / 20) % 4) + 1]
  pulse[0] = beat(d); pulse[1] = beat(d)
  seen1[ram(0x1B40)] = true
  seen2[ram(0x1B80)] = true
end

local function setstr(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return table.concat(ks, ",")
end

local STEPS = {
  function() return frames >= 900 end,
  function()
    if ROW == 0 then return sf > 30 end
    pulse[0] = beat({ down = true }); return ram(0x1B10) == ROW
  end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function()  -- some rows put a screen (difficulty/dialogue) before char select
    local m = frames % 16
    pulse[0] = (m < 3) and { start = true } or ((m >= 8 and m < 11) and { a = true } or {})
    if ram(0x1B40) ~= 0 then return true end
    return sf > 400
  end,
  function() t1, t2 = 0, 0; roam(); return sf > 600 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("ROW %d -> $8D=%02X   move-t1(VS/practice, two cursors)=%d  " ..
      "move-t2(story, restricted roster)=%d", ROW, ram(0x8D), t1, t2))
    log("  cursor1 reached charIDs: " .. setstr(seen1))
    log("  cursor2 reached charIDs: " .. setstr(seen2))
    log(string.format("  verdict: %s roster, %s",
      (seen1[6] or seen1[7] or seen1[8]) and "FULL (outer senshi reachable)" or "RESTRICTED (no 6/7/8)",
      t2 > 0 and "single story cursor" or "two-cursor nav"))
    emu.stop(0)
  end
  if frames > 4000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_menurows loaded: row " .. ROW)
