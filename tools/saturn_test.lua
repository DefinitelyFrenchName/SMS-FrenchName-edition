-- saturn_test.lua — PAD-TEST helper for the Saturn-in-SMS smoke ROM.
--
-- HOW TO USE (Mesen GUI):
--   1. Build the ROM:  python3 tools/mksaturn_smoke.py build/SailorMoonS_saturn_smoke.sfc
--   2. Open it in Mesen, start a match (2P VS or vs COM; pick ANY character as P1).
--   3. Load this script in the Script Window. When the round starts, P1 becomes
--      SAILOR SATURN automatically. Re-transforms every round.
--
-- WHAT SHOULD WORK: idle/walk, the four standing normals (Y=LP X=HP B=LK A=HK),
-- crouch/jump variants, qcf+P specials (two more specials exist — try motions!),
-- hits connect both ways, guard, pushback.
-- KNOWN GAPS (by design, next port units): fireballs are INVISIBLE and vanish
-- instantly (projectile objects not ported yet); her moves are SILENT (Super S
-- sound handler has no SMS twin yet); she wears URANUS'S COLORS (palettes not
-- ported); throws/desperation unverified; P2 stays whoever you picked.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local function w(a, v) emu.write(a, v, WRAM) end

local wasSaturn = false
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
    end
  end
  if wasSaturn then
    emu.drawString(8, 12, "P1 = SAILOR SATURN (smoke build)", 0xFFFFFF, 0x000000)
  end
end, emu.eventType.endFrame)
print("saturn_test loaded — start a match; P1 becomes Saturn at round start")
