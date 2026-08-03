-- probe_sms_mlcheck.lua — acceptance test for Saturn's movelist (task #41).
--
-- SMS expands a per-character movelist from a table at $E0:021A + charID*3 into
-- the staging buffer and DMAs it to BG3 (P1 -> VRAM word $1000). The build hooks
-- the two per-player table reads and substitutes hers. Checks:
--   1. with L+R held at confirm, P1's expand uses HER pointer, not the shell's;
--   2. the staged tilemap is byte-identical to tools/saturn/mkmovelist.py's;
--   3. with nobody armed, the shell's own list loads exactly as before.
--
-- usage: SAT=1 CHAR=6 ROM=build/saturn/<rom> tools/run.sh \
--            tools/saturn/probe_sms_mlcheck.lua 400
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "6")
local DUMMY = tonumber(os.getenv("DUMMY") or "4")
local SAT = (os.getenv("SAT") or "1") ~= "0"
local TAG = os.getenv("TAG") or ((SAT and "sat" or "vanilla") .. (os.getenv("CHAR") or "6"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/mlcheck_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local MEM = emu.memType.snesMemory

local fails, checks = 0, 0
local function check(ok, what, detail)
  checks = checks + 1
  if not ok then fails = fails + 1 end
  log(string.format("  [%s] %s%s", ok and "PASS" or "FAIL", what,
    detail and ("  — " .. detail) or ""))
end
local function readfile(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local d = f:read("*a"); f:close(); return d
end
local WANT = readfile("/tmp/saturn_tm.bin")

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end
local function slowbeat(on) return (frames % 20) < 4 and on or {} end
local function r8(a) return emu.read(0x7E0000 + a, MEM) end
local function r16(a) return r8(a) + 256 * r8(a + 1) end

local expands, staged = {}, nil
-- hook $C0:916B, not $919F: 916B moves the VRAM destination out of $03 into
-- $30 and zeroes $03 before calling the decompressor
for _, a in ipairs({ 0x00916B, 0x80916B, 0xC0916B }) do
  emu.addMemoryCallback(function()
    local dst = r16(0x03)
    if dst ~= 0x1000 and dst ~= 0x1400 then return end
    expands[#expands + 1] = { dst = dst, src = r16(0x00) + 0x10000 * r8(0x02) }
    log(string.format("  f%-5d EXPAND src $%06X -> VRAM word $%04X", frames,
      expands[#expands].src, dst))
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, MEM)
end
-- grab the staged buffer at the DMA that carries P1's list
for _, a in ipairs({ 0x0092A9, 0x8092A9, 0xC092A9 }) do
  emu.addMemoryCallback(function()
    -- several transfers hit $1000 during a load (a blank template first), so
    -- keep overwriting: the last one is the movelist actually shown
    if r16(0x30) ~= 0x1000 then return end
    if #expands == 0 then return end
    local t = {}
    for i = 0, 0x7FF do t[#t + 1] = string.char(emu.read(0x7F0000 + i, MEM)) end
    staged = table.concat(t)
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, MEM)
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = slowbeat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = slowbeat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = {}; return sf > 10 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() wr(0x1B40, CHAR); wr(0x1B80, DUMMY); return sf > 20 end,
  function()   -- P1 confirms, holding L+R to summon her
    local b = beat({ a = true })
    if SAT then b.l = true; b.r = true end
    pulse[0] = b
    return ram(0x1B42) == 1 or sf > 90
  end,
  function() pulse[0] = {}; return sf > 30 end,
  function()
    wr(0x1B80, DUMMY)
    pulse[0] = (frames % 14 < 3) and { a = true }
      or ((frames % 14 >= 7 and frames % 14 < 10) and { start = true } or {})
    if ram(0x1000) ~= 0 and ram(0x1080) ~= 0 then return true end
    if sf > 900 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() return sf > 150 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("=== %s, shell char %d (P1 id $%02X), flags %02X/%02X ===",
      SAT and "SATURN" or "VANILLA", CHAR, ram(0x1000), ram(0x1F100), ram(0x1F102)))
    local p1 = nil
    for _, e in ipairs(expands) do if e.dst == 0x1000 then p1 = e.src end end
    check(p1 ~= nil, "P1's movelist was expanded")
    if p1 then
      if SAT then
        check((p1 >> 16) ~= 0xE2, "P1's list comes from HER appended bank",
          string.format("source $%06X", p1))
      else
        check((p1 >> 16) == 0xE2, "P1's list is the vanilla bank-$E2 one",
          string.format("source $%06X", p1))
      end
    end
    if SAT and WANT and staged then
      local diff = 0
      for i = 1, 0x800 do
        if staged:byte(i) ~= WANT:byte(i) then diff = diff + 1 end
      end
      check(diff == 0, "the staged tilemap is byte-identical to the authored one",
        diff == 0 and nil or (diff .. " of 2048 bytes differ"))
    elseif SAT then
      check(false, "staged tilemap captured", "no buffer or reference")
    end
    log(string.format("=== %d checks, %d FAILED ===", checks, fails))
    log(fails == 0 and "ALL PASS" or "FAILURES PRESENT")
    emu.stop(fails == 0 and 0 or 1)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_sms_mlcheck loaded")
