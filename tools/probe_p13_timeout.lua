-- probe_p13_timeout.lua — issue #21: do Guts levels survive a TIMED-OUT round?
-- Loads a VS state on a patch-13 ROM, grants LV via direct state-block pokes, runs the
-- round clock down to 0, and logs LV across the round transition (frame-advance proof).
-- ROM=<p13 build> tools/run.sh tools/probe_p13_timeout.lua 240
-- Output: traces/p13_timeout.txt — verdict RESET (fixed) or SURVIVED (bug).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p13_timeout.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end
-- $7F:F800 state block (WRAM offset 0x1F800): MAGIC +0, LV +1/+2, PREVHP +5/+6
local ST = 0x1F800
local t, needLoad = -1, true
local granted, refillAt, verdictAt, prevHP2 = false, nil, nil, nil

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "neptune_vs_jupiter.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
  emu.setInput(base, 0, 0); emu.setInput(base, 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 10 then
    -- grant Guts: MAGIC must be inited and PREVHP must equal live HP (no false KO edge)
    wr(ST + 0, 0xA5); wr(ST + 1, 2); wr(ST + 2, 1)
    wr(ST + 5, ram(0x1049)); wr(ST + 6, ram(0x10C9))
    -- round clock: frame $0802, ones $0803, tens $0804 -> set 0:02
    wr(0x803, 2); wr(0x804, 0)
    granted = true
    log(string.format("t=%d GRANT lv=%d/%d clock=%d%ds hp=%02X/%02X", t, ram(ST+1), ram(ST+2), ram(0x804), ram(0x803), ram(0x1049), ram(0x10C9)))
  end
  if t == 15 then
    -- damage P2 so the decision has a loser and the refill produces a real edge
    wr(0x10C9, 0x30); wr(0x801, 0x30)
    log(string.format("t=%d DAMAGE p2 hp=%02X", t, ram(0x10C9)))
  end
  if granted and t % 30 == 0 then
    log(string.format("t=%d tick clock=%d%d lv=%d/%d hp=%02X/%02X max=%02X/%02X acts=%02X/%02X mode70=%02X",
      t, ram(0x804), ram(0x803), ram(ST+1), ram(ST+2), ram(0x1049), ram(0x10C9), ram(0x104A), ram(0x10CA), ram(0x1001), ram(0x1081), ram(0x70)))
  end
  -- detect the HP-refill edge of the round transition (probe-tracked prev, below max -> at max)
  if granted and not refillAt then
    local atMax = ram(0x1049) == ram(0x104A) and ram(0x10C9) == ram(0x10CA)
    if atMax and prevHP2 and prevHP2 < ram(0x10CA) then
      refillAt = t
      log(string.format("t=%d REFILL-EDGE lv=%d/%d acts=%02X/%02X clock=%d%d", t, ram(ST+1), ram(ST+2), ram(0x1001), ram(0x1081), ram(0x804), ram(0x803)))
      verdictAt = t + 120  -- give the new round time to settle
    end
    prevHP2 = ram(0x10C9)
  end
  if verdictAt and t >= verdictAt then
    local l1, l2 = ram(ST + 1), ram(ST + 2)
    log(string.format("t=%d VERDICT lv=%d/%d -> %s", t, l1, l2,
      (l1 == 0 and l2 == 0) and "RESET (timeout clears Guts — fixed)" or "SURVIVED (bug: Guts persists through timeout)"))
    emu.stop((l1 == 0 and l2 == 0) and 0 or 1)
  end
  if t > 3000 then log("TIMEOUT-NO-TRANSITION (round never ended?)"); emu.stop(2) end
end, emu.eventType.endFrame)
print("probe_p13_timeout loaded")
