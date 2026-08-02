-- probe_sms_selectcheck.lua — acceptance test for Saturn's character-select
-- voice ("Yoroshiku").
--
-- SMS voices each sailor on confirm by loading audio-bank id 21 + charID (one
-- BRR sample to ARAM $B700, played through a fixed directory entry). The build
-- swaps that id for hers when the confirming player is Saturn. Checks:
--   1. the Saturn player's confirm loads HER bank id, not the shell's;
--   2. the other player's confirm still loads the vanilla id for their character;
--   3. ARAM $B700 really holds her line, byte-for-byte vs saturn_select.brr;
--   4. the shell is irrelevant — pass SHELL=1 to re-run over Moon.
--
-- usage: SAT=0 SHELL=6 OTHER=9 ROM=build/saturn/<rom> tools/run.sh \
--            tools/saturn/probe_sms_selectcheck.lua 600
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local SHELL = tonumber(os.getenv("SHELL") or "6")
local OTHER = tonumber(os.getenv("OTHER") or "9")
local SATP = tonumber(os.getenv("SAT") or "0")
local SELID = tonumber(os.getenv("SELID") or "52")
local TAG = os.getenv("TAG") or ("sel_p" .. (tonumber(os.getenv("SAT") or "0") + 1)
  .. "_shell" .. (os.getenv("SHELL") or "6"))
local LOG = assert(io.open(ENV.TRACE .. "saturn/selectcheck_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local MEM = emu.memType.snesMemory
local WRAM = emu.memType.snesWorkRam
local ARAM = emu.memType.spcRam

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
local SEL = readfile(ENV.ROOT .. "build/saturn/saturn_select.brr")

-- P1 confirms first, then P2; both characters are known, so the expected
-- vanilla id for each side is 21 + that side's charID
local P1CHAR, P2CHAR = SHELL, OTHER
if SATP == 1 then P1CHAR, P2CHAR = OTHER, SHELL end

local frames, step, sf = 0, 1, 0
local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(PL.pad(pulse[p]), 0, p) end
end, emu.eventType.inputPolled)
local function beat(on) return (frames % 7) < 3 and on or {} end

local loads, dumped = {}, nil
for _, a in ipairs({ 0x00EB4B, 0x80EB4B, 0xC0EB4B }) do
  emu.addMemoryCallback(function()
    local ok, s = pcall(emu.getState)
    local A = ((ok and s and s["cpu.a"]) or 0) & 0xFF
    if A >= 21 and A <= 30 or A == SELID then
      loads[#loads + 1] = { f = frames, id = A }
      log(string.format("  f%-5d select-voice LOAD id %d  ($1B1E=%02X, player byte %d)",
        frames, A, ram(0x1B1E), ram(0x1F109)))
      if A == SELID and not dumped then dumped = frames end
    end
  end, emu.callbackType.exec, a, a, emu.cpuType.snes, MEM)
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function()
    if sf > 240 then
      log(string.format("=== P1 char %d, P2 char %d — Saturn on P%d (shell %d) ===",
        P1CHAR, P2CHAR, SATP + 1, SHELL))
      return true
    end
    return false
  end,
  function() wr(0x1B40, P1CHAR); wr(0x1B80, P2CHAR); return sf > 30 end,
  function()
    pulse[0] = beat({ a = true })
    if SATP == 0 then pulse[0].l = true; pulse[0].r = true end
    return ram(0x1B42) == 1 or sf > 120
  end,
  function() pulse[0] = {}; return sf > 90 end,
  function()
    pulse[1] = beat({ a = true })
    if SATP == 1 then pulse[1].l = true; pulse[1].r = true end
    return sf > 220
  end,
  function() return sf > 60 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("--- %d select-voice loads seen ---", #loads))
    check(#loads == 2, "exactly two select-voice loads (one per player)",
      string.format("saw %d", #loads))
    if SATP < 0 then
      -- nobody armed: BOTH confirms must be pure vanilla
      local ok1 = loads[1] and loads[1].id == 21 + P1CHAR
      local ok2 = loads[2] and loads[2].id == 21 + P2CHAR
      check(ok1 and ok2, "with nobody armed, both confirms load vanilla ids",
        string.format("got %s / %s, expected %d / %d",
          loads[1] and loads[1].id or "-", loads[2] and loads[2].id or "-",
          21 + P1CHAR, 21 + P2CHAR))
      log(string.format("=== %d checks, %d FAILED ===", checks, fails))
      log(fails == 0 and "ALL PASS" or "FAILURES PRESENT")
      emu.stop(fails == 0 and 0 or 1)
      return
    end
    local hers = (SATP == 0) and loads[1] or loads[2]
    local theirs = (SATP == 0) and loads[2] or loads[1]
    local otherchar = (SATP == 0) and P2CHAR or P1CHAR
    if hers then
      check(hers.id == SELID, "the Saturn player's confirm loads HER bank",
        string.format("id %d (expected %d)", hers.id, SELID))
    else
      check(false, "the Saturn player's confirm loads HER bank", "no load seen")
    end
    if theirs then
      check(theirs.id == 21 + otherchar,
        "the other player's confirm is untouched",
        string.format("id %d (expected %d for char %d)", theirs.id,
          21 + otherchar, otherchar))
    else
      check(false, "the other player's confirm is untouched", "no load seen")
    end
    if SEL then
      -- her line is uploaded to $B700; whichever confirm came LAST leaves its
      -- own bank there, so only compare when hers was last
      local diff, first = 0, nil
      for i = 1, #SEL do
        if emu.read(0xB700 + i - 1, ARAM) ~= SEL:byte(i) then
          diff = diff + 1; first = first or (0xB700 + i - 1)
        end
      end
      if SATP == 1 then
        local d = nil
        if diff ~= 0 then
          d = string.format("%d of %d bytes differ, first at $%04X", diff, #SEL, first or 0)
        end
        check(diff == 0, string.format("her %d-byte line is resident at $B700", #SEL), d)
      else
        log(string.format("  (P1 case: P2 confirmed last, so $B700 now holds their line"
          .. " — %d of %d bytes differ from hers, as expected)", diff, #SEL))
      end
    else
      check(false, "build/saturn/saturn_select.brr readable")
    end
    log(string.format("=== %d checks, %d FAILED ===", checks, fails))
    log(fails == 0 and "ALL PASS" or "FAILURES PRESENT")
    emu.stop(fails == 0 and 0 or 1)
  end
  if frames > 4000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_sms_selectcheck loaded")
