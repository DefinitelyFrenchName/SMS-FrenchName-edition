-- demo_truecombo.lua — prove the N=5 patch is a TRUE (unblockable) 1-frame link.
--
-- Same frame-perfect [2LP > 2HP > 66]xN loop as demo_infinite.lua, but P2 now
-- *tries to block*: it takes the very first hit clean, then holds DOWN-BACK
-- (crouch guard) for the rest of the demo. A true combo means those held-block
-- inputs never save P2 — it stays locked in hitstun and keeps taking damage.
--
--   * On the true-combo build (v0.6 / gate 0x05, N=5): P2 NEVER reaches a block
--     state; the "hits taken WHILE holding block" counter climbs every rep.
--   * On the frame-trap build (v0.5 / gate 0x04, N=6): P2 reaches crouch-block
--     (act 0x0D) between reps -> it blocks (act 0x0F blockstun) and the loop
--     stalls. The HUD flags the block in red so the difference is obvious.
--
-- HOW TO USE (Mesen 2 GUI):
--   1. Load a patched build and get into a VS match as Uranus (P1) vs anyone (P2),
--      match LIVE. Recommended: build/SailorMoonS_FrenchName_v0.6_all5_truecombo.sfc.
--      (Load the v0.5 ROM instead to watch the old frame-trap get blocked.)
--   2. Debug -> Script Window -> open this file -> Run.
--   Keys: R restart now, S stop driving.

local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local function w(a, v) emu.write(a, v, WRAM) end

