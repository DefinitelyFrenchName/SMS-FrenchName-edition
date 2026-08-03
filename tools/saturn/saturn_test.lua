-- saturn_test.lua — PAD-TEST helper for the Saturn-in-SMS smoke ROM.
--
-- HOW TO USE (Mesen GUI):
--   1. Build the ROM:  python3 tools/saturn/mksaturn_smoke.py build/saturn/SailorMoonS_saturn_smoke.sfc
--   2. Open it in Mesen, start a match (2P VS or vs COM; pick URANUS, NEPTUNE or
--      PLUTO as P1 — since v0.14.5 those are the only shells she will wear).
--   3. HIDDEN build (the DEFAULT since the 2026-07-31 consensus): hold L+R
--      while CONFIRMING Uranus, Neptune or Pluto at the select screen; that
--      character becomes Saturn at round load (P1/P2/practice dummy; confirming
--      without the code un-picks). Any OTHER shell is refused outright — that is
--      the story lock (story mode cannot offer the outer senshi), so there is no
--      mode check to get wrong; see SHELL_GUARD in mksaturn_smoke.py.
--      Older route, still working: hold L+R on a pad while the round LOADS
--      (P1 pad since v0.8.0, P2 pad since v0.9.0; SELECT-hold reverts), or load
--      this script in the Script Window (auto-transform + version label).
--      (The v0.10.0 VISIBLE slot-10 variant was retired 2026-08-04 and its code
--      deleted — it was a placeholder and it added the one char-select surface
--      the story lock exists to avoid. History: BUILDS.md 0.10.0/0.11.0.)
--
-- WHAT SHOULD WORK: idle/walk, all normals (standing/crouch/air; Y=LP X=HP
-- B=LK A=HK), qcf+P specials with a VISIBLE traveling fireball that hits, the
-- qcb+P wave, the j.632+K air projectile, throws, and since v0.11.2 her
-- DESPERATION: at low HP (red life), 412364+HP (roughly SF half-circle-back
-- then back again, unhurried — each step has a 15f window; must end with
-- HEAVY PUNCH) -> rushing 8-hit super. Hits connect both ways, guard,
-- pushback. NOTE she has NO forward step-dash (Super S is the same).
-- For the fireball GRAPHICS, generate the effect-tile dump once (needs the
-- Super S ROM):  ROM=<SuperS> tools/run.sh tools/saturn/probe_supers_effecttiles.lua 60
-- (without it the fireball renders with Uranus's effect tiles — still visible).
-- Her REAL PALETTE is applied automatically (embedded in the ROM, injected into
-- the CGRAM shadow at transform).
-- STALE-GAP NOTE (cleared 2026-08-04): her moves are NOT silent (sound landed in
-- v0.7.0, her own voice in v0.13.0), throws and desperation ARE verified (0.11.2
-- desperation, 0.11.3 win screen, 0.14.7-0.14.9 throws incl. command grabs), and
-- P2 can be Saturn too (P2_ALSO below, or L+R on pad 2). Parked, not gaps:
-- approximate sfx mapping, shell-dependent voice pitch, and balance —
-- docs/saturn/PROJECT.md "Parked".
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local P2_ALSO = false   -- set true for a Saturn MIRROR match (P2 transforms too;
                        -- P2's fireball art + palette use P2 slots automatically)
local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local function w(a, v) emu.write(a, v, WRAM) end

local wasSaturn = false
local tilesDone = false
local buildVer = nil
local function readVersion()
  local PRG = emu.memType.snesPrgRom
  local out = {}
  for i = 0, 23 do
    local b = emu.read(0x2EC040 + i, PRG)
    if b == 0 then break end
    out[#out + 1] = string.char(b)
  end
  return #out > 0 and table.concat(out) or "UNVERSIONED BUILD"
end
local function uploadPalette()
  local PRG = emu.memType.snesPrgRom
  for i = 0, 31 do
    emu.write(0x0600 + i, emu.read(0x2EC000 + i, PRG), emu.memType.snesWorkRam)
  end
end
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
      uploadPalette()
    end
  end
  if P2_ALSO and inMatch and r(0x1080) ~= 0x1C and r(0x1081) <= 0x02 then
    w(0x1080, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do w(0x1080 + o, 0) end
    local PRG = emu.memType.snesPrgRom
    for i = 0, 31 do  -- P2 = OBJ palette 1 -> shadow $0620
      emu.write(0x0620 + i, emu.read(0x2EC000 + i, PRG), emu.memType.snesWorkRam)
    end
  end
  if wasSaturn then
    buildVer = buildVer or readVersion()
    emu.drawString(8, 12, "P1 = SAILOR SATURN [" .. buildVer .. "]"
      .. (tilesDone and "" or " (no effect tiles - see header)"), 0xFFFFFF, 0x000000)
  end
end, emu.eventType.endFrame)
print("saturn_test loaded — start a match; P1 becomes Saturn at round start")
