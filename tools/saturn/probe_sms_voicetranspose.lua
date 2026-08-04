-- probe_sms_voicetranspose.lua — test the PROPOSED voice-pitch fix before
-- building anything: poke the driver's per-sound TRANSPOSE bytes in ARAM and
-- measure the pitch that comes out.
--
-- What the driver actually does (disassembled with tools/saturn/spc700dis.py
-- from traces/saturn/aram_6.bin; ROM home = ARAM + 0x23F804):
--
--   sound id  -> sfx table $13D6 + (id-1)*4 = [seq_lo, seq_hi, prio, chan]
--   sequence  -> [?, ptr_lo, ptr_hi, TRANSPOSE, instrument, volL, volR, ...]
--   $0B1E     copies TRANSPOSE to $0240+X (per logical channel)
--   $10A6     note = seqbyte - $74 + $0240+X
--   $0D6D     pitch = interp(semitone_table[$0DF5]) >> (6-octave) * tune($0410/$0420)
--   $12F4     flushes $02B0/$02C0+X to VxPITCH  (the "$131D/$1327" of the docs —
--             those PCs are the INC Y right after each MOV DSPDATA,A)
--
-- So pitch is per-sound NOTE data, and one byte per sound shifts it in whole
-- semitones. Her four ids and their vanilla transposes:
--
--   id 49 win laugh  $1C91 = $FE      id 51 214P   $1CB6 = $FF
--   id 50 236P       $1CAB = $FE      id 52 j632K  $1CC1 = $FD
--
-- Predicted: setting all four to $FB lands every one of them on $0345 (6539 Hz),
-- the maintainer-settled in-fight target. This probe proves or kills that.
--
--   SHELL_ID=6 ROM=<saturn build> tools/run.sh tools/saturn/probe_sms_voicetranspose.lua 700
-- envs: TRANSPOSE=0xFB (or "none" for the unpoked control), SHELL_ID, TAG
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr

