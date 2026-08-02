-- probe_sms_saturn_smoke.lua — SMOKE TEST: Saturn animates in SMS.
-- Run on the mksaturn_smoke.py ROM. Loads the uranus_vs_jupiter_f5 fixture, pokes
-- P1's object id to Saturn's 0x1C (fresh idle state), and verifies the full ported
-- three-layer chain EVERY frame: pose id -> pose record (class/boxes, bank $E9 copy)
-- -> cels (bank $EA tables -> rebased $EB-$ED addresses in +0x0C..0x0E/+0x12/13).
-- P2 (Jupiter, id 4) doubles as a copy-fidelity canary: her chain must match the
-- ORIGINAL $84/$CB tables. Also asserts +0x51 stays 0 (recognizer stub works).
-- Holds right t=150..230 for walk; screenshots idle/walk to traces/.
-- ROM=build/saturn/SailorMoonS_saturn_smoke.sfc tools/run.sh tools/saturn/probe_sms_saturn_smoke.lua 200
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/saturn_smoke.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, rom, wr = PL.ram, PL.rom, PL.wr

local SAT_ID = 0x1C
-- appended banks are layout-dependent (clean base: first free = file 0x280000;
-- REF-stacked: 0x300000). Derive from ROM size (v0.11.5).
-- Read the first Saturn bank out of the ROM instead of inferring it from the
-- image size: the builder writes B_SCR as the operand of the interpreter's data
-- bank load ($80:A078 `lda #$C0` -> `lda #$<B_SCR>`), so this stays right however
-- many banks she occupies. It was `romsize - 9 * 0x10000` until v0.13.0 added a
-- tenth bank for her voice, at which point every frame "mismatched" — the probe
-- was reading the wrong bank, not the ROM misbehaving.
local B_SCR = rom(0x0A079)
local NB = (B_SCR - 0xC0) * 0x10000       -- first Saturn bank, as a file offset
local E8, E9, EA = NB, NB + 0x10000, NB + 0x20000
local t, needLoad = -1, true
local ok, bad, req51bad = 0, 0, 0
local actsSeen, posesSeen = {}, {}

local function word(off) return rom(off) + 256 * rom(off + 1) end

-- verify one player's chain against (posebank, posetbl, celbank, celtbl)
local function chain(base, cid, posebank, posetbl, celbank, celtbl)
  local pose = ram(base + 0x05)
  local prec = posebank + word(posebank + posetbl + 2 * cid) + 4 * pose
  local boxesOK = rom(prec) == ram(base + 0x18) and rom(prec + 1) == ram(base + 0x40)
    and rom(prec + 2) == ram(base + 0x41) and rom(prec + 3) == ram(base + 0x42)
  local p1 = word(celbank + celtbl + 4 * cid)
  local p2 = word(celbank + celtbl + 2 + 4 * cid)
  local celA = rom(celbank + p1 + 2 * pose)
  local ra = celbank + p2 + 5 * celA
  local celOK = rom(ra) == ram(base + 0x0C) and rom(ra + 1) == ram(base + 0x0D)
    and rom(ra + 2) == ram(base + 0x0E) and rom(ra + 3) == ram(base + 0x12)
    and rom(ra + 4) == ram(base + 0x13)
  return boxesOK, celOK, pose
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local p1 = PL.pad()
  if t >= 150 and t <= 230 then p1 = PL.pad({ right = true }) end
  emu.setInput(p1, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    -- become Saturn: id + fresh idle state
    wr(0x1000, SAT_ID)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1000 + o, 0) end
    log("t=060 poked P1 -> Saturn id 0x1C, fresh idle")
  end
  if t >= 63 and t <= 290 then
    -- P1 Saturn vs the relocated tables ($E9/$EA)
    local bOK, cOK, pose = chain(0x1000, SAT_ID, E9, 0x9E00, EA, 0x2000)
    -- P2 Jupiter canary vs the ORIGINAL tables ($84:809C / $CB:0000)
    local jbOK, jcOK = chain(0x1080, 4, 0x040000, 0x809C, 0x0B0000, 0x0000)
    local act = ram(0x1001)
    actsSeen[act] = true; posesSeen[pose] = true
    if bOK and cOK and jbOK and jcOK then ok = ok + 1 else
      bad = bad + 1
      if bad <= 12 then
        log(string.format("t=%03d MISMATCH act=%02X pose=%02X sat(box=%s cel=%s) jup(box=%s cel=%s) cel=%02X%02X%02X",
          t, act, pose, tostring(bOK), tostring(cOK), tostring(jbOK), tostring(jcOK),
          ram(0x100E), ram(0x100D), ram(0x100C)))
      end
    end
    if ram(0x1051) ~= 0 then req51bad = req51bad + 1 end
  end
  if t == 50 or t == 140 or t == 200 then
    local png = emu.takeScreenshot()
    local nm = t == 50 and "saturn_smoke_before.png" or (t == 140 and "saturn_smoke_idle.png" or "saturn_smoke_walk.png")
    log(string.format("t=%03d shot %s p1x=%d p2x=%d", t, nm,
      ram(0x1021) + 256*ram(0x1022), ram(0x10A1) + 256*ram(0x10A2)))
    local f = assert(io.open(ENV.TRACE .. nm, "wb"))
    f:write(png); f:close()
  end
  if t == 300 then
    local acts, poses = {}, {}
    for a in pairs(actsSeen) do acts[#acts + 1] = string.format("%02X", a) end
    for p in pairs(posesSeen) do poses[#poses + 1] = string.format("%02X", p) end
    table.sort(acts); table.sort(poses)
    log(string.format("frames: %d OK / %d MISMATCH; req51 violations: %d", ok, bad, req51bad))
    log("acts seen: " .. table.concat(acts, " "))
    log("poses seen: " .. table.concat(poses, " "))
    local verdict = (bad == 0 and req51bad == 0)
    log(verdict and "SMOKE PASS" or "SMOKE FAIL")
    emu.stop(verdict and 0 or 1)
  end
end, emu.eventType.endFrame)
print("probe_sms_saturn_smoke loaded")
