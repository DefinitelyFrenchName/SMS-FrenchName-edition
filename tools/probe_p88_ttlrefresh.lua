-- probe_p88_ttlrefresh.lua — issue #88: does a REPEATED label event refresh its TTL?
--
-- Loads traces/uranus_vs_jupiter.mss on a patch-10b (labels) ROM and forces the
-- TECH detector to fire EVERY frame: an exec hook on the producer entry $80:D5E8
-- (the patch's own hook site, so the pokes land after the engine's object update
-- and immediately before the label compute stub runs) writes P1 act $1001=0x23 and
-- P1 prevAct shadow $0900=0, giving detect the curAct==0x23 && prevAct!=0x23 edge
-- every frame. With the event recurring every frame the label must never expire;
-- on the unfixed build the TTL ($0906) is only set when the detected id differs
-- from the SHOWN id ($0907), so it decays to 0 and the label blanks mid-stream.
--   PASS (fixed): after first fire, TTL never reaches 0 and the label never blanks.
--   FAIL (unfixed): TTL hits 0 / labelId blanks while the event fires every frame.
-- Run: ROM=build/sms_combolabels.sfc tools/run.sh tools/probe_p88_ttlrefresh.lua 90
-- Out: traces/probe_p88_ttlrefresh.txt

local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local function w(a, v) emu.write(a, v, WRAM) end

local STATE = ENV.ROOT .. "traces/uranus_vs_jupiter.mss"
local OUT = ENV.ROOT .. "traces/probe_p88_ttlrefresh.txt"
local WARMUP, POKE_TO, VERDICT = 30, 150, 160

local t = 0
local firedAt, minTTL, blankAt = nil, 999, nil

local __loaded = false
emu.addMemoryCallback(function()
  if not __loaded then
    local f = assert(io.open(STATE, "rb"), "probe_p88: missing savestate " .. STATE)
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss); __loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

-- poke at the producer hook itself: after the engine's updates, before label compute
emu.addMemoryCallback(function()
  if __loaded and t > WARMUP and t <= POKE_TO then
    w(0x1001, 0x23); w(0x0900, 0x00)
  end
end, emu.callbackType.exec, 0x80D5E8, 0x80D5E8, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if not __loaded then return end
  t = t + 1
  local id, ttl = r(0x0905), r(0x0906)
  if t > WARMUP and t <= POKE_TO then
    if firedAt then
      if ttl < minTTL then minTTL = ttl end
      if id == 0 and not blankAt then blankAt = t end
    end
    if id == 5 and not firedAt then firedAt = t end
  end
  if os.getenv("P88_DEBUG") and t > WARMUP and t <= WARMUP + 20 then
    print(string.format("t=%d act=%02X st0=%02X st5=%02X st6=%02X st7=%02X",
      t, r(0x1001), r(0x0900), id, ttl, r(0x0907)))
  end
  if t == VERDICT then
    local log = io.open(OUT, "w")
    local ok = firedAt and not blankAt and minTTL > 0
    log:write(string.format(
      "fired@%s minTTL=%d blank@%s mode=%d -> %s\n",
      tostring(firedAt), minTTL, tostring(blankAt), r(0x008D),
      ok and "PASS (TTL refreshed by repeated event)"
         or (firedAt and "FAIL (repeated event did not refresh TTL)"
                      or "BROKEN (label never fired - probe precondition failed)")))
    log:close()
    emu.stop(ok and 0 or 1)
  end
end, emu.eventType.endFrame)

print("probe_p88_ttlrefresh loaded")
