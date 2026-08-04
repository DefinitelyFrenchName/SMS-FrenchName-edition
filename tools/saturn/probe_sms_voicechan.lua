-- probe_sms_voicechan.lua — settle the "voices 1/2/6" finding by watching the
-- driver's PER-CHANNEL state instead of the DSP output.
--
-- The finding: retuning her four sounds also moves the pitch of DSP voices 1, 2
-- and 6, by exactly the intervals applied to her sounds, while those voices hold
-- MUSIC sources (srcn 23/24). Two mechanisms fit, with opposite consequences:
--
--   (a) her sfx is LAYERED across several logical channels. Shifting every layer
--       together is then correct behaviour, and the finding is the fix working.
--   (b) an sfx channel's pitch shadow is reaching a DSP voice that music is
--       using. The retune then audibly detunes those frames of music.
--
-- They predict different things, which is what makes this decidable:
--
--   the driver keeps 16 LOGICAL channels and maps them onto 8 DSP voices through
--   the table at $1346 = [00 10 20 30 40 50 60 70] twice, so logical 0-7 (music)
--   and 8-15 (sfx) share voices. Her id-52 sfx table entry says chan 4, which
--   $0AF7/$0B1E turn into logical channel 12 -> DSP voice 4.
--
--   (a) predicts her TRANSPOSE ($0240+X) appears on more than one logical
--       channel — 9, 10 and/or 14, the sfx channels that map to voices 1, 2, 6.
--   (b) predicts it appears ONLY on channel 12, and the affected pitches show up
--       on the MUSIC channels 1, 2, 6 instead.
--
-- So: watch every write to the per-channel transpose array $0240-$024F and the
-- pitch shadow $02B0-$02BF, with the SPC PC that wrote it, and report per index.
--
--   SHELL_ID=6 ROM=<saturn build> tools/run.sh tools/saturn/probe_sms_voicechan.lua 700
-- envs: SHELL_ID, POKE (hex transpose for her four ids; unset = vanilla), TAG
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr

local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
local POKE = tonumber(os.getenv("POKE") or "", 16)
local TAG = os.getenv("TAG") or ("voicechan_" .. (POKE and "poked" or "van"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local SPC = emu.memType.spcRam
local TR = { 0x1C91, 0x1CAB, 0x1CB6, 0x1CC1 }
local TR_VAN = { 0xFE, 0xFE, 0xFF, 0xFD }
-- logical channel -> DSP voice, read straight from the driver's own table
local CH2V = {}

local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local synced = false
local trwrite = {}     -- channel -> {value -> count}
local trpc = {}        -- channel -> {pc -> count}
local pitchpc = {}     -- channel -> {pc -> count}
local kon = {}

local function beat(on) return (frames % 7) < 3 and on or {} end
local function setchars() wr(0x1B40, SHELL); wr(0x1B80, 4) end
local function bump(t, k1, k2)
  t[k1] = t[k1] or {}; t[k1][k2] = (t[k1][k2] or 0) + 1
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and p == 0 then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local function spcpc()
  local ok, st = pcall(emu.getState)
  return (ok and st and st["spc.pc"]) or -1
end

-- $0240+X — the per-channel TRANSPOSE, copied from the sound's sequence header
-- by $0B1E. This is the array the patch's four bytes flow into.
emu.addMemoryCallback(function(addr, value)
  if not synced then return end
  local ch = addr - 0x0240
  bump(trwrite, ch, value or 0)
  bump(trpc, ch, spcpc())
end, emu.callbackType.write, 0x0240, 0x024F, emu.cpuType.spc, SPC)

-- $02B0+X — the pitch-low shadow the DSP flush ($12F4) pushes to VxPITCHL
local pitchval = {}    -- channel -> ordered list of values written
emu.addMemoryCallback(function(addr, value)
  if not synced then return end
  local ch = addr - 0x02B0
  bump(pitchpc, ch, spcpc())
  pitchval[ch] = pitchval[ch] or {}
  local t = pitchval[ch]; t[#t + 1] = value or 0
end, emu.callbackType.write, 0x02B0, 0x02BF, emu.cpuType.spc, SPC)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() setchars(); hold = true; return sf > 20 end,
  function() setchars(); pulse[0] = beat({ a = true })
             return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    setchars()
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 150 end,
  function()
    if sf == 1 then
      for c = 0, 15 do CH2V[c] = (emu.read(0x1346 + c, SPC) or 0) >> 4 end
      log("logical channel -> DSP voice: " ..
        table.concat((function() local t = {}
          for c = 0, 15 do t[#t + 1] = string.format("%d->%d", c, CH2V[c]) end
          return t end)(), " "))
      for i, a in ipairs(TR) do
        local got = emu.read(a, SPC) or 0
        if got ~= TR_VAN[i] then
          log(string.format("PRECONDITION-FAIL $%04X=$%02X expect $%02X", a, got, TR_VAN[i]))
          emu.stop(1); return true
        end
      end
      if POKE then
        for _, a in ipairs(TR) do emu.write(a, POKE, SPC) end
        log(string.format("poked her four transposes to $%02X", POKE))
      else
        log("vanilla (no poke)")
      end
      synced = true
    end
    -- IDLE=1: she never acts, so none of her voices play. Comparing this to the
    -- vanilla run isolates whether HER SOUND perturbs music notes at all, which
    -- decides whether patch 101 introduces the artefact or only changes it.
    if os.getenv("IDLE") == "1" then pulse[0] = {}; return sf > 900 end
    local m = sf % 60
    if m < 6 then pulse[0] = { down = true }
    elseif m < 12 then pulse[0] = { down = true, right = true }
    elseif m < 18 then pulse[0] = { right = true }
    elseif m < 22 then pulse[0] = { y = true }
    elseif m < 30 then pulse[0] = {}
    elseif m < 36 then pulse[0] = { down = true }
    elseif m < 42 then pulse[0] = { down = true, left = true }
    elseif m < 48 then pulse[0] = { left = true }
    elseif m < 52 then pulse[0] = { y = true }
    else pulse[0] = {} end
    return sf > 900
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    local function fmt(t)
      local ks = {}
      for k in pairs(t) do ks[#ks + 1] = k end
      table.sort(ks)
      local o = {}
      for _, k in ipairs(ks) do o[#o + 1] = string.format("$%02X x%d", k, t[k]) end
      return table.concat(o, " ")
    end
    log("")
    log("TRANSPOSE writes ($0240+ch) — which logical channels carry a transpose:")
    for c = 0, 15 do
      if trwrite[c] then
        log(string.format("  ch %-2d (DSP voice %d): %s", c, CH2V[c] or -1, fmt(trwrite[c])))
      end
    end
    log("")
    log("PITCH-shadow writers ($02B0+ch), by SPC PC:")
    for c = 0, 15 do
      if pitchpc[c] then
        local o = {}
        for pc, n in pairs(pitchpc[c]) do o[#o + 1] = string.format("$%04X x%d", pc, n) end
        table.sort(o)
        log(string.format("  ch %-2d (DSP voice %d): %s", c, CH2V[c] or -1, table.concat(o, " ")))
      end
    end
    log("")
    log("PITCH-shadow VALUE stream per channel (first 40):")
    for c = 0, 15 do
      if pitchval[c] then
        local o = {}
        for i = 1, math.min(40, #pitchval[c]) do o[#o + 1] = string.format("%02X", pitchval[c][i]) end
        log(string.format("  ch %-2d n=%-4d %s", c, #pitchval[c], table.concat(o, " ")))
      end
    end
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_voicechan loaded: shell " .. SHELL .. (POKE and " poked" or " vanilla"))
