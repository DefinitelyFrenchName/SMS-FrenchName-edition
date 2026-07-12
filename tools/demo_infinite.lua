-- demo_infinite.lua — scripted playback of the frame-perfect 1-frame-link infinite.
--
-- Purpose: SHOW that the patched infinite still works when executed frame-perfectly
-- (it is a 1-frame link, not removed). Drives BOTH players — a demo to watch, not to
-- play. It is the exact timing a human/TAS would need per rep.
--
-- HOW TO USE (Mesen 2 GUI):
--   1. Load a patched build (build/sms_full5.sfc or sms_full4.sfc) and get into a VS
--      match as Uranus (P1) vs anyone (P2), match live. Any stage.
--   2. Debug -> Script Window -> open this file -> Run.
--   The script snaps both players to neutral point-blank and loops the infinite
--   [2LP > 2HP > 66]xN with P2 held in guard, auto-restarting before a KO.
--   Watch the combo counter: each rep is one frame-perfect jab link (1-frame window)
--   plus one frame-perfect 66.  Keys: R restart now, S stop driving.

local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local function w(a, v) emu.write(a, v, WRAM) end

local REP = 55                 -- one rep = 55 frames
local WARMUP = 20              -- frames to settle after a (re)position before playing
-- rep-local frame -> P1 buttons (latched). Verified frame-perfect timing.
local SEQ = {
  [0]={down=true,y=true}, [2]={down=true},            -- 2LP
  [17]={down=true,x=true},[20]={down=true},           -- 2HP
  [35]={}, [37]={right=true},[38]={},[39]={right=true},[41]={},  -- 66
}
local OFFS = {}; for k in pairs(SEQ) do OFFS[#OFFS+1]=k end; table.sort(OFFS)
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

local t = 0                    -- master frame counter (endFrame)
local playStart = WARMUP + 1   -- frame the current run starts playing
local combo, comboDmg, reps, p2hpPrev = 0, 0, 0, nil
local driving = true

local keyPrev = {}
local function pressed(name)
  local ok, now = pcall(emu.isKeyPressed, name); if not ok then return false end
  local was = keyPrev[name]; keyPrev[name] = now; return now and not was
end

local function reposition()
  for _,b in ipairs({0x1000, 0x1080}) do w(b+1,0); w(b+2,0); w(b+6,0); w(b+7,0) end
  w(0x1021, 0xE8); w(0x1022, 0)      -- P1 x (verified point-blank gap)
  w(0x10A1, 0x00); w(0x10A2, 0x01)   -- P2 x = 0x100  (facings kept as-is)
end

local function restart()
  reposition()
  playStart = t + WARMUP
  combo, comboDmg, reps, p2hpPrev = 0, 0, 0, nil
end

local function p1Input(lt)
  local last = {}
  for _,off in ipairs(OFFS) do if off <= lt then last = SEQ[off] else break end end
  local b = {}; for k,v in pairs(FALSE) do b[k]=v end
  for k,v in pairs(last) do b[k]=v end
  return b
end

-- Optional headless self-test: set global DEMO_STATE to a .mss path before this script
-- runs, and it loads that savestate and anchors the clock to it. Leave unset for normal
-- GUI use (you are already in a live match).
if DEMO_STATE ~= nil then
  local __loaded = false
  emu.addMemoryCallback(function()
    if not __loaded then
      local f = io.open(DEMO_STATE, "rb"); local ss = f:read("*a"); f:close()
      emu.loadSavestate(ss); __loaded = true
      t = 0; playStart = WARMUP + 1
    end
  end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  if not driving then
    emu.setInput(FALSE, 0, 0); emu.setInput(FALSE, 0, 1); return
  end
  if t >= playStart then
    emu.setInput(p1Input((t - playStart) % REP), 0, 0)   -- P1: the infinite
    -- P2: neutral for the first ~8 frames so the opening 2LP lands, THEN hold down-back
    -- guard — which can never come out, proving the loop is a true lock (not a blockstring).
    local p2 = {}; for k,v in pairs(FALSE) do p2[k]=v end
    if (t - playStart) >= 8 then p2.right = true; p2.down = true end
    emu.setInput(p2, 0, 1)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  t = t + 1
  if pressed("R") then restart() end
  if pressed("S") then driving = not driving end

  if t == 5 then reposition() end          -- initial snap
  if driving and t >= playStart then
    local lt = (t - playStart) % REP
    local hp = r(0x10C9)
    if p2hpPrev and hp < p2hpPrev then combo = combo + 1; comboDmg = comboDmg + (p2hpPrev - hp) end
    p2hpPrev = hp
    if lt == 0 and t > playStart then reps = reps + 1 end
    if lt == 50 and hp < 0x28 then restart() end          -- auto-restart before KO
  end

  -- HUD
  emu.drawString(8, 8,  "DEMO: frame-perfect 1-frame-link infinite", 0x00FF00, 0x000000)
  emu.drawString(8, 17, "[2LP > 2HP > 66] x N   (P2 = guard)", 0xFFFFFF, 0x000000)
  emu.drawString(8, 26, "reps "..reps.."   COMBO "..combo.." hits  "..comboDmg.." dmg", 0xFFFF00, 0x000000)
  emu.drawString(8, 35, "each jab link = a 1-FRAME window", 0xFF80FF, 0x000000)
  emu.drawString(8, 210, driving and "R restart   S stop" or "STOPPED — S resume", 0x808080, 0x000000)
end, emu.eventType.endFrame)

print("demo_infinite.lua loaded — watch the frame-perfect infinite. R restart, S stop.")
