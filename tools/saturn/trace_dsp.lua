-- trace_dsp.lua — record EVERY SNES-DSP register write of a scripted session, so
-- two builds can be diffed instead of spot-checked.
--
-- Why this exists. Testing a specific behaviour is easy; proving a change did
-- not disturb something nobody thought to check is the hard part, and more test
-- cases do not solve it. This turns "search the haystack" into "diff two
-- haystacks": run two builds through byte-identical scripted input and compare
-- the complete audio-side state trace. Any divergence outside the predicted set
-- is a finding you did not have to think to look for.
--
-- Coverage and its limits. This is TOTAL for the audio subsystem — every write
-- to every DSP register, including all music — and blind to everything else. A
-- hook that corrupted something non-audio needs the same treatment with a
-- different state vector.
--
-- Capture method: the DSP is programmed through the SPC's two ports ($00F2
-- latches the register index, $00F3 writes it), so shadowing those writes IS the
-- traffic. A write callback on memType.spcDspRegisters never fires (measured;
-- see probe_sms_voicepitch), which is why this reads the ports instead.
--
-- Alignment: frames are counted from a SYNC point (the frame the match goes
-- live), never from power-on, because load timing may legitimately differ
-- between builds. Input after sync is a fixed schedule keyed on the post-sync
-- frame counter, not on game state, so both runs are driven identically even if
-- one of them behaves differently — divergence must show up in the trace rather
-- than silently re-syncing the harness.
--
--   TAG=a SHELL_ID=6 ROM=<rom> tools/run.sh tools/saturn/trace_dsp.lua 700
-- envs:
--   TAG         output name -> traces/saturn/dsp_<TAG>.{dig,log}
--   SHELL_ID    shell she wears (6/7/8); with SATURN=0, the plain character
--   SATURN      1 (default) hold L+R at confirm, 0 = vanilla session
--   POKE_TR     hex transpose to write into her four sound ids at sync (e.g.
--               0xFB) — emulates the proposed fix with no ROM change, so the
--               retune can be diffed before any patch exists
--   FRAMES      post-sync frames to record (default 900)
--   DETAIL      0 to write digests only (default 1)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr

local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local TAG = os.getenv("TAG") or "a"
local SHELL = num("SHELL_ID", 6)
local SATURN = os.getenv("SATURN") ~= "0"
local POKE_TR = tonumber(os.getenv("POKE_TR") or "") -- nil = leave the driver alone
-- POKE_LIST writes a per-id list instead of one value for all four. Its point is
-- the NO-OP CONTROL: poking the vanilla bytes back must produce a byte-identical
-- trace, which is what proves the poke mechanism itself is inert. Without that
-- control, any divergence found by poking could be the poke rather than the value.
local POKE_LIST = os.getenv("POKE_LIST")
local FRAMES = num("FRAMES", 900)
local DETAIL = os.getenv("DETAIL") ~= "0"

local SPC = emu.memType.spcRam
local DIG = assert(io.open(ENV.TRACE .. "saturn/dsp_" .. TAG .. ".dig", "w"))
local LOGF = DETAIL and assert(io.open(ENV.TRACE .. "saturn/dsp_" .. TAG .. ".log", "w")) or nil

-- her four in-match sound ids: transpose byte = sequence base + 3
local TR = { 0x1C91, 0x1CAB, 0x1CB6, 0x1CC1 }
local TR_VANILLA = { 0xFE, 0xFE, 0xFF, 0xFD }

local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local synced, pf = false, -1          -- pf = post-sync frame index
local dspaddr, shadow = 0, {}
local fw = {}                          -- writes this frame: reg,val pairs
local total = 0
local buf, buflen = {}, 0

local function out(s)
  if not LOGF then return end
  buflen = buflen + 1; buf[buflen] = s
  if buflen >= 4096 then LOGF:write(table.concat(buf, "\n"), "\n"); buf = {}; buflen = 0 end
end

local function beat(on) return (frames % 7) < 3 and on or {} end
local function setchars() wr(0x1B40, SHELL); wr(0x1B80, 4) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and SATURN and p == 0 then b.l = true; b.r = true end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

emu.addMemoryCallback(function(_, v) dspaddr = v or 0 end,
  emu.callbackType.write, 0xF2, 0xF2, emu.cpuType.spc, emu.memType.spcMemory)

