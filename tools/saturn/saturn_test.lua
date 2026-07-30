-- saturn_test.lua — PAD-TEST helper for the Saturn-in-SMS smoke ROM.
--
-- HOW TO USE (Mesen GUI):
--   1. Build the ROM:  python3 tools/saturn/mksaturn_smoke.py build/saturn/SailorMoonS_saturn_smoke.sfc
--   2. Open it in Mesen, start a match (2P VS or vs COM; pick ANY character as P1).
--   3. Load this script in the Script Window. When the round starts, P1 becomes
--      SAILOR SATURN automatically. Re-transforms every round.
--
-- WHAT SHOULD WORK: idle/walk, all normals (standing/crouch/air; Y=LP X=HP
-- B=LK A=HK), qcf+P specials with a VISIBLE traveling fireball that hits, the
-- second special (try motions!), hits connect both ways, guard, pushback.
-- For the fireball GRAPHICS, generate the effect-tile dump once (needs the
-- Super S ROM):  ROM=<SuperS> tools/run.sh tools/saturn/probe_supers_effecttiles.lua 60
-- (without it the fireball renders with Uranus's effect tiles — still visible).
-- KNOWN GAPS: her moves are SILENT (Super S sound handler has no SMS twin yet);
-- she wears URANUS'S COLORS (palettes not ported); throws/desperation
-- unverified; P2 stays whoever you picked.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local function w(a, v) emu.write(a, v, WRAM) end

local wasSaturn = false
local tilesDone = false
local function uploadTiles()
  local f = io.open(ENV.TRACE .. "saturn/supers_effecttiles.bin", "rb")
  if not f then return false end
  local d = f:read("*a"); f:close()
  local V = emu.memType.snesVideoRam
  for i = 1, #d do emu.write(0x6A00 * 2 + i - 1, d:byte(i), V) end
  return true
end
emu.addEventCallback(function()
  local inMatch = r(0x0070) == 4
  local isSaturn = r(0x1000) == 0x1C
  if inMatch and not isSaturn then
    -- transform only from a neutral-ish act so we don't corrupt a live move
    local act = r(0x1001)
    if act <= 0x02 then
      w(0x1000, 0x1C)
      for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do w(0x1000 + o, 0) end
      wasSaturn = true
      tilesDone = uploadTiles()
    end
  end
  if wasSaturn then
    emu.drawString(8, 12, tilesDone and "P1 = SAILOR SATURN (smoke build)"
      or "P1 = SATURN (no effect tiles - see script header)", 0xFFFFFF, 0x000000)
  end
end, emu.eventType.endFrame)
print("saturn_test loaded — start a match; P1 becomes Saturn at round start")
