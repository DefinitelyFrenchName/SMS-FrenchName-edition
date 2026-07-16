-- const.lua — addresses, tables, palettes, and probe-verified platform facts.
--
-- ── P-1 PROBE RESULTS (2026-07-16, tools/probe_api.lua / probe_input.lua / probe_hud.lua) ──
-- * emu.getInput(port) at the TOP of inputPolled returns the PHYSICAL pad only; it is
--   polluted by our own setInput only later in the same frame. Pipeline rule: read pads
--   first, then override. No cross-frame stickiness.
-- * Callback order per frame: inputPolled fires BEFORE the exec@$80:8353 joy_read.
-- * +0x4D = hitstop countdown (8→0 during a hit, anim ticks frozen while nonzero).
--   +0x43 = attack_connected LATCH — stays 1 long after the move ends; only trust its
--   0→1 edge during an attack.
-- * isKeyPressed: every key name errors in the headless testrunner (no keyboard) — always
--   pcall. GUI accepts digits/letters (trainer.lua precedent).
-- * ScriptHud (emu.drawSurface.scriptHud, scale 1-4): size comes from the video renderer →
--   degenerate headless (width 0). Layout must derive from getDrawSurfaceSize() per frame
--   and no-op when width < 300. takeScreenshot() does NOT composite ScriptHud.
-- * getDrawSurfaceSize() → {width, height, visibleWidth, visibleHeight, overscan{...}}.
-- * Font: ~6px/char, 9px line (emu.measureString("S4 A5 R4") = 48x9).
-- * Measured oracle (Venus 5LP point-blank, press t=60): act 0x40 step0 at t=60 (same
--   frame as poll), first hitbox t=64 (hit same frame), hitstop 8f t=65-72, recovery act
--   0x41 from t=76 with the hitbox persisting into its step-0 frame, neutral t=81,
--   defender act 0x12 hitstun until t=86 → advantage +6.

local C = {}

C.WRAM = emu.memType.snesWorkRam

-- player struct bases (fighters 1-2, projectile slots 3-4 share the layout)
C.BASE = { 0x1000, 0x1080 }
C.PROJ = { 0x1100, 0x1180 }
C.RAW_PAD = { 0x5C, 0x5E }        -- raw input words $7E:005C / $7E:005E
C.CAMERA_X = 0x0A00               -- $7E:0A00 camera/scroll word

-- struct offsets
C.OFF = {
  charID = 0x00, act = 0x01, step = 0x02, sprite = 0x05, tick = 0x06, frameIdx = 0x07,
  facing = 0x09, aflag = 0x18, posX = 0x21, posY = 0x25, hb = 0x40, hub = 0x41,
  coll = 0x42, connected = 0x43, atkID = 0x44, dmg = 0x45, hurt = 0x46, hp = 0x49,
  maxhp = 0x4A, hitstop = 0x4D, btnHeld = 0x50, actFlags = 0x54, mash = 0x56,
}

-- SNES pad-table keys (Mesen setInput / getInput)
C.PAD_KEYS = { "a","b","x","y","l","r","up","down","left","right","start","select" }
C.FALSE_PAD = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

-- game button semantics (verified): Y=LP, X=HP, B=LK, A=HK
-- normalized bitmask (matches +0x50 layout): 1=back 2=fwd 4=down 8=up
--                                            0x10=LP 0x20=LK 0x40=HP 0x80=HK
C.M_BACK, C.M_FWD, C.M_DOWN, C.M_UP = 0x01, 0x02, 0x04, 0x08
C.M_LP, C.M_LK, C.M_HP, C.M_HK = 0x10, 0x20, 0x40, 0x80
C.M_L, C.M_R = 0x100, 0x200
C.BTN_OF_KEY = { y = 0x10, b = 0x20, x = 0x40, a = 0x80, l = 0x100, r = 0x200 }
C.KEY_OF_BTN = { [0x10] = "y", [0x20] = "b", [0x40] = "x", [0x80] = "a",
                 [0x100] = "l", [0x200] = "r" }
C.BTN_LABEL = { [0x10] = "LP", [0x20] = "LK", [0x40] = "HP", [0x80] = "HK" }

C.CHAR_NAMES = { [1]="Moon", [2]="Mercury", [3]="Mars", [4]="Jupiter", [5]="Venus",
                 [6]="Uranus", [7]="Neptune", [8]="Pluto", [9]="ChibiMoon" }

