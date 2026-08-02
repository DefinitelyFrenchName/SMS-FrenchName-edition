-- probe_sms_cmdwho.lua — which player is running the script when a CMD step
-- fires? (task #44: her voice went to the WRONG slot.)
--
-- The CMD stub routed her voice with `ldx $88 / sta $78,X`, on the assumption
-- that $88 holds the current object's struct base ($1000 / $1080) the way it
-- does in the proc helper. In play the writes landed on P2's slot while she was
-- P1, so that assumption is wrong somewhere. This dumps the whole candidate set
-- at the moment of the store — registers, direct page, $88, and the engine's
-- object-loop variables — so the right source can be picked by measurement
-- rather than by another guess.
--
-- usage: STORE=0xF02944 PLAYER=0 ROM=build/saturn/<rom> tools/run.sh \
--            tools/saturn/probe_sms_cmdwho.lua 900
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHARA = tonumber(os.getenv("CHARA") or "6")
local CHAR2 = tonumber(os.getenv("CHAR2") or "9")
local PLAYER = tonumber(os.getenv("PLAYER") or "0")
local STORE = tonumber(os.getenv("STORE") or "0xF0293F")
local TAG = os.getenv("TAG") or "cmdwho"
local LOG = assert(io.open(ENV.TRACE .. "saturn/" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram
local WRAM = emu.memType.snesWorkRam
local MEM = emu.memType.snesMemory
local MAGIC, FLAG = 0xA5, 0x1F100 + (tonumber(os.getenv("PLAYER") or "0"))

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local live, hits = false, {}
emu.addMemoryCallback(function()
  if not live or #hits > 24 then return end
  local ok, s = pcall(emu.getState)
  if not ok or not s then return end
  local d = s["cpu.d"] or 0
  local x = s["cpu.x"] or 0
  local function w16(a) return emu.read(a, MEM) + 256 * emu.read(a + 1, MEM) end
  -- X is the interpreter's object base, so the emitting object identifies
  -- itself: +0x00 is its id (0x1C = Saturn, 0x20-0x22 = her projectiles) and
  -- +0x01 its current act.
  local obj = x & 0xFFFF
  hits[#hits + 1] = string.format(
    "f%-5d id=%3d ($%02X) X=$%04X -> obj $%02X act $%02X step $%02X | D=%04X "
    .. "| P1 id $%02X act $%02X | P2 id $%02X act $%02X",
    frames, (s["cpu.a"] or 0) & 0xFF, (s["cpu.a"] or 0) & 0xFF, obj,
    emu.read(0x7E0000 + obj, MEM), emu.read(0x7E0001 + obj, MEM),
    emu.read(0x7E0002 + obj, MEM), d,
    ram(0x1000), ram(0x1001), ram(0x1080), ram(0x1081))
end, emu.callbackType.exec, STORE, STORE, emu.cpuType.snes, MEM)

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
  function() return ram(PLAYER == 0 and 0x1000 or 0x1080) == 0x1C or sf > 600 end,
  function()
    if sf == 1 then
      live = true
      log(string.format("=== Saturn on P%d (P1 id $%02X, P2 id $%02X); watching %06X ===",
        PLAYER + 1, ram(0x1000), ram(0x1080), STORE))
    end
    return sf > 30
  end,
}

local MOTIONS = {
  { name = "236 LP", seq = { { 6, { down = true } }, { 4, { down = true, right = true } },
                             { 4, { right = true } }, { 3, { right = true, y = true } } } },
  { name = "214 LP", seq = { { 6, { down = true } }, { 4, { down = true, left = true } },
                             { 4, { left = true } }, { 3, { left = true, y = true } } } },
  { name = "jump 632K", seq = { { 4, { up = true, right = true } }, { 12, {} },
                                { 4, { down = true } }, { 3, { down = true, right = true } },
                                { 3, { right = true } }, { 3, { right = true, b = true } } } },
  { name = "plain jump", seq = { { 4, { up = true } } } },
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
    log("--- stores seen ---")
    if #hits == 0 then log("  (the CMD store never executed)") end
    for _, h in ipairs(hits) do log("  " .. h) end
    log("done"); emu.stop(0); return
  end
  mt = mt + 1
  if mt == 1 then log(string.format("--- %s (f%d) ---", m.name, frames)) end
  local t, acc = mt, 0
  pulse[PLAYER] = {}
  for _, s in ipairs(m.seq) do
    if t > acc and t <= acc + s[1] then pulse[PLAYER] = s[2] end
    acc = acc + s[1]
  end
  if mt > acc + 90 then mi = mi + 1; mt = 0 end
  if frames > 6000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_cmdwho loaded")
