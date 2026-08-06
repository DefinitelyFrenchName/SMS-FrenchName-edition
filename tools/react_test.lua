-- react_test.lua — does a Sailor Mars (P2) wake-up reaction escape Uranus's frame-perfect
-- N=6 meaty (the 1-frame-link follow-up 2LP)?
--
-- Drives Uranus's setup 2LP > 2HP > 66 > meaty-2LP (follow-up on the calibrated meaty frame),
-- then has Mars attempt REACTION on the exact frame it leaves hitstun (its only actionable
-- frame). Reloads the same state each attempt so it's deterministic. Reports, per attempt,
-- whether Mars ESCAPED (no damage) or was HIT, and which state Mars reached on the hit frame.
--
--   REACTION (global, or a wrapper sets it):
--     "backdash" (reversal back-dash, back-back = right-right)
--     "njump"    (neutral jump, up)
--     "bjump"    (back jump, up-back = up+right)
--     "grab"     (6HP command grab, forward+HP = left+X)
--     "jab"      (2LP, down+LP = down+Y)
--
-- USE (Mesen GUI): open the v0.7 ROM, Script Window -> open a wrapper -> Run. Loads the
--   Uranus-vs-Mars state itself. Headless: ROM=<v0.7> tools/run.sh tools/react_reactname.lua
-- Keys: R reset, S stop.

local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local REACT = REACTION or "backdash"
-- Mars reactions use the Mars state; the Neptune DP uses the Neptune state.
local DEF_STATE = (REACT=="dp") and ENV.TRACE .. "uranus_vs_neptune_v07.mss"
              or (REACT=="chibi5lp") and ENV.TRACE .. "uranus_vs_chibi_v07.mss"
                                 or ENV.TRACE .. "uranus_vs_mars_v07.mss"
local STATE = REACT_STATE or DEF_STATE
local MFV   = REACT_MFV or 115        -- meaty press frame (frame-perfect); try 116 for "1 late"

