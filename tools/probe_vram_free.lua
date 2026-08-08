-- probe_vram_free.lua — prove that a VRAM tile range is genuinely unused, rather
-- than merely unused in the captures we happen to have.
--
-- Patch 16 wants to author a half-width alphabet into VRAM tiles $5C0-$5FF, the
-- 64-tile run immediately above the menu font block ($500-$5B5). A census over
-- all 192 menu captures found it blank in every one — but that is EVIDENCE, not
-- proof: the captures only cover the screens the survey visited. This project has
-- already been burned once by a region that passed "nothing points at it" and was
-- still live (the ARAM candidate in docs/project/saturn/memory_and_shell.md), so the same
-- question gets asked properly here.
--
-- Two mechanisms, because either alone can lie:
--   * a WRITE WATCH on the byte range, logging the writer PC. Catches CPU stores
--     and PPU-port writes.
--   * periodic SNAPSHOTS of the range. Catches anything the callback misses —
--     notably DMA, which is how this console moves most graphics and which may
--     not surface as a CPU write at all. If the watch says nothing and a snapshot
--     goes non-zero, the watch is what is wrong.
--
-- The session must be a FULL one — boot, title, character select, a match, a KO
-- and the win screen — because a range can be free on every menu and still be
-- used by the one screen nobody walked to.
--
--   ROM=<rom> tools/run.sh tools/probe_vram_free.lua 900
-- envs: LO/HI (VRAM tile range, default 0x5C0/0x5FF), TAG
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr

local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local LO_T, HI_T = num("LO", 0x5C0), num("HI", 0x5FF)
local LO, HI = LO_T * 32, HI_T * 32 + 31
local TAG = os.getenv("TAG") or "vramfree"
local LOG = assert(io.open(ENV.TRACE .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local VRAM = emu.memType.snesVideoRam
local frames, step, sf = 0, 1, 0
local pulse = {}
local writes, firstwrite = 0, nil
local dirty = {}            -- snapshot findings: byte -> value
local samples = 0
local firstdirty = nil      -- the PHASE in which the range first went non-zero

log(string.format("watching VRAM tiles $%03X-$%03X = bytes $%04X-$%04X", LO_T, HI_T, LO, HI))

emu.addMemoryCallback(function(addr, value)
  writes = writes + 1
  if not firstwrite then
    local ok, st = pcall(emu.getState)
    local pc = -1
    if ok and st then pc = ((st["cpu.k"] or 0) << 16) | (st["cpu.pc"] or 0) end
    firstwrite = string.format("f=%d addr=$%04X val=$%02X pc=$%06X", frames, addr or 0, value or 0, pc)
    log("  WRITE " .. firstwrite)
  end
end, emu.callbackType.write, LO, HI, emu.cpuType.snes, VRAM)

local function sample(where)
  samples = samples + 1
  local n = 0
  for a = LO, HI do
    local v = emu.read(a, VRAM) or 0
    if v ~= 0 and not dirty[a] then dirty[a] = v; n = n + 1 end
  end
  if n > 0 then
    if not firstdirty then firstdirty = where end
    log(string.format("  SNAPSHOT %s (f=%d): %d newly non-zero bytes", where, frames, n))
  end
end

local function beat(on) return (frames % 7) < 3 and on or {} end

emu.addEventCallback(function()
  for p = 0, 1 do
    emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p)
  end
end, emu.eventType.inputPolled)

-- The autopilot is lifted VERBATIM from the probes that reliably reach a match
-- (trace_dsp.lua and friends): wait out the intro, walk the mode list by reading
-- $1B10, confirm, then mash into the match. A hand-rolled variant timed out at
-- the title on the first attempt — this flow is the one that is known to work.
local STEPS = {
  function() if frames % 120 == 0 then sample("boot/intro") end; return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() sample("mode-select"); pulse[0] = {}; return sf > 240 end,
  function() return sf > 20 end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() sample("char-select"); pulse[0] = {}; return sf > 30 end,
  function()
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); return true end
    return false
  end,
  function() pulse[0] = {}; sample("match-load"); return ram(0x1FA) == 0x80 and sf > 150 end,
  function()
    -- damage on ($8D=5, annotations.md), park at strike range, beat the dummy
    -- down so the KO and win screens actually get drawn
    if sf == 2 then wr(0x8D, 0x05) end
    local ax = ram(0x1021) + 256 * ram(0x1022)
    local dx = (ax + 40) % 65536
    wr(0x10A1, dx % 256); wr(0x10A2, math.floor(dx / 256))
    local m = sf % 20
    pulse[0] = (m < 4) and { x = true } or ((m >= 10 and m < 14) and { a = true } or {})
    if sf % 120 == 0 then sample("in-match") end
    return sf > 2400 or ram(0x10C9) == 0
  end,
  function() pulse[0] = beat({ start = true }); if sf % 60 == 0 then sample("KO/win") end
             return sf > 900 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    sample("final")
    local n = 0
    for _ in pairs(dirty) do n = n + 1 end
    log("")
    log(string.format("frames=%d  snapshots=%d  callback writes=%d  bytes ever non-zero=%d",
      frames, samples, writes, n))
    -- A MENU font does not have to survive the match: the match replaces VRAM
    -- wholesale and the glyphs are re-uploaded next time a menu is drawn. So
    -- "dirty, but only from match-load onward" is a PASS for patch 16, and only
    -- "dirty on a menu screen" disqualifies the range.
    local MENU_PHASES = { ["boot/intro"] = true, ["mode-select"] = true, ["char-select"] = true }
    if writes == 0 and n == 0 then
      log(string.format("VERDICT: tiles $%03X-$%03X stayed ZERO for the WHOLE session"
        .. " — free unconditionally", LO_T, HI_T))
      emu.stop(0)
    elseif firstdirty and not MENU_PHASES[firstdirty] then
      log(string.format("VERDICT: free on every MENU screen; first used at '%s'.", firstdirty))
      log("  For a menu font that is a PASS — the match replaces VRAM wholesale and")
      log("  the glyphs are re-uploaded whenever a menu is drawn again. It would NOT")
      log("  be safe for anything that must persist into gameplay.")
      emu.stop(0)
    else
      log(string.format("VERDICT: NOT FREE — %d writes, %d bytes non-zero. Do NOT author here.",
        writes, n))
      local shown = 0
      for a, v in pairs(dirty) do
        if shown < 12 then log(string.format("    $%04X = $%02X (tile $%03X)", a, v, a // 32)) end
        shown = shown + 1
      end
      emu.stop(1)
    end
  end
  if frames > 12000 then log("TIMEOUT at step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_vram_free loaded: tiles $" .. string.format("%03X-%03X", LO_T, HI_T))