local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local SHELL = num("SHELL_ID", 6)
local TRSTR = os.getenv("TRANSPOSE") or "0xFB"
local POKE = (TRSTR ~= "none") and (tonumber(TRSTR) or 0xFB) or nil
local TAG = os.getenv("TAG") or ("voicetranspose_" .. (POKE and string.format("%02X", POKE) or "ctl"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

-- ARAM address of each sound's transpose byte, and its expected vanilla value.
-- Asserting the vanilla value BEFORE poking is the precondition check this
-- project keeps paying for when it is skipped (HANDOFF §5): if the driver image
-- ever moves, a blind poke would write into unrelated data and the verdict would
-- be noise rather than a finding.
local SELECT = os.getenv("SELECT") == "1"
local TR_MATCH = {
  { id = 49, addr = 0x1C91, vanilla = 0xFE, what = "win laugh" },
  { id = 50, addr = 0x1CAB, vanilla = 0xFE, what = "236P" },
  { id = 51, addr = 0x1CB6, vanilla = 0xFF, what = "214P" },
  { id = 52, addr = 0x1CC1, vanilla = 0xFD, what = "j632K" },
}
-- The character-select line is a different id space: 48 + (charID-1)*5, one per
-- character, every one resolving to directory entry 48. The nine sequences are
-- byte-identical apart from the transpose, so she can simply REQUEST a different
-- character's id instead of having any byte patched — Mars's id 58 already
-- carries $FE, the settled select target. Poking the shell's own id to $FE is
-- the equivalent test.
local TR_SELECT = {
  { id = 73, addr = 0x1DA6, vanilla = 0x02, what = "Uranus select", shell = 6 },
  { id = 78, addr = 0x1DDD, vanilla = 0x01, what = "Neptune select", shell = 7 },
  { id = 83, addr = 0x1E14, vanilla = 0x04, what = "Pluto select", shell = 8 },
}
local TR = TR_MATCH
if SELECT then
  TR = {}
  for _, t in ipairs(TR_SELECT) do if t.shell == SHELL then TR[1] = t end end
  assert(TR[1], "SELECT mode needs SHELL_ID in {6,7,8}")
  POKE = (TRSTR ~= "none") and (tonumber(TRSTR) or 0xFE) or nil
end
local SPC = emu.memType.spcRam
local function aram(a) return emu.read(a, SPC) or 0 end

local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local curact = 0
local precheck, poked, reverts = nil, false, 0
local seen, order = {}, {}
local allkeyons, allsrcn = 0, {}
local voicepitch = {}          -- srcn -> {pitch -> count}, sample-address filtered

local function beat(on) return (frames % 7) < 3 and on or {} end
local function setchars() wr(0x1B40, SHELL); wr(0x1B80, 4) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and p == 0 then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

-- DSP register file shadowed from the SPC's port writes ($F2 index, $F3 data);
-- a write callback on spcDspRegisters never fires (see probe_sms_voicepitch).
local dspaddr = 0
emu.addMemoryCallback(function(_, v) dspaddr = v or 0 end,
  emu.callbackType.write, 0xF2, 0xF2, emu.cpuType.spc, emu.memType.spcMemory)

local shadow = {}
emu.addMemoryCallback(function(_, value)
  shadow[dspaddr] = value or 0
  if dspaddr ~= 0x4C or (value or 0) == 0 then return end
  for v = 0, 7 do
    if ((value >> v) & 1) == 1 then
      local base = v * 16
      local pitch = (shadow[base + 2] or 0) | ((shadow[base + 3] or 0) << 8)
      local srcn = shadow[base + 4] or 0
      allkeyons = allkeyons + 1
      local sk = string.format("srcn=%02d pitch=$%04X", srcn, pitch)
      allsrcn[sk] = (allsrcn[sk] or 0) + 1
      if srcn >= 48 then
        -- identify the source by its SAMPLE ADDRESS, not by looking plausible:
        -- that shortcut is what made the Super S "$03FE reference" wrong.
        local dirp = (emu.read(0x5D, emu.memType.spcDspRegisters) or 0) * 0x100
        local e = dirp + srcn * 4
        local sstart = aram(e) | (aram(e + 1) << 8)
        local key = string.format("act %02X -> srcn=%02d pitch=$%04X sample=$%04X",
          curact, srcn, pitch, sstart)
        if not seen[key] then seen[key] = 0; order[#order + 1] = key end
        seen[key] = seen[key] + 1
        -- Only sources whose sample actually lives in a voice bank ($B700 P1 /
        -- $DB00 P2) count toward the verdict. srcn >= 48 alone lets sfx in.
        if sstart >= 0xB700 then
          local vk = string.format("srcn=%02d", srcn)
          voicepitch[vk] = voicepitch[vk] or {}
          voicepitch[vk][pitch] = (voicepitch[vk][pitch] or 0) + 1
        end
      end
    end
  end
end, emu.callbackType.write, 0xF3, 0xF3, emu.cpuType.spc, emu.memType.spcMemory)

local function do_poke()
  for _, t in ipairs(TR) do emu.write(t.addr, POKE, SPC) end
end

-- Check the driver image is where the disassembly says, THEN poke. Asserting the
-- precondition before believing the verdict is the rule this project keeps
-- relearning: a blind poke into a moved image would produce numbers that look
-- like measurements and mean nothing.
local function arm(where)
  precheck = true
  for _, t in ipairs(TR) do
    local got = aram(t.addr)
    local ok = (got == t.vanilla)
    log(string.format("  PRE(%s) id%d %-14s $%04X = $%02X (expect $%02X) %s",
      where, t.id, t.what, t.addr, got, t.vanilla, ok and "OK" or "MISMATCH"))
    precheck = precheck and ok
  end
  if not precheck then
    log("PRECONDITION FAILED — driver image is not where the disassembly says;"
      .. " every pitch below would be meaningless. Stopping.")
    emu.stop(1)
    return
  end
  if POKE then
    do_poke()
    for _, t in ipairs(TR) do
      log(string.format("  POKE $%04X <= $%02X (readback $%02X)", t.addr, POKE, aram(t.addr)))
    end
    poked = true
  else
    log("  CONTROL run: no poke, expecting the documented vanilla pitches")
  end
end

local STEPS = {
  function() return frames >= 900 end,
  -- SELECT mode needs a mode that actually PLAYS the confirm voice: it never
  -- fires in practice. Row 1 = 2P VS.
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function()
    if SELECT then return true end
    pulse[0] = beat({ right = true }); return ram(0x1B10) == 4
  end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function()
    setchars(); hold = true
    -- SELECT: arm BEFORE the confirm, since the confirm voice is what we measure
    if SELECT and sf == 1 then arm("char-select") end
    return sf > 20
  end,
  function() setchars(); pulse[0] = beat({ a = true })
             return ram(0x1B42) == 1 or sf > 90 end,
  function()
    pulse[0] = {}
    if SELECT then return sf > 220 end        -- let the confirm voice play out
    return sf > 30
  end,
  function()
    if SELECT then return true end            -- done; skip the match load
    setchars()
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function()
    if SELECT then return true end
    pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 150
  end,
  function()
    if SELECT then return true end
    if sf == 1 then
      log(string.format("IN MATCH: p1=%02X (shell %d) dummy=%02X", ram(0x1000), SHELL, ram(0x1080)))
      arm("in-match")
    end
    -- Is the driver re-uploaded mid-match? If the poke ever reverts, a ROM-side
    -- fix needs to survive that upload, which changes the shape of the patch.
    if poked then
      for _, t in ipairs(TR) do
        if aram(t.addr) ~= POKE then reverts = reverts + 1; do_poke(); break end
      end
    end
    -- Drive her specials with real inputs (236+LP, 214+LP), NOT by forcing act
    -- ids. probe_sms_voicepitch's FORCEACTS list is stale on v0.14.9 — it
    -- produces zero voice key-ons on this build, while the input path below
    -- reproduces the documented srcn 49/50/51 exactly. Forcing an act that no
    -- longer voices looks identical to "the fix broke her voice".
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
    curact = ram(0x1001)
    return sf > 900
  end,
}

-- Targets settled by the maintainer (docs/saturn/sound_scope.md): in-fight
-- voices $0345 (6539 Hz), select line $03E4 (7781 Hz). TOL is not slack for a
-- shaky measurement — the driver INTERPOLATES between semitone-table entries and
-- rounds, so a transposed note lands within an LSB or two of the ideal value.
-- $0346 vs $0345 is 0.5 cents; demanding exact equality would fail a fix that
-- is audibly perfect.
local TARGET = SELECT and 0x03E4 or 0x0345
local TOL = 2

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("ALL key-ons: %d ; voice (srcn>=48): %d", allkeyons, #order))
    local ss = {}
    for k, v in pairs(allsrcn) do ss[#ss + 1] = string.format("%s x%d", k, v) end
    table.sort(ss)
    log("  EVERY key-on:")
    for _, l in ipairs(ss) do log("    " .. l) end
    log("  VOICE key-ons:")
    for _, k in ipairs(order) do log(string.format("    %s x%d", k, seen[k])) end
    log(string.format("  driver-image reverts during match: %d", reverts))
    -- verdict, over sources proven to be voices by SAMPLE ADDRESS
    local voices, off = 0, 0
    local vks = {}
    for k in pairs(voicepitch) do vks[#vks + 1] = k end
    table.sort(vks)
    log("  VOICE sources (sample in a voice bank):")
    for _, k in ipairs(vks) do
      for p, n in pairs(voicepitch[k]) do
        voices = voices + 1
        local ok = math.abs(p - TARGET) <= TOL
        if not ok then off = off + 1 end
        log(string.format("    %s pitch=$%04X x%d %s", k, p, n,
          POKE and (ok and "ON TARGET" or "off target") or ""))
      end
    end
    if voices == 0 then
      log("VERDICT: NO VOICE KEY-ONS — the probe proved nothing (broken harness,"
        .. " not evidence that the fix fails)")
      emu.stop(1)
    elseif POKE then
      log(string.format("VERDICT: %d distinct voice pitches, %d off target $%04X (tol +-%d) -> %s",
        voices, off, TARGET, TOL, off == 0 and "PASS" or "FAIL"))
      emu.stop(off == 0 and 0 or 1)
    else
      log(string.format("VERDICT(control): %d distinct voice pitches recorded", voices))
      emu.stop(0)
    end
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_voicetranspose loaded: shell " .. SHELL ..
  (POKE and string.format(" poke=$%02X", POKE) or " CONTROL"))
