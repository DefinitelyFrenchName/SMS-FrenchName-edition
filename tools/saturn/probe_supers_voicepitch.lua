-- probe_supers_voicepitch.lua — what pitch does SATURN'S OWN GAME play her voice
-- at? Measurement only; changes nothing.
--
-- This is the calibration the port has never had. SMS plays her in-match voices
-- at $03E4/$041F/$03AC (probe_sms_voicepitch.lua, shell-independent) and her
-- character-select confirm at the SHELL's pitch ($04E7 Uranus / $0582 Pluto).
-- Both numbers are only meaningful against what Super S itself does — otherwise
-- any "fix" swaps one arbitrary pitch for another.
--
-- Method: force her voiced acts one at a time (the same trick probe_attackid.lua
-- uses — driving motions is unreliable and mode-dependent) and capture every DSP
-- key-on, reading the voice's SRCN ($x4) and 14-bit VxPITCH ($x2/$x3). The DSP is
-- programmed through the SPC's ports — $00F2 latches the register index, $00F3
-- writes it — so the register file is shadowed from that traffic; a write
-- callback on memType.spcDspRegisters never fires (measured).
--
--   GAME=supers ROM=<SuperS.sfc> tools/run.sh tools/saturn/probe_supers_voicepitch.lua 300
--   GAME=port   ROM=<saturn build> tools/run.sh tools/saturn/probe_supers_voicepitch.lua 300
-- Diff the two: same acts, both games, so any pitch difference is the port's.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local GAME = os.getenv("GAME") or "supers"
local LOG = assert(io.open(ENV.TRACE .. "saturn/voicepitch_game_" .. GAME .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local STATE = (GAME == "supers") and "saturn/saturn_vs_uranus_supers.mss"
                                 or "uranus_vs_jupiter_f5.mss"
local HOOK = (GAME == "supers") and 0x808347 or 0x808353
local t, needLoad = -1, true

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, HOOK, HOOK, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  emu.setInput(PL.pad(), 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

-- DSP register shadow, built from the SPC's own port writes
local dspaddr, shadow = 0, {}
local curact, hits, order = 0, {}, {}
emu.addMemoryCallback(function(_, v) dspaddr = v or 0 end,
  emu.callbackType.write, 0xF2, 0xF2, emu.cpuType.spc, emu.memType.spcMemory)
-- Read SRCN/PITCH LIVE from the register file at key-on rather than from the
-- shadow: this probe starts from a SAVESTATE, so every register written before
-- the state was saved is absent from the shadow and reads back as 0. (That is
-- exactly what the first run showed — a wall of "srcn=000".) The shadow is kept
-- only as a fallback for anything the live read cannot supply.
local DSPREG = emu.memType.spcDspRegisters
local function reg(r) return emu.read(r, DSPREG) or shadow[r] or 0 end
emu.addMemoryCallback(function(_, value)
  shadow[dspaddr] = value or 0
  if dspaddr ~= 0x4C or (value or 0) == 0 then return end   -- KON
  for v = 0, 7 do
    if ((value >> v) & 1) == 1 then
      local b = v * 16
      -- Identify what a source ACTUALLY is, instead of inferring it from a
      -- steady pitch: SRCN indexes the BRR directory at DIR($5D)*0x100 in ARAM,
      -- whose first word is the sample's start address. A voice and a music
      -- instrument are then distinguishable by where their sample lives.
      local srcn = reg(b + 4)
      local dir = reg(0x5D) * 0x100
      local e = dir + srcn * 4
      local start = (emu.read(e, emu.memType.spcRam) or 0)
                  | ((emu.read(e + 1, emu.memType.spcRam) or 0) << 8)
      local key = string.format("act %02X -> srcn=%03d pitch=$%04X sample=$%04X",
        curact, srcn, reg(b + 2) | (reg(b + 3) << 8), start)
      if not hits[key] then hits[key] = 0; order[#order + 1] = key end
      hits[key] = hits[key] + 1
    end
  end
end, emu.callbackType.write, 0xF3, 0xF3, emu.cpuType.spc, emu.memType.spcMemory)

-- her voiced moves: qcb+P (6A/6C), qcf+P (6E/70), j.632K (74/76), desperation
-- (78/79), win pose (24). Forced one at a time, well spaced.
local ACTS = { 0x6A, 0x6C, 0x6E, 0x70, 0x74, 0x76, 0x78, 0x79, 0x24,
               0x6A, 0x6E, 0x74, 0x78, 0x24 }   -- second pass: voices are not
               -- guaranteed to key on within one forced-act window
local ai, SPACING = 1, tonumber(os.getenv("SPACING") or "140")

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 and GAME == "port" then                 -- make P1 Saturn in the port
    wr(0x1000, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1000 + o, 0) end
  end
  if t < 100 then return end
  local base = 100 + (ai - 1) * SPACING
  if ai <= #ACTS then
    if t == base then
      curact = ACTS[ai]
      wr(0x1001, curact); wr(0x1002, 0); wr(0x1006, 0); wr(0x1007, 0)
    elseif t == base + SPACING - 1 then
      ai = ai + 1
    end
  else
    log(string.format("GAME=%s  p1 id=%02X", GAME, ram(0x1000)))
    log("every key-on, tagged with the act that was forced:")
    for _, k in ipairs(order) do log(string.format("  %s  x%d", k, hits[k])) end
    emu.stop(0)
  end
  if t > 3000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_supers_voicepitch loaded: " .. GAME)