-- universal action IDs
C.ACT_NAMES = {
  [0x00]="neutral", [0x01]="walk fwd", [0x02]="walk back", [0x03]="crouch",
  [0x04]="half crouch", [0x05]="prejump", [0x06]="jump up", [0x07]="jump fwd",
  [0x08]="jump back", [0x09]="landing", [0x0C]="stand block", [0x0D]="crouch block",
  [0x0E]="blockstun", [0x0F]="c.blockstun", [0x10]="hitstun hL", [0x11]="hitstun hH",
  [0x12]="hitstun bL", [0x13]="hitstun bH", [0x14]="hitstun dL", [0x15]="hitstun dH",
  [0x16]="air hitstun", [0x17]="flame", [0x18]="electric", [0x19]="knockdown",
  [0x1A]="knockdown H", [0x1B]="thrown", [0x1C]="held", [0x1D]="thrown",
  [0x1E]="down", [0x1F]="KO", [0x20]="stand up", [0x21]="neutral(low)",
  [0x22]="intro", [0x23]="throw tech", [0x24]="victory", [0x25]="freeze",
  [0x26]="backdash", [0x27]="slip", [0x28]="down", [0x29]="stand up",
  [0x2A]="embarrassed",
}

-- per-char cancellable light-recovery action IDs (engine-actionable "recovery")
-- charIDs 1-9 ONLY (Saturn is Sailor Moon Super S data — not this game).
local function set(l) local s = {}; for _, v in ipairs(l) do s[v] = true end; return s end
C.CANCELLABLE = {
  [1] = set{0x42,0x48,0x54,0x58}, [2] = set{0x41,0x46,0x53,0x57},
  [3] = set{0x42,0x49,0x55,0x59}, [4] = set{0x42,0x47,0x53,0x57},
  [5] = set{0x41,0x45,0x51,0x55}, [6] = set{0x42,0x48,0x54,0x58},
  [7] = set{0x41,0x45,0x56,0x5A}, [8] = set{0x41,0x49,0x55,0x59},
  [9] = set{0x41,0x47,0x53,0x57},
}

-- act predicates
function C.isNeutralAct(a) return a <= 0x04 or a == 0x0C or a == 0x0D or a == 0x21 end
function C.isAirAct(a) return a >= 0x05 and a <= 0x08 end
function C.isHitstunAct(a) return a >= 0x10 and a <= 0x18 end
function C.isBlockstunAct(a) return a == 0x0E or a == 0x0F end
function C.isBlockHoldAct(a) return a == 0x0C or a == 0x0D end
function C.isKDAct(a)
  return a == 0x19 or a == 0x1A or a == 0x1E or a == 0x1F or a == 0x20
      or a == 0x27 or a == 0x28 or a == 0x29
end
function C.isThrowVictimAct(a) return a == 0x1B or a == 0x1C or a == 0x1D end

-- frame classes (small ints; order used for palette lookup)
C.CLS = { NEUTRAL=1, MOVEMENT=2, STARTUP=3, ACTIVE=4, RECOVERY=5, RECOVERY_C=6,
          HITSTUN=7, BLOCKSTUN=8, BLOCKHOLD=9, KNOCKDOWN=10, THROWN=11, TECH=12,
          OTHER=13 }
C.CLS_NAME = {}
for k, v in pairs(C.CLS) do C.CLS_NAME[v] = k end

-- meter palette (0xRRGGBB)
C.CLS_COLOR = {
  [C.CLS.NEUTRAL]  = 0x3A3A42, [C.CLS.MOVEMENT]  = 0x565662,
  [C.CLS.STARTUP]  = 0x28B04C, [C.CLS.ACTIVE]    = 0xE03028,
  [C.CLS.RECOVERY] = 0x3058D8, [C.CLS.RECOVERY_C]= 0x5C8CF0,
  [C.CLS.HITSTUN]  = 0xF0D030, [C.CLS.BLOCKSTUN] = 0xB89820,
  [C.CLS.BLOCKHOLD]= 0x50627E, [C.CLS.KNOCKDOWN] = 0xB05818,
  [C.CLS.THROWN]   = 0x9038C8, [C.CLS.TECH]      = 0x30C0A8,
  [C.CLS.OTHER]    = 0x2A2A2E,
}
C.COL = {
  bg = 0x101014, text = 0xFFFFFF, dim = 0x808080, good = 0x40FF40, bad = 0xFF6060,
  warn = 0xFFFF00, accent = 0xFF80FF, invuln = 0xFFFFFF, cancel = 0xC0E0FF,
  black = 0x000000,
}

return C
