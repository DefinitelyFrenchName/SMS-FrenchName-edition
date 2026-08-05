-- probe_buttonmap.lua — which BUTTON selects which byte of the per-character
-- button-map record?
--
-- The record (SMS table `$C1:169B`, Super S `$C1:16F9`) is 7 bytes of
-- move-request nibbles, and Saturn's (`02 00 04 08 06 00 0a`) differs from the
-- common one (`02 00 04 06 08 00 0a`) by exactly two SWAPPED bytes — which is a
-- candidate explanation for the field report "her two ground throws are on the
-- wrong buttons". But the record is only meaningful once you know which slot
-- each button reads, and the pad-bit layout was about to be *guessed*: `$6A`/
-- `$6B` could be the low/high halves either way round, and the two readings put
-- HP on different slots.
--
-- So measure it. `$C1:15E4` onward tests fresh-press bits and branches to one of
-- seven loaders, each of which does `lda $08+N` and falls into the +0x51 write:
--
--   $C1:1661 -> byte 6   $C1:1665 -> byte 2   $C1:1669 -> byte 3
--   $C1:166D -> byte 4   $C1:1671 -> byte 5   $C1:1675 -> byte 0
--   $C1:1679 -> byte 1
--
-- Press one button at a time in a live match and log which loader runs and what
-- lands in +0x51. This is engine code shared by every character, so it needs no
-- Saturn build — run it on ANY ROM.
--
-- RESULT (2026-08-05): **this routine never executes.** Entry hits = 0 in a live
-- match on a clean ROM, while a control hook on $C1:0000 fired 381 times — so
-- the hooks were fine and `$C1:15C4` is simply not on any live path here. Which
-- means the whole button-map record is a DEAD END for the throw question: the
-- +0x51 move-request pipeline is never written during a throw either
-- (probe_throwsrc). Saturn's odd record is real and still unexplained, but it
-- is not why her throws were on the wrong buttons — that was a separate
-- per-button table at `$C1:C84A`. Kept as the record of the dead end.
--
--   ROM=<rom> TAG=clean tools/run.sh tools/saturn/probe_buttonmap.lua 600
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram = PL.ram
local TAG = os.getenv("TAG") or "buttonmap"
local LOG = assert(io.open(ENV.TRACE .. "saturn/buttonmap_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end
local MEM = emu.memType.snesMemory

local frames, step, sf = 0, 1, 0
local pulse = {}
local function beat(on) return (frames % 7) < 3 and on or {} end

-- what is being pressed right now, for attribution
local current = "-"
local seen = {}      -- "button -> byte N (req $XX)" -> count

local LOADERS = { [0x1661] = 6, [0x1665] = 2, [0x1669] = 3,
                  [0x166D] = 4, [0x1671] = 5, [0x1675] = 0, [0x1679] = 1 }
for addr, idx in pairs(LOADERS) do
  for _, bank in ipairs({ 0x81, 0xC1 }) do          -- FastROM mirror and its twin
    emu.addMemoryCallback(function()
      -- the record byte itself lives at DP $08+idx; read it for the request value
      local v = ram(0x08 + idx)
      local k = string.format("%-10s -> record byte %d (value $%02X)", current, idx, v)
      seen[k] = (seen[k] or 0) + 1
    end, emu.callbackType.exec, (bank << 16) | addr, (bank << 16) | addr,
       emu.cpuType.snes, MEM)
  end
end

-- DIAGNOSTIC: does the routine even run, and what do its gate bytes hold? The
-- first run logged zero loader hits, which is exactly the shape of a probe that
-- is watching the wrong code — so prove the handler executes before reading
-- anything into the record layout.
local entry, gate = 0, 0
local gatevals = {}
emu.addMemoryCallback(function() entry = entry + 1 end,
  emu.callbackType.exec, 0xC115C4, 0xC115C4, emu.cpuType.snes, MEM)
emu.addMemoryCallback(function()
  gate = gate + 1
  if current ~= "-" then
    local k = string.format("%-10s $68=$%02X $6A=$%02X $6B=$%02X", current,
      ram(0x68), ram(0x6A), ram(0x6B))
    gatevals[k] = (gatevals[k] or 0) + 1
  end
end, emu.callbackType.exec, 0xC115E6, 0xC115E6, emu.cpuType.snes, MEM)

emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)

-- Y=LP, X=HP, B=LK, A=HK (HANDOFF §5, empirical). Each is pressed alone, then
-- with FORWARD held, because a throw is a direction+button and the handler
-- might route those differently.
local PRESSES = {
  { "LP (y)", { y = true } },       { "LK (b)", { b = true } },
  { "HP (x)", { x = true } },       { "HK (a)", { a = true } },
  { "6+LP", { right = true, y = true } }, { "6+LK", { right = true, b = true } },
  { "6+HP", { right = true, x = true } }, { "6+HK", { right = true, a = true } },
  { "4+HP", { left = true, x = true } },  { "4+HK", { left = true, a = true } },
  { "start", { start = true } },    { "select", { select = true } },
}
local pi = 0

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,   -- 1P vs 2P
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 150 end,
  function() pulse[0] = {}; return sf > 20 end,
  function() pulse[1] = beat({ a = true }); return ram(0x1B82) == 1 or sf > 150 end,
  function()   -- into the round
    pulse[0] = (sf % 30 < 4) and { start = true } or {}
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); LOG:close(); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return ram(0x01FA) == 0x80 and sf > 120 end,
  function()   -- press each entry in isolation, with recovery gaps
    local slot = sf // 45
    if slot >= #PRESSES then return true end
    pi = slot + 1
    local within = sf % 45
    if within < 4 then
      current = PRESSES[pi][1]; pulse[0] = PRESSES[pi][2]
    else
      current = "-"; pulse[0] = {}
    end
    return false
  end,
  function()
    local ks = {}
    for k in pairs(seen) do ks[#ks + 1] = k end
    table.sort(ks)
    log(string.format("BUTTONMAP tag=%s p1char=%d entry_hits=%d gate_hits=%d observations=%d",
      TAG, ram(0x1000), entry, gate, #ks))
    for _, k in ipairs(ks) do log("  " .. k .. "  x" .. seen[k]) end
    local gk = {}
    for k in pairs(gatevals) do gk[#gk + 1] = k end
    table.sort(gk)
    for _, k in ipairs(gk) do log("  gate " .. k .. "  x" .. gatevals[k]) end
    if #ks == 0 then
      log("VOID: no loader ever ran — the probe never pressed anything the "
        .. "handler saw. Says nothing about the record layout.")
      LOG:close(); emu.stop(2)
    end
    LOG:close(); emu.stop(0)
    return true
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then LOG:close(); emu.stop(0) end
  if frames > 8000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
