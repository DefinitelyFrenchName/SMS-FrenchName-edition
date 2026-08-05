-- probe_p17_randompool.lua — can the RANDOM stage default land on stage 9?
--
-- Patch 3 carries a rider that picks the stage at random when P2 confirms, and
-- it bounds itself rather than reading the menu's $1C1C:
--
--   $E8:00CD  lda $B1 / and #$00FF
--             cmp #$0009 / bcc + / sec / sbc #$0009 / bra -    ; A %= 9
--             asl / sta $8E
--
-- Sampling the distribution would need dozens of runs to argue "9 never comes
-- up". Forcing the input instead makes it one deterministic run per build: an
-- exec hook on the `lda $B1` writes the RNG byte the picker is about to read,
-- so RNG=9 must give stage 0 with the vanilla modulo and stage 9 with the
-- patched one. RNG=8 is the control — it must give stage 8 on BOTH builds,
-- which is what proves the poke reached the picker at all.
--
--   ROM=<ref build> TAG=nopool RNG=9 tools/run.sh tools/probe_p17_randompool.lua 400
-- envs: RNG (0-255, default 9), POOLPC (hex, default 0xE800CD), TAG
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local TAG = os.getenv("TAG") or "pool"
local RNG = tonumber(os.getenv("RNG") or "9")
local POOLPC = tonumber(os.getenv("POOLPC") or "0xE800CD")
local LOG = assert(io.open(ENV.TRACE .. "p17_pool_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end
local function w16(a) return ram(a) | (ram(a + 1) << 8) end

local frames, step, sf = 0, 1, 0
local pulse = {}
local function beat(on) return (frames % 7) < 3 and on or {} end

-- Increment BEFORE anything that could throw: a dead callback must not be able
-- to report "the picker never ran".
local forced = 0
emu.addMemoryCallback(function()
  forced = forced + 1
  wr(0xB1, RNG & 0xFF); wr(0xB2, 0)
end, emu.callbackType.exec, POOLPC, POOLPC, emu.cpuType.snes, emu.memType.snesMemory)

-- $C3:AACC is `sta $1838` in the config screen's entry code (`lda $8E / and
-- #$00FF / sta $1838 / sta $183A`) — i.e. the moment the screen adopts the
-- picked stage. Waiting on THAT rather than on a frame count is what makes the
-- two reported numbers comparable; a fixed wait sampled $1838 before the sync
-- and read a flat 0 on every build.
local synced = 0
emu.addMemoryCallback(function() synced = synced + 1 end,
  emu.callbackType.exec, 0x83AACC, 0x83AACC, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,   -- 1P vs 2P
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 150 end,
  function() pulse[0] = {}; return sf > 20 end,
  function() pulse[1] = beat({ a = true }); return ram(0x1B82) == 1 or sf > 150 end,
  -- wait for the config screen to sync $1838 from $8E ($C3:AAC6), so the two
  -- report the same stage and the log cannot be read as a contradiction
  function() pulse[0] = {}; pulse[1] = {}; return synced > 0 or sf > 900 end,
  function()
    if synced == 0 then
      log("VOID: the config screen never adopted a stage ($C3:AACC never ran).")
      LOG:close(); emu.stop(2)
    end
    if forced == 0 then
      log("VOID: the random-stage picker never executed at $" ..
        string.format("%06X", POOLPC) .. " — this ROM has no patch-3 rider, or "
        .. "it moved. Says nothing about the pool.")
      LOG:close(); emu.stop(2)
    end
    local idx = w16(0x1838)
    log(string.format("P17POOL tag=%s rng=%d picker_ran=%d $8E=%d $1838=%d stage=%d",
      TAG, RNG, forced, ram(0x8E), idx, idx // 2))
    LOG:close(); emu.stop(0)
    return true
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then LOG:close(); emu.stop(0) end
  if frames > 6000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
