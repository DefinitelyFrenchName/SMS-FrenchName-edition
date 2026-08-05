-- probe_p17_stagelist.lua — how many stages can the VS config screen reach?
--
-- Patch 17. The stage row's handler is $C3:AA1A: it sets the list bound
-- $1C1C from the flag $1F59 (set -> $0010, clear -> $0012) and then calls the
-- shared list navigator, whose wrap point ($C3:8002 cmp / $C3:801A lda) treats
-- $1C1C as the INCLUSIVE max index in WORD units. So 16 = stages 0-8 (nine)
-- and 18 = stages 0-9 (ten, the hidden Nakayoshi stage included).
--
-- The first attempt at this measurement was void because it swept WRAM for a
-- byte that cycles: the live index is $0038,X with X = $1B00, which is $1838
-- only once that base is loaded. So this probe does two things instead:
--   * PRECONDITION — an exec hook on the stage row's `sta $1C1C` ($C3:AA38,
--     also hooked on the FastROM mirror $83:AA38). If it never fires we never
--     reached the stage row and the run reports VOID, not "nine stages".
--   * MEASUREMENT — tap Right on that row and collect the distinct values of
--     $1838, which is what both the name tables and the scene id are indexed by.
--
-- Positive control: the vanilla unlock. $1F59 comes from $1C5A >> 1, and
-- $1C5A stays 0 only while a button combo is held on an earlier screen
-- ($C3:B8B4 checks X+L+R, $C0:AE00 checks L+R) — so FORCE=1, which pokes
-- $1C5A=0 before the flag is latched, must show ten stages on a CLEAN ROM.
-- If it does not, the harness is wrong, not the ROM.
--
--   ROM=<rom> TAG=clean            tools/run.sh tools/probe_p17_stagelist.lua 900
--   ROM=<rom> TAG=cleanforced FORCE=1 tools/run.sh tools/probe_p17_stagelist.lua 900
--   ROM=<rom> TAG=p17  SHOT=1      tools/run.sh tools/probe_p17_stagelist.lua 900
-- SHOT=1 also starts the match on the LAST reachable stage and screenshots it
-- (traces/ is gitignored — never commit game imagery).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local TAG = os.getenv("TAG") or "p17"
local FORCE = os.getenv("FORCE") == "1"
local SHOT = os.getenv("SHOT") == "1"
local LOG = assert(io.open(ENV.TRACE .. "p17_stagelist_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end
local function w16(a) return ram(a) | (ram(a + 1) << 8) end

local frames, step, sf = 0, 1, 0
local pulse = {}
local function beat(on) return (frames % 7) < 3 and on or {} end

-- PRECONDITION hook: the stage row's own `sta $1C1C`. Increment FIRST — this
-- project has had probes die inside a callback and report "0 events".
local hits, hits_fast, hits_slow = 0, 0, 0
local MEM = emu.memType.snesMemory
emu.addMemoryCallback(function() hits = hits + 1; hits_fast = hits_fast + 1 end,
  emu.callbackType.exec, 0x83AA38, 0x83AA38, emu.cpuType.snes, MEM)
emu.addMemoryCallback(function() hits = hits + 1; hits_slow = hits_slow + 1 end,
  emu.callbackType.exec, 0xC3AA38, 0xC3AA38, emu.cpuType.snes, MEM)

-- COMBO=1 holds the vanilla unlock's button combo (X+L+R) on P1 for the whole
-- run, merged into whatever the navigation is pressing. $C3:B8B4 leaves $1C5A
-- at 0 only while it is held, and $1C5A>>1 is the flag.
local COMBO = os.getenv("COMBO") == "1"
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    -- only until the latch (measured at ~f622, well before the navigation
    -- starts at f900) — holding X into character select would confirm a slot.
    if COMBO and p == 0 and frames < 700 then b.x = true; b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

-- Where does the flag actually get latched? One write callback answers it, and
-- makes "FORCE did nothing" distinguishable from "FORCE was too late".
emu.addMemoryCallback(function(_, v)
  log(string.format("$1F59 <- %d @f%d ($1C5A=%d pad$5C=$%04X)", v or -1, frames,
    w16(0x1C5A), w16(0x5C)))
end, emu.callbackType.write, 0x1F59, 0x1F59, emu.cpuType.snes, emu.memType.snesWorkRam)

-- Audio activity, for the BGM question. The hidden stage's scene record ends in
-- track $06 while the nine normal stages use $0A-$12, so "does it actually play
-- music" is a real question. The DSP is programmed through the SPC ports ($F2
-- latches the register, $F3 writes it — a callback on spcDspRegisters never
-- fires here, measured in trace_dsp.lua), so shadow those. KON is register $4C.
local kon, dspw, konbits, reg = 0, 0, 0, 0
local audio_on = false
emu.addMemoryCallback(function(_, v) reg = v or 0 end,
  emu.callbackType.write, 0x00F2, 0x00F2, emu.cpuType.spc, emu.memType.spcMemory)
emu.addMemoryCallback(function(_, v)
  if not audio_on then return end
  dspw = dspw + 1
  if reg == 0x4C and (v or 0) ~= 0 then kon = kon + 1; konbits = konbits | v end
end, emu.callbackType.write, 0x00F3, 0x00F3, emu.cpuType.spc, emu.memType.spcMemory)

local seen, order = {}, {}
local function note(v)
  if not seen[v] then seen[v] = true; order[#order + 1] = v end
end

local ctx = {}
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,   -- 1P vs 2P
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 150 end,
  function() pulse[0] = {}; return sf > 20 end,
  function() pulse[1] = beat({ a = true }); return ram(0x1B82) == 1 or sf > 150 end,
  function() pulse[0] = {}; pulse[1] = {}; return sf > 90 end,
  -- walk DOWN until the stage row's handler is the one running
  function()
    local m = sf % 24
    pulse[0] = (m < 3) and { down = true } or {}
    if hits > 0 then
      ctx.base = w16(0x1B00); ctx.bound = w16(0x1C1C)
      ctx.flag = ram(0x1F59); ctx.c5a = w16(0x1C5A)
      log(string.format("on stage row @f%d: $1B00=$%04X $1C1C=%d $1F59=%d $1C5A=%d $1838=%d"
        .. " (exec hits fast=%d slow=%d)", frames, ctx.base, ctx.bound, ctx.flag,
        ctx.c5a, ram(0x1838), hits_fast, hits_slow))
      return true
    end
    if sf > 900 then
      log("VOID: the stage row was never reached — no $1C1C write from $C3:AA38. "
        .. "This says nothing about how many stages exist.")
      LOG:close(); emu.stop(2)
    end
    return false
  end,
  -- cycle the row and collect every distinct index
  function()
    local m = sf % 10
    pulse[0] = (m < 3) and { right = true } or {}
    if m == 8 then note(w16(0x1838)) end
    return sf > 420
  end,
  function()   -- report
    table.sort(order)
    local list = {}
    for _, v in ipairs(order) do list[#list + 1] = string.format("%d(st%d)", v, v // 2) end
    log(string.format("P17 tag=%s bound=$1C1C=%d flag=$1F59=%d stages_reached=%d [%s]",
      TAG, ctx.bound or -1, ctx.flag or -1, #order, table.concat(list, " ")))
    if not SHOT then LOG:close(); emu.stop(#order > 0 and 0 or 1) end
    return true
  end,
  -- optional: land on a chosen index (default the highest) and start there
  function()
    local cur = w16(0x1838)
    local top = tonumber(os.getenv("STAGE") or "") and tonumber(os.getenv("STAGE")) * 2
      or order[#order]
    if cur ~= top then
      pulse[0] = (sf % 10 < 3) and { right = true } or {}
      if sf > 400 then log("could not reach top index"); LOG:close(); emu.stop(1) end
      return false
    end
    -- The name is queued to VRAM, not drawn on the spot: a shot taken on the
    -- frame the index lands shows the PREVIOUS stage's name. (Measured — the
    -- first capture at index 18 showed index 8's name, which reads exactly like
    -- "the tenth entry is mislabelled".) Let the transfer settle first.
    pulse[0] = {}
    ctx.settle = (ctx.settle or 0) + 1
    if ctx.settle < 40 then return false end
    log(string.format("selected index %d (stage %d); starting match", cur, cur // 2))
    -- "ten indices are reachable" is not "the tenth stage's NAME is drawn" —
    -- the name comes from a second table ($C3:B5AD/$B5C1 -> records in $C4) and
    -- a missing tenth entry there would show as a blank or garbage row.
    local f = io.open(ENV.TRACE .. "p17_menu_" .. TAG .. ".png", "wb")
    if f then f:write(emu.takeScreenshot()); f:close()
      log("menu screenshot -> traces/p17_menu_" .. TAG .. ".png (gitignored)") end
    return true
  end,
  function() pulse[0] = beat({ start = true }); return sf > 60 end,
  function()
    pulse[0] = {}
    if sf == 120 then audio_on = true end     -- past the load, into the round
    if sf > 600 then
      audio_on = false
      log(string.format("match: $8E=%d $1838=%d p1hp=%d p2hp=%d",
        ram(0x8E), w16(0x1838), ram(0x1049), ram(0x10C9)))
      log(string.format("AUDIO tag=%s stage=%d dsp_writes=%d key_ons=%d voices=$%02X",
        TAG, ram(0x8E) // 2, dspw, kon, konbits))
      local f = io.open(ENV.TRACE .. "p17_stage_" .. TAG .. ".png", "wb")
      if f then f:write(emu.takeScreenshot()); f:close()
        log("screenshot -> traces/p17_stage_" .. TAG .. ".png (gitignored)") end
      LOG:close(); emu.stop(0)
    end
    return false
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  -- FORCE: reproduce the vanilla unlock by keeping $1C5A at 0 until the flag is
  -- latched ($C3:BADE, `lda $1C5A / lsr / sta $1F59`).
  if FORCE then wr(0x1C5A, 0); wr(0x1C5B, 0) end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then LOG:close(); emu.stop(0) end
  if frames > 9000 then log("TIMEOUT step " .. step .. " hits=" .. hits); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
