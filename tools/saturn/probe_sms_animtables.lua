-- probe_sms_animtables.lua — live-verify SMS's three animation-layer tables
-- (located 2026-07-30 as twins of the decoded Super S system):
--   scripts $C0:0000 / pose records $84:809C / cel tables $CB:0000.
-- Every frame, recompute from PRG-ROM what the engine should have derived for P1:
--   pose record [class,hit,hurt,coll] at $84:809C[cid] + 4*pose(+0x05)
--   celA/celB via $CB:0000[cid] pose->cels + 5B cel records -> +0x0C..0x0E,+0x12/13
-- and compare against the live struct. Runs on the CLEAN SMS ROM with the
-- uranus_vs_jupiter_f5 fixture; drives 5LP and 2HP to cover attack poses.
-- ROM=<clean SMS> tools/run.sh tools/saturn/probe_sms_animtables.lua 200 -> traces/sms_animtables.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/sms_animtables.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, rom = PL.ram, PL.rom

local t, needLoad = -1, true
local ok, bad = 0, 0

local function word(off) return rom(off) + 256 * rom(off + 1) end

local function check()
  local cid = ram(0x1000)
  if cid == 0 then return end
  local pose = ram(0x1005)
  -- layer 2: pose record
  local prec = 0x040000 + word(0x04809C + 2 * cid) + 4 * pose
  local e18, e40, e41, e42 = rom(prec), rom(prec + 1), rom(prec + 2), rom(prec + 3)
  local g = (e18 == ram(0x1018)) and (e40 == ram(0x1040)) and (e41 == ram(0x1041)) and (e42 == ram(0x1042))
  -- layer 3: cels
  local base = 0xB0000
  local p1 = word(base + 4 * cid)
  local p2 = word(base + 4 * cid + 2)
  local celA = rom(base + p1 + 2 * pose)
  local ra = base + p2 + 5 * celA
  local srcOK = (rom(ra) == ram(0x100C)) and (rom(ra + 1) == ram(0x100D)) and (rom(ra + 2) == ram(0x100E))
             and (rom(ra + 3) == ram(0x1012)) and (rom(ra + 4) == ram(0x1013))
  if g and srcOK then ok = ok + 1 else
    bad = bad + 1
    log(string.format("t=%03d MISMATCH pose=%02X boxes(%s) cel(%s): rec %02X %02X %02X %02X vs %02X %02X %02X %02X; cel %02X src %02X%02X%02X/%02X%02X vs %02X%02X%02X/%02X%02X",
      t, pose, tostring(g), tostring(srcOK), e18, e40, e41, e42,
      ram(0x1018), ram(0x1040), ram(0x1041), ram(0x1042),
      celA, rom(ra+2), rom(ra+1), rom(ra), rom(ra+4), rom(ra+3),
      ram(0x100E), ram(0x100D), ram(0x100C), ram(0x1013), ram(0x1012)))
  end
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local p1 = PL.pad()
  if t >= 120 and t <= 121 then p1 = PL.pad({ y = true }) end                 -- 5LP
  if t >= 180 and t <= 181 then p1 = PL.pad({ down = true, x = true }) end    -- 2HP
  emu.setInput(p1, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t >= 60 then check() end
  if t == 300 then
    log(string.format("frames checked: %d OK / %d MISMATCH -> %s", ok, bad, bad == 0 and "ALL PASS" or "FAIL"))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("probe_sms_animtables loaded")
