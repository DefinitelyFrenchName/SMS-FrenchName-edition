-- probe_exp_cells.lua — the [SMS-33] FULL-SESSION watch on the object struct's
-- tail cells the anime-fighter line parks state in.
--
--   ROM=<clean> tools/run.sh tools/probe_exp_cells.lua 600
--   SMS_CELLS=79,7B,7C,7D,7E,7F  (default)   SMS_TAG=<name>
--   -> traces/exp_cells_<tag>.txt
--
-- WHY. `tools/census_struct_cell.py` answers "who writes this cell" statically,
-- but it cannot say WHICH OBJECT a runtime `sta $7E,Y` lands on — the engine
-- keeps players at $1000/$1080 and projectiles at $1100/$1180 through the same
-- instruction. And [SMS-33]: a WRAM freedom claim needs a watch across the FULL
-- session — boot -> title -> character select -> VS config -> match -> KO ->
-- win — because menu code runs between select and round load and has already
-- armed and disarmed flags in this project once.
--
-- So this drives a whole session from boot and reports, per cell and per PLAYER
-- SLOT: every writer PC with its phase and count, and whether a magic 0xA5
-- seeded at each phase boundary survived to the next.
--
-- CONTROLS, printed before the verdicts:
--   * positive — +0x78 (the throw interpreter's byte6 sink) and +0x46 (the
--     reaction flag) must both report writers. A watch that reports nothing
--     everywhere is broken, and a broken watch passes every cell it can no
--     longer see (trap 20/22).
--   * the phase ledger — every phase must be REACHED. An unvisited phase is
--     coverage this run does not have, and it says so rather than implying a
--     clean sweep.
--
-- ⚠ A writer PC reported here is the NEXT instruction, not the store: the
-- round-load zeroing came back as $C0:8832 / $C0:897F and the stores are the
-- `stz $1079` / `stz $10F9` three bytes earlier. Use these PCs to FIND a
-- writer, then read the ROM before writing the address down.
--
-- ⚠ Nothing here may throw inside a memory callback: an error there dies with
-- no message at all (trap 12), so `emu.getState` is wrapped in pcall and the
-- counters are bumped BEFORE the call that can throw.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local TAG = os.getenv("SMS_TAG") or "clean"
local LOG = assert(io.open(ENV.TRACE .. "exp_cells_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local CELLS = {}
for c in (os.getenv("SMS_CELLS") or "79,7A,7B,7C,7D,7E,7F"):gmatch("[^,]+") do
  CELLS[#CELLS + 1] = tonumber(c, 16)
end
local CONTROLS = { 0x78, 0x46 }
local P1, P2 = 0x1000, 0x1080
local MAGIC = 0xA5

local frames, step, sf = 0, 1, 0
local phase = "boot"
local seen = {}          -- ["7C@1000"] = { ["$C0:1234"] = {n=, phase=, frame=, val=} }
local phases = { boot = 0 }
local seeds = {}         -- ["7C@1000"] = { phase=, frame= }
local survival = {}      -- [cell] = { "boot->title: SURVIVED", ... }

local function key(cell, base) return string.format("%02X@%04X", cell, base) end
local function pcnow()
  local ok, s = pcall(emu.getState)
  if not ok or not s then return nil end
  return ((s["cpu.k"] or 0) << 16) | (s["cpu.pc"] or 0)
end

local function watch(cell, base)
  local k = key(cell, base)
  seen[k] = {}
  emu.addMemoryCallback(function(_, v)
    local t = seen[k]
    local pc = pcnow()
    local id = pc and string.format("$%06X", pc) or "(pc unavailable)"
    local e = t[id]
    if e then
      e.n = e.n + 1
      e.val = v
    else
      t[id] = { n = 1, phase = phase, frame = frames, val = v }
    end
  end, emu.callbackType.write, base + cell, base + cell, emu.cpuType.snes, emu.memType.snesWorkRam)
end

for _, cell in ipairs(CELLS) do
  watch(cell, P1); watch(cell, P2)
end
for _, cell in ipairs(CONTROLS) do
  watch(cell, P1); watch(cell, P2)
end

-- seed the magic and, on the next checkpoint, say whether it survived
local function checkpoint(name)
  for _, cell in ipairs(CELLS) do
    for _, base in ipairs({ P1, P2 }) do
      local k = key(cell, base)
      local s = seeds[k]
      if s then
        local now = PL.ram(base + cell)
        survival[k] = survival[k] or {}
        table.insert(survival[k], string.format("%s->%s: %s (read $%02X)",
          s.phase, name, now == MAGIC and "SURVIVED" or "CLOBBERED", now))
      end
      PL.wr(base + cell, MAGIC)
      seeds[k] = { phase = name, frame = frames }
    end
  end
  phase = name
  -- the phase is EVIDENCED, not asserted: $8A is the menu-state byte, $8D the
  -- mode, $1B10 the title selection, and the two act bytes say whether a match
  -- is actually running
  phases[name] = string.format("frame %d  ($8A=%02X $8D=%02X $1B10=%02X  P1 char=%02X act=%02X  P2 char=%02X act=%02X)",
    frames, PL.ram(0x8A), PL.ram(0x8D), PL.ram(0x1B10),
    PL.ram(P1), PL.ram(P1 + 1), PL.ram(P2), PL.ram(P2 + 1))
end

local function beat(on) return (frames % 7) < 3 and on or {} end
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)

local hp2, kos = nil, 0
local STEPS = {
  -- boot -> title
  function() if frames >= 900 then checkpoint("title") return true end return false end,
  function() pulse[0] = beat({ down = true }); return PL.ram(0x1B10) == 1 end,   -- 1P vs 2P
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() if sf > 240 then checkpoint("select") return true end return false end,
  -- character select: Uranus vs Jupiter, poked the way coltest does
  function() PL.wr(0x1B40, 6); PL.wr(0x1B80, 4); return sf > 20 end,
  function() pulse[0] = beat({ a = true }); return PL.ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = beat({ a = true }); return PL.ram(0x1B82) == 1 or sf > 90 end,
  function() if sf > 180 then checkpoint("config") return true end return false end,
  -- VS config screen -> the match
  function() pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
             return PL.ram(P1) ~= 0 and PL.ram(P2) ~= 0 and PL.ram(P1 + 0x01) == 0 end,
  function() if sf > 60 then checkpoint("match") return true end return false end,
  -- busy play: both fighters attack, jump, block, throw — the whole struct
  -- pipeline, not an idle round
  function()
    local k = sf % 40
    if k < 4 then pulse[0] = { x = true } elseif k < 8 then pulse[0] = { right = true }
    elseif k < 12 then pulse[0] = { up = true } elseif k < 16 then pulse[0] = { b = true }
    elseif k < 20 then pulse[0] = { down = true, y = true } else pulse[0] = {} end
    local k2 = (sf + 17) % 40
    if k2 < 4 then pulse[1] = { x = true } elseif k2 < 8 then pulse[1] = { left = true }
    elseif k2 < 12 then pulse[1] = { up = true } elseif k2 < 16 then pulse[1] = { a = true }
    else pulse[1] = {} end
    return sf > 700
  end,
  -- KO: drop P2 to a sliver and keep hitting until the round ends
  function() PL.wr(P2 + 0x49, 2); hp2 = 2; return true end,
  function()
    local k = sf % 8
    pulse[0] = (k < 3) and { right = true } or ((k < 6) and { x = true } or {})
    if PL.ram(P2 + 0x49) == 0 or PL.ram(P2 + 0x01) == 0x1F then kos = kos + 1 end
    if kos > 0 then checkpoint("ko") return true end
    return sf > 900
  end,
  function() pulse[0] = {}; pulse[1] = {}; if sf > 400 then checkpoint("win") return true end return false end,
  function() return sf > 240 end,
}

local function report()
  log("== [SMS-33] full-session cell watch (" .. TAG .. ") ==")
  log("")
  log("phase ledger (a phase with no frame was NOT reached):")
  for _, p in ipairs({ "boot", "title", "select", "config", "match", "ko", "win" }) do
    log(string.format("   %-7s %s", p, phases[p] or "NOT REACHED"))
  end
  log("")
  -- A PC that writes MOST of the watched cells is a bulk sweep (the boot clear,
  -- the round-load struct init) — it says nothing about any one cell, and
  -- counting it as a "user" of the cell would condemn every byte of the struct.
  -- What decides a cell's freedom is a writer EXCLUSIVE to it.
  local pccells = {}
  for _, cell in ipairs(CELLS) do
    for _, base in ipairs({ P1, P2 }) do
      for id in pairs(seen[key(cell, base)]) do
        pccells[id] = pccells[id] or {}
        pccells[id][cell] = true
      end
    end
  end
  local function ncells(id) local n = 0; for _ in pairs(pccells[id]) do n = n + 1 end; return n end
  local BULK = math.max(2, #CELLS - 1)      -- writes nearly every watched cell
  local bulk = {}
  for id in pairs(pccells) do if ncells(id) >= BULK then bulk[id] = true end end
  local blist = {}
  for id in pairs(bulk) do blist[#blist + 1] = id end
  table.sort(blist)
  log("bulk writers (each writes " .. BULK .. "+ of the " .. #CELLS ..
      " watched cells — boot clear / round-load struct init):")
  log("   " .. (#blist > 0 and table.concat(blist, " ") or "(none)"))
  log("")
  local ctlok = true
  for _, cell in ipairs(CONTROLS) do
    local n = 0
    for _, base in ipairs({ P1, P2 }) do
      for _ in pairs(seen[key(cell, base)]) do n = n + 1 end
    end
    log(string.format("positive control +0x%02X: %d distinct writer PCs%s",
      cell, n, n == 0 and "   <-- WATCH BROKEN" or ""))
    if n == 0 then ctlok = false end
  end
  log("")
  local verdicts = {}
  for _, cell in ipairs(CELLS) do
    log(string.format("== +0x%02X ==", cell))
    local excl = 0
    for _, base in ipairs({ P1, P2 }) do
      local k = key(cell, base)
      local pcs = {}
      for id, e in pairs(seen[k]) do pcs[#pcs + 1] = { id = id, e = e } end
      table.sort(pcs, function(a, b) return a.e.n > b.e.n end)
      for _, w in ipairs(pcs) do
        if not bulk[w.id] then
          excl = excl + 1
          log(string.format("   %s EXCLUSIVE writer %s  x%d  first in phase %s (frame %d)  last value $%02X",
            base == P1 and "P1" or "P2", w.id, w.e.n, w.e.phase, w.e.frame, w.e.val or 0))
        end
      end
      for _, s in ipairs(survival[k] or {}) do
        log(string.format("   %s magic  %s", base == P1 and "P1" or "P2", s))
      end
    end
    if excl == 0 then log("   no writer beyond the bulk sweeps, either slot, any phase") end
    verdicts[cell] = excl
  end
  log("")
  for _, cell in ipairs(CELLS) do
    log(string.format("VERDICT +0x%02X: %s", cell,
      verdicts[cell] == 0 and "FREE on both player slots for this session (bulk clears only)"
        or ("USED — " .. verdicts[cell] .. " exclusive writer PCs (see above)")))
  end
  if not ctlok then log("") log("RESULT VOID: a positive control found nothing.") end
  LOG:close()
  emu.stop(ctlok and 0 or 1)
end

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then report() end
  if frames > 6000 then
    log("TIMEOUT at step " .. step .. " phase " .. phase)
    report()
  end
end, emu.eventType.endFrame)

print("probe_exp_cells loaded: " .. TAG)