local PL = ENV.dofile("probelib.lua")   -- shared emulator-access helpers (#34)
local WRAM = PL.WRAM
local r = PL.ram
local FALSE = PL.FALSE_PAD

-- Uranus P1: 2LP@60, 2HP@77, 66@97/99, meaty 2LP@MFV (verified relative timing)
local function p1btn(t)
  local kf = { {10,{down=true}}, {60,{down=true,y=true}},{62,{down=true}},
               {77,{down=true,x=true}},{80,{down=true}},
               {95,{}},{97,{right=true}},{98,{}},{99,{right=true}},{101,{}},
               {MFV,{down=true,y=true}},{MFV+2,{down=true}} }
  local best={}
  for _,e in ipairs(kf) do if e[1] <= t then best=e[2] end end
  local b={}; for k,v in pairs(FALSE) do b[k]=v end
  for k,v in pairs(best) do b[k]=v end
  return b
end

-- Mars P2 wake-up reactions (P2 on the right: back=right, forward=left; LP=Y, HP=X).
-- Inputs buffer across the hitstun->actionable transition at frame ~120.
local REACTS = {
  njump   = { {118,{up=true}},{119,{}},{120,{up=true}},{121,{up=true}},{122,{up=true}} },
  bjump   = { {118,{up=true,right=true}},{119,{right=true}},{120,{up=true,right=true}},{121,{up=true,right=true}} },
  jab     = { {117,{down=true}},{118,{down=true,y=true}},{119,{down=true}},{120,{down=true,y=true}},{121,{down=true}},{122,{down=true,y=true}} },
  grab    = { {117,{left=true}},{118,{left=true,x=true}},{119,{left=true}},{120,{left=true,x=true}},{121,{left=true}},{122,{left=true,x=true}} },
  backdash= { {116,{right=true}},{117,{}},{118,{right=true}},{119,{}},{120,{right=true}},{121,{}} },
  -- Neptune DP: 623+HP buffered through hitstun (forward=left, +X). Invincible from frame 2.
  dp      = { {113,{left=true}},{115,{down=true}},{117,{down=true,left=true}},
              {118,{down=true,left=true,x=true}},{119,{down=true,left=true,x=true}},
              {120,{down=true,left=true,x=true}},{121,{down=true,left=true,x=true}},{123,{}} },
  -- Chibi Moon 5LP (fastest poke, neutral+LP=Y). On wake-up its startup begins the frame
  -- AFTER the wake frame (120 is a neutral-return frame), so it can't contest the meaty.
  chibi5lp= { {117,{}},{118,{y=true}},{119,{}},{120,{y=true}},{121,{y=true}},{122,{y=true}} },
}
local function p2btn(t)
  local plan = REACTS[REACT] or {}
  local best={}
  for _,e in ipairs(plan) do if e[1] <= t then best=e[2] end end
  local b={}; for k,v in pairs(FALSE) do b[k]=v end
  for k,v in pairs(best) do b[k]=v end
  return b
end

local STATE_NAMES = {[0x00]="neutral",[0x26]="backdash",[0x0C]="stand-block",[0x0D]="crouch-block"}

local t = -1
local needLoad = true
local attempts = 0
local tally = { HIT=0, TRADE=0, WIN=0, BLOCK=0, ESCAPE=0 }
local hpStart, hitFrame, p2AtHit, moveSeen, p1Hurt, sawBlock = nil, nil, nil, nil, nil, false
local lastVerdict, lastKind = "...", nil
local driving = true
local hold = 0
local HOLD = (DEMO_LOG ~= nil) and 2 or 150
local __log = (DEMO_LOG ~= nil) and io.open(DEMO_LOG,"w") or nil

local keyPrev = {}
local function pressed(name)
  local ok, now = pcall(emu.isKeyPressed, name); if not ok then return false end
  local was = keyPrev[name]; keyPrev[name] = now; return now and not was
end

emu.addMemoryCallback(function()
  if needLoad then
    -- #80: an assert here is SWALLOWED — errors thrown inside a memory callback
    -- die without a message (so #46's fix never actually reported). print + stop.
    local f = io.open(STATE, "rb")
    if not f then print("react_test: missing savestate " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close(); emu.loadSavestate(ss)
    needLoad=false; t=0; hpStart=nil; hitFrame=nil; p2AtHit=nil; moveSeen=nil; p1Hurt=nil; sawBlock=false
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if not driving or t<0 or hold>0 then emu.setInput(FALSE,0,0); emu.setInput(FALSE,0,1); return end
  emu.setInput(p1btn(t),0,0); emu.setInput(p2btn(t),0,1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if pressed("R") then attempts=0; tally={HIT=0,TRADE=0,WIN=0,BLOCK=0,ESCAPE=0}; lastVerdict="..." end
  if pressed("S") then driving = not driving end
  if hold>0 then hold=hold-1; if hold==0 then needLoad=true; t=-1 end
  elseif t>=0 then
    if t==5 then emu.write(0x1021,0xE8,WRAM) end
    local p1a, p2a, hp = r(0x1001), r(0x1081), r(0x10C9)
    if t==100 then hpStart=hp end
    if t>=118 and t<=128 and p2a~=0x00 and (p2a<0x0C or p2a>0x18) then moveSeen=moveSeen or p2a end
    if hpStart and hp<hpStart and hitFrame==nil then hitFrame=t; p2AtHit=p2a end   -- P2 got hit
    if t>=120 and t<=128 and p2a>=0x0C and p2a<=0x0F then sawBlock=true end          -- P2 in a guard state
    -- Uranus hurt? whole hurt range 0x10-0x20: hitstun/flame/electric/knockdown/thrown/held/down
    if t>=121 and t<=145 and p1a>=0x10 and p1a<=0x20 and p1Hurt==nil then p1Hurt=p1a end
    if t==146 then
      attempts=attempts+1
      -- describe how Uranus got hurt, if she did
      local punish = p1Hurt and (
          (p1Hurt>=0x1B and p1Hurt<=0x1D) and "THROWN"
       or (p1Hurt==0x19 or p1Hurt==0x1A or p1Hurt==0x1E or p1Hurt==0x1F) and "knocked down"
       or "counter-hit") or nil
      local kind, verdict
      if hitFrame and p1Hurt then kind="TRADE"; verdict="TRADE — both hit ("..punish.." vs meaty)"
      elseif hitFrame then
        kind="HIT"
        local why = (p2AtHit==0x26) and "backdash out, no frame-1 invuln"
                 or (p2AtHit==0x00) and "meaty took the wake frame before the reaction became active"
                 or (p2AtHit==0x0C or p2AtHit==0x0D) and "reaction became block, meaty beat same-frame block"
                 or "reaction hit"
        verdict="HIT — meaty wins ("..why..")"
      elseif p1Hurt then kind="WIN"; verdict="REACTION WINS — Uranus "..punish
      elseif sawBlock then kind="BLOCK"; verdict="BLOCKED — reaction became a guard (no damage)"
      else kind="ESCAPE"; verdict="ESCAPED — reaction came out, both safe (whiff/no trade)" end
      tally[kind]=tally[kind]+1; lastVerdict=verdict; lastKind=kind
      if __log then
        __log:write(string.format("react=%s attempt=%d p2Hit=%s p2AtHit=%s p1Hurt=%s move=%s -> %s\n",
          REACT, attempts, tostring(hitFrame), (p2AtHit and string.format("%02X",p2AtHit) or "-"),
          (p1Hurt and string.format("%02X",p1Hurt) or "-"), (moveSeen and string.format("%02X",moveSeen) or "-"), verdict))
        if attempts>=2 then __log:write(string.format("FINAL react=%s HIT=%d TRADE=%d WIN=%d BLOCK=%d ESCAPE=%d\n",
          REACT, tally.HIT, tally.TRADE, tally.WIN, tally.BLOCK, tally.ESCAPE)); __log:close(); __log=nil; emu.stop(0) end
      end
      hold=HOLD
    else t=t+1 end
  end

  -- HUD  (HIT = meaty wins / bad for defender; WIN/TRADE/BLOCK/ESCAPE = defender not cleanly hit)
  local col = (lastKind=="HIT") and 0xFF4040 or (lastKind==nil) and 0xC0C0C0 or 0x00FF00
  local mfvtxt = (MFV==115) and "frame-perfect" or ("meaty press "..MFV)
  emu.drawString(8, 8,  "WAKE-UP REACTION vs N=6 meaty ("..mfvtxt..")", 0xFFFF00, 0x000000)
  emu.drawString(8, 17, "reaction: "..REACT, 0xFFFFFF, 0x000000)
  emu.drawString(8, 26, "last: "..lastVerdict, col, 0x000000)
  emu.drawString(8, 35, string.format("HIT %d  TRADE %d  WIN %d  BLOCK %d  ESCAPE %d",
    tally.HIT, tally.TRADE, tally.WIN, tally.BLOCK, tally.ESCAPE), 0xC0C0C0, 0x000000)
  emu.drawString(8, 200, hold>0 and "** paused on result **" or "", 0xFFFF00, 0x000000)
  emu.drawString(8, 210, driving and "R reset   S stop" or "STOPPED - S resume", 0x808080, 0x000000)
end, emu.eventType.endFrame)

print("react_test.lua loaded (REACTION="..REACT..").")