local REP = 55                 -- one rep = 55 frames (identical to demo_infinite.lua)
local WARMUP = 20
-- rep-local frame -> P1 buttons (latched). Frame-perfect timing.
local SEQ = {
  [0]={down=true,y=true}, [2]={down=true},            -- 2LP
  [17]={down=true,x=true},[20]={down=true},           -- 2HP
  [35]={}, [37]={right=true},[38]={},[39]={right=true},[41]={},  -- 66
}
local OFFS = {}; for k in pairs(SEQ) do OFFS[#OFFS+1]=k end; table.sort(OFFS)
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

local t = 0
local playStart = WARMUP + 1
local combo, comboDmg, reps, p2hpPrev = 0, 0, 0, nil
local blocking = false         -- latched true after P2 eats the first hit
local hitsWhileBlocking = 0    -- damage instances that landed while P2 held block
local everBlocked = false      -- did P2 ever reach a real block/blockstun state?
local driving = true

local keyPrev = {}
local function pressed(name)
  local ok, now = pcall(emu.isKeyPressed, name); if not ok then return false end
  local was = keyPrev[name]; keyPrev[name] = now; return now and not was
end

local function reposition()
  for _,b in ipairs({0x1000, 0x1080}) do w(b+1,0); w(b+2,0); w(b+6,0); w(b+7,0) end
  w(0x1021, 0xE8); w(0x1022, 0)      -- P1 x (point-blank gap)
  w(0x10A1, 0x00); w(0x10A2, 0x01)   -- P2 x = 0x100  (P1 left of P2 -> P2 back = RIGHT)
end

local function restart()
  reposition()
  playStart = t + WARMUP
  combo, comboDmg, reps, p2hpPrev = 0, 0, 0, nil
  blocking, hitsWhileBlocking, everBlocked = false, 0, false
end

local function p1Input(lt)
  local last = {}
  for _,off in ipairs(OFFS) do if off <= lt then last = SEQ[off] else break end end
  local b = {}; for k,v in pairs(FALSE) do b[k]=v end
  for k,v in pairs(last) do b[k]=v end
  return b
end

-- P2: neutral crouch until the first hit lands, then hold DOWN-BACK (down+right,
-- since P1 is on the left) trying to block everything after.
local function p2Input()
  local b = {}; for k,v in pairs(FALSE) do b[k]=v end
  b.down = true
  if blocking then b.right = true end   -- down-back = crouch block attempt
  return b
end

local function p2StateName(act)
  if act == 0x0C or act == 0x0D then return "BLOCK(guard)", 0xFF4040 end
  if act == 0x0E or act == 0x0F then return "BLOCKSTUN",    0xFF4040 end
  if act >= 0x10 and act <= 0x16 then return "HITSTUN",     0x00FF00 end
  return string.format("act %02X", act), 0xC0C0C0
end

-- Optional headless self-test: set DEMO_STATE (savestate path) and DEMO_LOG (out file)
-- as globals before running; logs P2 state each frame so the harness can verify.
local __log = nil
if DEMO_STATE ~= nil then
  local __loaded = false
  emu.addMemoryCallback(function()
    if not __loaded then
      local f = io.open(DEMO_STATE, "rb"); local ss = f:read("*a"); f:close()
      emu.loadSavestate(ss); __loaded = true
      t = 0; playStart = WARMUP + 1
    end
  end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
  if DEMO_LOG ~= nil then __log = io.open(DEMO_LOG, "w") end
end

emu.addEventCallback(function()
  if not driving then
    emu.setInput(FALSE, 0, 0); emu.setInput(FALSE, 0, 1); return
  end
  if t >= playStart then
    emu.setInput(p1Input((t - playStart) % REP), 0, 0)
    emu.setInput(p2Input(), 0, 1)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  t = t + 1
  if pressed("R") then restart() end
  if pressed("S") then driving = not driving end

  if t == 5 then reposition() end
  local p2act = r(0x1081)
  if driving and t >= playStart then
    local lt = (t - playStart) % REP
    local hp = r(0x10C9)
    if p2hpPrev and hp < p2hpPrev then
      combo = combo + 1; comboDmg = comboDmg + (p2hpPrev - hp)
      -- the FIRST hit lands before block is held, so it must not count (#94)
      local wasBlocking = blocking
      blocking = true                                   -- after the first hit, start blocking
      if wasBlocking then hitsWhileBlocking = hitsWhileBlocking + 1 end
    end
    p2hpPrev = hp
    if p2act == 0x0C or p2act == 0x0D or p2act == 0x0E or p2act == 0x0F then
      if blocking then everBlocked = true end            -- P2 got to guard -> not a true combo
    end
    if lt == 0 and t > playStart then reps = reps + 1 end
    if lt == 50 and hp < 0x28 then restart() end
    if __log then
      __log:write(string.format("t=%03d lt=%02d P1=%02X P2=%02X hp=%02X blk=%s hitsBlk=%d everBlk=%s\n",
        t, lt, r(0x1001), p2act, hp, tostring(blocking), hitsWhileBlocking, tostring(everBlocked)))
      if t > playStart + REP*3 then __log:close(); __log=nil; emu.stop(0) end
    end
  end

  -- HUD
  local nm, col = p2StateName(p2act)
  emu.drawString(8, 8,  "DEMO: TRUE 1-frame-link combo (P2 blocks after 1st hit)", 0x00FF00, 0x000000)
  emu.drawString(8, 17, "[2LP > 2HP > 66] x N   P2 = HOLD DOWN-BACK", 0xFFFFFF, 0x000000)
  emu.drawString(8, 26, "reps "..reps.."   COMBO "..combo.." hits  "..comboDmg.." dmg", 0xFFFF00, 0x000000)
  emu.drawString(8, 35, "P2 state: "..nm.."   (holding block: "..tostring(blocking)..")", col, 0x000000)
  emu.drawString(8, 44, "hits taken WHILE holding block: "..hitsWhileBlocking, 0x00FF00, 0x000000)
  if everBlocked then
    emu.drawString(8, 53, "!! P2 REACHED BLOCK -> NOT a true combo (frame-trap build)", 0xFF4040, 0x000000)
  else
    emu.drawString(8, 53, "P2 never reaches block -> TRUE unblockable combo", 0x00FF00, 0x000000)
  end
  emu.drawString(8, 210, driving and "R restart   S stop" or "STOPPED — S resume", 0x808080, 0x000000)
end, emu.eventType.endFrame)

print("demo_truecombo.lua loaded — P2 tries to block after the first hit. R restart, S stop.")
