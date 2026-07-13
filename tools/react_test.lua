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

local REACT = REACTION or "backdash"
-- Mars reactions use the Mars state; the Neptune DP uses the Neptune state.
local DEF_STATE = (REACT=="dp") and "/Users/koneko/Developer/SailorMoonS/traces/uranus_vs_neptune_v07.mss"
              or (REACT=="chibi5lp") and "/Users/koneko/Developer/SailorMoonS/traces/uranus_vs_chibi_v07.mss"
                                 or "/Users/koneko/Developer/SailorMoonS/traces/uranus_vs_mars_v07.mss"
local STATE = REACT_STATE or DEF_STATE
local MFV   = REACT_MFV or 115        -- meaty press frame (frame-perfect); try 116 for "1 late"

local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

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
local attempts, escapes, hits = 0, 0, 0
local hpStart, hitFrame, p2AtHit, moveSeen, p1Hit = nil, nil, nil, nil, false
local lastVerdict = "..."
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
    local f = io.open(STATE, "rb"); if not f then return end
    local ss = f:read("*a"); f:close(); emu.loadSavestate(ss)
    needLoad=false; t=0; hpStart=nil; hitFrame=nil; p2AtHit=nil; moveSeen=nil; p1Hit=false
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if not driving or t<0 or hold>0 then emu.setInput(FALSE,0,0); emu.setInput(FALSE,0,1); return end
  emu.setInput(p1btn(t),0,0); emu.setInput(p2btn(t),0,1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if pressed("R") then attempts,escapes,hits=0,0,0; lastVerdict="..." end
  if pressed("S") then driving = not driving end
  if hold>0 then hold=hold-1; if hold==0 then needLoad=true; t=-1 end
  elseif t>=0 then
    if t==5 then emu.write(0x1021,0xE8,WRAM) end
    local p1a, p2a, hp = r(0x1001), r(0x1081), r(0x10C9)
    if t==100 then hpStart=hp end
    if t>=118 and t<=128 and p2a~=0x00 and (p2a<0x0C or p2a>0x16) and p2a~=0x13 then moveSeen=moveSeen or p2a end
    if hpStart and hp<hpStart and hitFrame==nil then hitFrame=t; p2AtHit=p2a end
    -- did Uranus (P1) get counter-hit? (hitstun 0x10-0x16 or knockdown 0x19/1A/1E/20 after the meaty)
    if t>=121 and t<=140 and ((p1a>=0x10 and p1a<=0x16) or p1a==0x19 or p1a==0x1A or p1a==0x1E or p1a==0x20) then p1Hit=true end
    if t==142 then
      attempts=attempts+1
      if REACT=="dp" then
        if hitFrame then lastVerdict="DP LOST — meaty hit its vulnerable frame 1"; hits=hits+1
        elseif p1Hit then lastVerdict="DP WON — Uranus counter-hit / knocked down"; escapes=escapes+1
        else lastVerdict="DP whiffed / traded (P2 unhurt, P1 safe)"; escapes=escapes+1 end
      elseif hitFrame==nil then lastVerdict="ESCAPED (no damage)"; escapes=escapes+1
      else
        local st = STATE_NAMES[p2AtHit] or string.format("state %02X",p2AtHit)
        local why = (p2AtHit==0x26) and "backdash came out (no frame-1 invuln)"
                 or (p2AtHit==0x00) and "meaty took the wake frame before the reaction became active"
                 or (p2AtHit==0x0C or p2AtHit==0x0D) and "reaction became a block, meaty beat same-frame block"
                 or "hit in "..st
        lastVerdict="HIT @"..hitFrame.." ("..why..")"; hits=hits+1
      end
      if __log then
        __log:write(string.format("react=%s attempt=%d hit=%s p2AtHit=%s moveSeen=%s -> %s\n",
          REACT, attempts, tostring(hitFrame), (p2AtHit and string.format("%02X",p2AtHit) or "nil"),
          (moveSeen and string.format("%02X",moveSeen) or "nil"), lastVerdict))
        if attempts>=2 then __log:write("FINAL react="..REACT.." escapes="..escapes.." hits="..hits.."\n"); __log:close(); __log=nil; emu.stop(0) end
      end
      hold=HOLD
    else t=t+1 end
  end

  -- HUD
  local esc = lastVerdict:find("ESCAPED")
  local col = esc and 0x00FF00 or 0xFF4040
  emu.drawString(8, 8,  "MARS WAKE-UP REACTION vs frame-perfect N=6 meaty", 0xFFFF00, 0x000000)
  emu.drawString(8, 17, "reaction: "..REACT, 0xFFFFFF, 0x000000)
  emu.drawString(8, 26, "last: "..lastVerdict, col, 0x000000)
  emu.drawString(8, 35, string.format("attempts %d   ESCAPED %d   HIT %d", attempts, escapes, hits), 0xC0C0C0, 0x000000)
  emu.drawString(8, 200, hold>0 and "** paused on result **" or "", 0xFFFF00, 0x000000)
  emu.drawString(8, 210, driving and "R reset   S stop" or "STOPPED - S resume", 0x808080, 0x000000)
end, emu.eventType.endFrame)

print("react_test.lua loaded (REACTION="..REACT..").")
