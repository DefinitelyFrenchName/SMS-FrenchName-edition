-- probe_sms_voicefire.lua — does SHE actually ask for her voice in play?
--
-- The bank and directory can be perfect and still be silent: her sounds are
-- requested by CMD steps inside her ported scripts, and mksaturn_smoke.py routes
-- args 0x22-0x25 to `sta $78,X` with X taken from $88 (the engine's current
-- object base, $1000 or $1080). That $88 assumption is the last untested link,
-- so this watches the per-player voice slots while she fights: every write to
-- $1078/$10F8 is logged with the PC that made it, alongside the DSP voice that
-- starts as a result.
--
-- Expected: her specials request ids 50/51/52 and her win pose 49, always into
-- the slot belonging to her player, and DSP voice 4 (P1) picks up directory
-- entries 48-51.
--
-- usage: PLAYER=0 CHARA=6 CHAR2=9 ROM=build/saturn/<rom> tools/run.sh \
--            tools/saturn/probe_sms_voicefire.lua 900
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHARA = tonumber(os.getenv("CHARA") or "6")
local CHAR2 = tonumber(os.getenv("CHAR2") or "9")
local PLAYER = tonumber(os.getenv("PLAYER") or "0")
local TAG = os.getenv("TAG") or ("fire_p" .. (tonumber(os.getenv("PLAYER") or "0") + 1))
local LOG = assert(io.open(ENV.TRACE .. "saturn/voicefire_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram
local WRAM = emu.memType.snesWorkRam
local DSP = emu.memType.spcDspRegisters
local MAGIC, FLAG = 0xA5, 0x1F100 + (tonumber(os.getenv("PLAYER") or "0"))

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

-- every write to either voice slot, with its writer
local live = false
local writes = {}
for _, slot in ipairs({ { 0x1078, "P1" }, { 0x10F8, "P2" } }) do
  for _, b in ipairs({ 0x7E0000 + slot[1], slot[1] }) do
    emu.addMemoryCallback(function(_, value)
      if not live or (value or 0) == 0 or #writes > 60 then return end
      local ok, s = pcall(emu.getState)
      writes[#writes + 1] = string.format("f%-5d %s slot <= %3d ($%02X)  from %02X:%04X",
        frames, slot[2], value, value,
        (ok and s and s["cpu.k"]) or 0, (ok and s and s["cpu.pc"]) or 0)
    end, emu.callbackType.write, b, b, emu.cpuType.snes, WRAM)
  end
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function()
    emu.write(0x1B40, CHARA, WRAM); emu.write(0x1B80, CHAR2, WRAM); return sf > 20
  end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function() pulse[1] = beat({ a = true }); return sf > 60 end,
  function()
    if sf == 1 then emu.write(FLAG, MAGIC, WRAM) end
    return sf > 240
  end,
  function()
    pulse[0] = beat({ start = true }); pulse[1] = beat({ start = true })
    return ram(0x1000) ~= 0 and ram(0x1080) ~= 0 or sf > 600
  end,
  function()
    return ram(PLAYER == 0 and 0x1000 or 0x1080) == 0x1C or sf > 600
  end,
  function() if sf == 1 then live = true; log("=== match live, she is object $1C ===") end
    return sf > 30 end,
}

-- motions, driven on her pad: 236+LP, 214+LP, 236+HP
local PAD = PLAYER
local MOTIONS = {
  { name = "236 LP", seq = { { 6, { down = true } }, { 4, { down = true, right = true } },
                             { 4, { right = true } }, { 3, { right = true, y = true } } } },
  { name = "214 LP", seq = { { 6, { down = true } }, { 4, { down = true, left = true } },
                             { 4, { left = true } }, { 3, { left = true, y = true } } } },
  { name = "236 HP", seq = { { 6, { down = true } }, { 4, { down = true, right = true } },
                             { 4, { right = true } }, { 3, { right = true, x = true } } } },
}
local mi, mt = 1, 0

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if not live then
    local fn = STEPS[step]
    if fn and fn() then step = step + 1; sf = 0; pulse = {} end
    return
  end
  local m = MOTIONS[mi]
  if not m then
    log("--- voice-slot writes ---")
    if #writes == 0 then log("  (none — her CMD steps never reached a voice slot)") end
    for _, w in ipairs(writes) do log("  " .. w) end
    log("done")
    emu.stop(0)
    return
  end
  mt = mt + 1
  if mt == 1 then log(string.format("--- %s (f%d) ---", m.name, frames)) end
  local t, acc = mt, 0
  pulse[PAD] = {}
  for _, s in ipairs(m.seq) do
    if t > acc and t <= acc + s[1] then pulse[PAD] = s[2] end
    acc = acc + s[1]
  end
  if mt > acc + 90 then mi = mi + 1; mt = 0 end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_voicefire loaded")
