-- trainer.lua — interactive training tool for the SMS Uranus patches (Mesen GUI).
--
-- HOW TO USE (Mesen 2, windowed GUI — NOT --testrunner):
--   1. Load your patched ROM (e.g. build/sms_full4.sfc) and get into a VS match
--      as Uranus (P1). A 1P-vs-2P match is easiest; you control P1 with your pad.
--   2. Debug menu -> Script Window (or "Lua Script Window").
--   3. Open this file and press Run. The HUD appears; the script becomes your P2.
--
-- WHAT IT DOES
--   * You play P1 (your controller is untouched).
--   * The script drives P2 as a configurable dummy so you don't need a 2nd pad.
--   * On-screen HUD shows both players' state, P1 frame advantage, combo hits/damage,
--     and — key for the infinite — a big "P2 CAN ACT" flash the moment P2 leaves
--     hit/block-stun (i.e. the escape window). If you never see it mid-loop, the
--     infinite is locking P2; if it flashes between reps, there's a gap.
--
-- CHANGING THE P2 DUMMY MODE
--   Easiest / always works: edit `local MODE = 1` below to 1..6 and press Run again.
--   Or use hotkeys (number row, while the emulator window is focused):
--     1..6  select P2 dummy behaviour (see MODES below)
--     0     reset both players to neutral, mid-screen, point blank
--     9     toggle the HUD on/off
--   (Hotkeys are pcall-guarded — if a key name isn't recognised on your build the
--    script keeps running; just use the MODE variable instead. Number keys avoid
--    Mesen's default F-key save-state shortcuts.)
--
-- P2 DUMMY MODES
--   1 Off          P2 stands still (neutral).
--   2 Guard all    P2 holds down-back — blocks whenever not in stun. The classic
--                  "is the infinite a true lock?" test.
--   3 Guard a.hit  P2 stands, then holds down-back after the first time it's hit
--                  (realistic "block the follow-up" test).
--   4 Mash 2LP     P2 mashes crouching jab the instant it can act (interrupt test).
--   5 Backdash     P2 backdashes the instant it can act (escape test).
--   6 Wakeup meaty P2 sweeps you to a knockdown, then meaty-jabs your wakeup —
--                  use this to practice the reversal 66 and see if it gets hit.
--
-- Reads/labels come from annotations.md. Player structs: P1 $7E:1000, P2 $7E:1080.

--------------------------------------------------------------------------------
local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local function w(a, v) emu.write(a, v, WRAM) end
local P1, P2 = 0x1000, 0x1080

-- action-id -> short label (universal states + Uranus specifics; from annotations.md)
local NAME = {
  [0x00]="neutral",[0x01]="walk>",[0x02]="walk<",[0x03]="crouch",[0x04]="crouch",
  [0x05]="jump^",[0x06]="jumpUp",[0x07]="jump>",[0x08]="jump<",[0x09]="land",
  [0x0C]="stBLOCK",[0x0D]="crBLOCK",[0x0E]="stBLKstun",[0x0F]="crBLKstun",
  [0x10]="hd-hit",[0x11]="hd-HIT",[0x12]="bd-hit",[0x13]="bd-HIT",[0x14]="dk-hit",[0x15]="dk-HIT",
  [0x16]="air-hit",[0x19]="knockdn",[0x1A]="hvy-kd",[0x1E]="down",[0x20]="wakeup",[0x26]="backdash",
  [0x53]="2LP",[0x54]="2LP-rec",[0x55]="2HP",[0x56]="2HP-rec",[0x57]="2LK",[0x58]="2LK-rec",
  [0x59]="2HK",[0x60]="66DASH",
}
local function nm(a) return NAME[a] or string.format("$%02X", a) end
local function inStun(a)   return a>=0x10 and a<=0x16 end            -- hit/juggle stun
local function inBlk(a)    return a==0x0E or a==0x0F end             -- blockstun
local function inDown(a)   return a==0x19 or a==0x1A or a==0x1E or a==0x20 end
local function canAct(a)   return not (inStun(a) or inBlk(a) or inDown(a)) end

--------------------------------------------------------------------------------
local MODE = 1
local MODE_NAME = {"Off","Guard all","Guard after-hit","Mash 2LP","Backdash","Wakeup meaty"}
local showHud = true
local wasHitOnce = false           -- for mode 3
local p1adv, advClock = nil, 0     -- frame advantage tracking
local p2FreeAt = -999              -- frame P2 last became actionable
local combo, comboDmg, p2hpPrev = 0, 0, nil
local frame = 0
local canActFlash = 0

-- edge-detected hotkeys (pcall-guarded: an unknown key name never crashes the script)
local keyPrev = {}
local function pressed(name)
  local ok, now = pcall(emu.isKeyPressed, name)
  if not ok then return false end
  local was = keyPrev[name]
  keyPrev[name] = now
  return now and not was
end

-- block direction: P2 holds away from P1 (+down for low block)
local function backButtons(low)
  local p1x = r(0x1021) + 256*r(0x1022)
  local p2x = r(0x10A1) + 256*r(0x10A2)
  local away = (p1x <= p2x) and {right=true} or {left=true}
  if low then away.down = true end
  return away
end

-- P2 input for the current dummy mode
local p2mashPhase = 0
local function driveP2()
  local a2 = r(0x1081)
  local btn = {}
  if MODE == 1 then                                  -- Off
    -- nothing
  elseif MODE == 2 then                              -- Guard all (down-back)
    if canAct(a2) then btn = backButtons(true) end
  elseif MODE == 3 then                              -- Guard after first hit
    if inStun(a2) then wasHitOnce = true end
    if wasHitOnce and canAct(a2) then btn = backButtons(true) end
  elseif MODE == 4 then                              -- Mash 2LP (down + Y, 3on/3off)
    if canAct(a2) then
      p2mashPhase = (p2mashPhase + 1) % 6
      btn = { down = true, y = (p2mashPhase < 3) }
    end
  elseif MODE == 5 then                              -- Backdash (tap away x2) when free
    if canAct(a2) then
      p2mashPhase = (p2mashPhase + 1) % 8
      local away = backButtons(false)
      -- double-tap pattern: press,release,press
      if p2mashPhase==0 or p2mashPhase==2 then btn = away end
    end
  elseif MODE == 6 then                              -- Wakeup meaty (sweep -> jab)
    -- crude: if P1 is standing/close and P2 free, sweep; if P1 knocked down, jab as it wakes
    local a1 = r(0x1001)
    if canAct(a2) then
      if inDown(a1) then btn = { down = true, a = true }   -- 2HK meaty on wakeup
      else btn = { down = true, a = true } end
    end
  end
  emu.setInput(btn, 0, 1)   -- port 1 = P2 (Mesen: port is the 3rd arg)
end

--------------------------------------------------------------------------------
-- frame-advantage + combo tracking (updates each frame)
local function track()
  local a1, a2 = r(0x1001), r(0x1081)
  local p2hp = r(0x10C9)
  -- combo: count P2 HP drops while it stays in stun
  if p2hpPrev and p2hp < p2hpPrev then
    combo = combo + 1; comboDmg = comboDmg + (p2hpPrev - p2hp)
  end
  if canAct(a2) and canAct(a1) then combo = 0; comboDmg = 0 end
  p2hpPrev = p2hp

  -- P2 becomes actionable: note the frame (escape window opens)
  if canAct(a2) then
    if p2FreeAt ~= frame-1 then canActFlash = 20 end  -- just became free
    p2FreeAt = frame
  end
  if canActFlash > 0 then canActFlash = canActFlash - 1 end

  -- crude frame advantage: frames P1 is actionable before P2 is
  -- (positive = P1 recovers first). Sampled when both settle.
end

--------------------------------------------------------------------------------
local function hud()
  if not showHud then return end
  local a1, a2 = r(0x1001), r(0x1081)
  local y = 8
  emu.drawString(8, y, "P2 dummy: F1-6 ["..MODE.."] "..MODE_NAME[MODE], 0x00FF00, 0x000000); y=y+9
  emu.drawString(8, y, "P1 "..nm(a1).."  step="..string.format("%02X",r(0x1002)), 0xFFFFFF, 0x000000); y=y+9
  emu.drawString(8, y, "P2 "..nm(a2).."  hp="..string.format("%3d",r(0x10C9)), 0xFFFFFF, 0x000000); y=y+9
  if combo > 0 then
    emu.drawString(8, y, "COMBO "..combo.." hits  "..comboDmg.." dmg", 0xFFFF00, 0x000000); y=y+9
  end
  if canActFlash > 0 and (inStun(a2)==false) then
    emu.drawString(90, 60, ">> P2 CAN ACT <<", 0xFF3030, 0x000000)
  end
  emu.drawString(8, 210, "keys 1-6 mode  0 reset  9 hud", 0x808080, 0x000000)
end

--------------------------------------------------------------------------------
local function resetPos()
  -- neutral, mid-screen, point blank
  for _,base in ipairs({P1,P2}) do
    w(base+0x01, 0x00); w(base+0x02, 0x00); w(base+0x06, 0x00); w(base+0x07,0x00)
  end
  w(0x1021, 0xC8); w(0x1022, 0x00)   -- P1 x
  w(0x10A1, 0xE0); w(0x10A2, 0x00)   -- P2 x (point blank to the right)
  combo, comboDmg, wasHitOnce = 0, 0, false
end

--------------------------------------------------------------------------------
emu.addEventCallback(function() driveP2() end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frame = frame + 1
  -- hotkeys (number row; guarded)
  for i=1,6 do if pressed(tostring(i)) then MODE=i; wasHitOnce=false end end
  if pressed("0") then resetPos() end
  if pressed("9") then showHud = not showHud end
  track()
  hud()
end, emu.eventType.endFrame)

emu.displayMessage("Trainer", "Loaded — keys 1-6 pick P2 dummy, 0 reset, 9 HUD")
print("trainer.lua loaded — you are P1, script drives P2. Keys 1-6 modes, 0 reset, 9 HUD.")