emu.addMemoryCallback(function(_, value)
  local v = value or 0
  shadow[dspaddr] = v
  if not synced then return end
  total = total + 1
  fw[#fw + 1] = dspaddr; fw[#fw + 1] = v
  if dspaddr == 0x4C and v ~= 0 then
    -- decode the key-on so the differ can attribute a pitch write to a SOURCE,
    -- and identify that source by its sample ADDRESS rather than by srcn alone
    for i = 0, 7 do
      if ((v >> i) & 1) == 1 then
        local b = i * 16
        local pitch = (shadow[b + 2] or 0) | ((shadow[b + 3] or 0) << 8)
        local srcn = shadow[b + 4] or 0
        local dirp = (emu.read(0x5D, emu.memType.spcDspRegisters) or 0) * 0x100
        local e = dirp + srcn * 4
        local samp = (emu.read(e, SPC) or 0) | ((emu.read(e + 1, SPC) or 0) << 8)
        out(string.format("K %d %d %d %04X %04X", pf, i, srcn, pitch, samp))
      end
    end
  end
end, emu.callbackType.write, 0xF3, 0xF3, emu.cpuType.spc, emu.memType.spcMemory)

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
    if sf > 1500 then DIG:write("MATCH-LOAD-FAIL\n"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 150 end,
  -- ---- recorded window ------------------------------------------------------
  function()
    if sf == 1 then
      synced = true; pf = 0
      DIG:write(string.format("# trace_dsp TAG=%s shell=%d saturn=%d poke=%s frames=%d\n",
        TAG, SHELL, SATURN and 1 or 0,
        POKE_LIST or (POKE_TR and string.format("%02X", POKE_TR)) or "none", FRAMES))
      DIG:write(string.format("# sync at abs frame %d, p1=%02X dummy=%02X\n",
        frames, ram(0x1000), ram(0x1080)))
      local plist = nil
      if POKE_LIST then
        plist = {}
        for h in POKE_LIST:gmatch("[^,]+") do plist[#plist + 1] = tonumber(h, 16) end
        assert(#plist == #TR, "POKE_LIST needs " .. #TR .. " values")
      end
      if POKE_TR or plist then
        -- assert the vanilla bytes before writing: a blind poke into a moved
        -- driver image would produce a trace that looks like a measurement
        for i, a in ipairs(TR) do
          local got = emu.read(a, SPC) or 0
          if got ~= TR_VANILLA[i] then
            DIG:write(string.format("PRECONDITION-FAIL $%04X=$%02X expect $%02X\n",
              a, got, TR_VANILLA[i]))
            emu.stop(1); return true
          end
        end
        for i, a in ipairs(TR) do emu.write(a, plist and plist[i] or POKE_TR, SPC) end
        DIG:write(string.format("# poked transpose %s into %d ids\n",
          plist and POKE_LIST or string.format("$%02X", POKE_TR), #TR))
      end
    end
    -- FIXED post-sync input schedule: 236+LP then 214+LP on a 60-frame cycle.
    -- Keyed on pf, never on game state, so both builds get identical input.
    local m = pf % 60
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
    return pf >= FRAMES
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if synced then
    -- per-frame FNV-1a over this frame's (reg,val) stream. Independent per frame
    -- rather than cumulative: a cumulative hash makes every frame after the
    -- first divergence differ too, which hides how many real divergences there
    -- are and where they stop.
    local h = 2166136261
    for i = 1, #fw do
      h = (h ~ fw[i]) & 0xFFFFFFFF
      h = (h * 16777619) & 0xFFFFFFFF
    end
    DIG:write(string.format("%d %d %08X\n", pf, #fw // 2, h))
    if DETAIL then
      for i = 1, #fw, 2 do out(string.format("W %d %02X %02X", pf, fw[i], fw[i + 1])) end
    end
    fw = {}
    pf = pf + 1
  end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    DIG:write(string.format("# END writes=%d frames=%d\n", total, pf))
    if LOGF then LOGF:write(table.concat(buf, "\n"), "\n"); LOGF:close() end
    DIG:close()
    emu.stop(0)
  end
  if frames > 8000 then DIG:write("# TIMEOUT step " .. step .. "\n"); emu.stop(1) end
end, emu.eventType.endFrame)

print("trace_dsp loaded: TAG=" .. TAG .. " shell=" .. SHELL ..
  (SATURN and " SATURN" or " vanilla") .. (POKE_TR and (" poke=" .. POKE_TR) or ""))
