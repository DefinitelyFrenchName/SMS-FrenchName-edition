-- demo_link.lua — PROVE the patched infinite is a genuine 1-frame link.
--
-- Each attempt reloads the SAME savestate and replays the exact frame-advance-verified
-- sequence  2LP > 2HP > 66 > (follow-up 2LP),  pressing the follow-up 2LP on frame
-- (114 + LINK_OFFSET). Reloading guarantees byte-identical conditions every attempt, so
-- the only variable is that one press frame. The opponent takes the setup clean, then
-- holds DOWN-BACK to block the follow-up.
--
--    LINK_OFFSET =  0  -> only valid frame -> TRUE COMBO (hit lands during hitstun)
--    LINK_OFFSET = -1  -> 1 frame EARLY -> 2LP DROPPED (input lost in dash recovery)
--    LINK_OFFSET = +1  -> 1 frame LATE  -> P2 has RECOVERED; still CONNECTS as a same-frame
--                         MEATY (engine's hit-beats-same-frame-block rule), NOT a true combo
--    LINK_OFFSET = +2  -> 2 frames late -> cleanly BLOCKED (no damage)
-- The guaranteed TRUE COMBO is exactly one frame (offset 0). +1 still connects as a meaty
-- (beatable by an invincible reversal / jump-out), so the "connect" window is 2 frames.
--
-- USAGE (headless, reproducible):
--   ROM="build/SailorMoonS_FrenchName_v0.6_all5_truecombo.sfc" tools/run.sh tools/demo_link.lua
--   (wrappers demo_link_early.lua / demo_link_late.lua set the offset for you)
-- USAGE (Mesen GUI): open the v0.6 true-combo ROM, then Debug -> Script Window -> open a
--   wrapper -> Run. The demo loads traces/uranus_vs_jupiter_v06.mss itself (that state is
--   tagged to the v0.6 ROM; Mesen refuses a state tagged to a different ROM — that was the
--   earlier "won't run"). No match setup by hand needed.
-- Keys: R reset tally, S stop.

local OFFSET = LINK_OFFSET or 0
-- Savestate MUST be tagged to the ROM you have open, or Mesen's GUI refuses it. This one
-- is tagged to the v0.6 true-combo ROM. Override with LINK_STATE if you use another build.
local STATE  = LINK_STATE or "/Users/koneko/Developer/SailorMoonS/traces/uranus_vs_jupiter_v06.mss"

local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end

-- Exact verified sweep timing (absolute frames since state load). Follow-up 2LP @ 114+off.
local FV = 114 + OFFSET
local PLAN = {
  [10]={down=true}, [60]={down=true,y=true},[62]={down=true},
  [77]={down=true,x=true},[80]={down=true},
  [95]={},[97]={right=true},[98]={},[99]={right=true},[101]={},
  [FV]={down=true,y=true},[FV+2]={down=true},
}
local P2PLAN = { [10]={}, [100]={down=true,right=true} }   -- take setup, then block follow-up
local RESOLVE = FV + 16                                     -- attempt done; reload after this
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }
local function latched(plan, t)
  local best, bestk = {}, -1
  for k,v in pairs(plan) do if k <= t and k > bestk then best, bestk = v, k end end
  local b = {}; for kk,vv in pairs(FALSE) do b[kk]=vv end
  for kk,vv in pairs(best) do b[kk]=vv end
  return b
end

local t = -1
local needLoad = true
local attempts, combos, meaties, drops, blocks = 0, 0, 0, 0, 0
local seen53, sawBlock, hpRef, hitP2 = false, false, nil, nil
local lastVerdict = "..."
local driving = true
local hold = 0
local HOLD = (DEMO_LOG ~= nil) and 2 or 150   -- GUI: freeze ~2.5s on each result so it's readable

local keyPrev = {}
local function pressed(name)
  local ok, now = pcall(emu.isKeyPressed, name); if not ok then return false end
  local was = keyPrev[name]; keyPrev[name] = now; return now and not was
end

-- state (re)load must happen inside an exec callback on the main CPU
emu.addMemoryCallback(function()
  if needLoad then
    local f = io.open(STATE, "rb")
    if not f then emu.drawString(8, 80, "ERROR: savestate not found: "..STATE, 0xFF0000, 0x000000); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    needLoad = false; t = 0
    seen53, sawBlock, hpRef, hitP2 = false, false, nil, nil
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if not driving or t < 0 or hold > 0 then emu.setInput(FALSE,0,0); emu.setInput(FALSE,0,1); return end
  emu.setInput(latched(PLAN, t), 0, 0)
  emu.setInput(latched(P2PLAN, t), 0, 1)
end, emu.eventType.inputPolled)

local __log = (DEMO_LOG ~= nil) and io.open(DEMO_LOG, "w") or nil

local function drawHUD()
  local sign = OFFSET==0 and "+0  (only valid frame)"
            or (OFFSET>0 and "+"..OFFSET.." frame LATE" or OFFSET.." frame EARLY")
  local vcol = lastVerdict:find("TRUE COMBO") and 0x00FF00 or 0xFF4040
  emu.drawString(8, 8,  "1-FRAME-LINK PROOF  —  follow-up 2LP timing: "..sign, 0xFFFF00, 0x000000)
  emu.drawString(8, 17, "each attempt reloads the same state; only the press frame differs", 0xFFFFFF, 0x000000)
  emu.drawString(8, 26, "last attempt: "..lastVerdict, vcol, 0x000000)
  emu.drawString(8, 35, string.format("attempts %d  COMBO %d  meaty %d  dropped %d  blocked %d",
    attempts, combos, meaties, drops, blocks), 0xC0C0C0, 0x000000)
  local note = OFFSET==0 and "=> true combo (hit lands during hitstun)"
            or (OFFSET==1 and "=> +1 still CONNECTS as a same-frame meaty (not a true combo)"
            or  "=> off by "..OFFSET.." frames")
  emu.drawString(8, 44, note, vcol, 0x000000)
  emu.drawString(8, 200, hold>0 and "** RESULT (paused) — reloading... **" or "", 0xFFFF00, 0x000000)
  emu.drawString(8, 210, driving and "R reset   S stop" or "STOPPED — S resume", 0x808080, 0x000000)
end

emu.addEventCallback(function()
  if pressed("R") then attempts,combos,meaties,drops,blocks=0,0,0,0,0; lastVerdict="..." end
  if pressed("S") then driving = not driving end

  if hold > 0 then                         -- freeze on the result before reloading
    hold = hold - 1
    if hold == 0 then needLoad = true; t = -1 end
    drawHUD()
    return
  end
  if t < 0 then return end

  if t == 5 then emu.write(0x1021, 0xE8, WRAM) end   -- match trace.lua: snap P1 to point-blank

  local p1a, p2a, hp = r(0x1001), r(0x1081), r(0x10C9)
  if t == FV - 1 then hpRef = hp end
  if t >= FV and t <= FV + 14 then
    if p1a == 0x53 then seen53 = true end
    if p2a==0x0C or p2a==0x0D or p2a==0x0E or p2a==0x0F then sawBlock = true end
    -- record P2's action on the exact frame the follow-up connects (hp drops)
    if hpRef and hp < hpRef and hitP2 == nil then hitP2 = p2a end
  end

  if driving and t == RESOLVE then
    attempts = attempts + 1
    -- verdict keyed on P2's state ON the hit frame: hitstun = true combo; block state
    -- (0x0C-0F) but hp still dropped = same-frame meaty (P2 recovered, not a true combo).
    if not seen53 then lastVerdict="MOVE DROPPED (too early)"; drops=drops+1
    elseif hitP2 and hitP2>=0x10 and hitP2<=0x16 then lastVerdict="TRUE COMBO (hit in hitstun)"; combos=combos+1
    elseif hitP2 then lastVerdict="MEATY — connects but P2 RECOVERED (not a true combo)"; meaties=meaties+1
    elseif sawBlock then lastVerdict="BLOCKED (too late)"; blocks=blocks+1
    else lastVerdict="whiff / no connect"; drops=drops+1 end
    if __log then
      __log:write(string.format("attempt %d offset=%+d seen53=%s hitP2=%s block=%s -> %s\n",
        attempts, OFFSET, tostring(seen53), (hitP2 and string.format("%02X",hitP2) or "nil"), tostring(sawBlock), lastVerdict))
      if attempts >= 3 then
        __log:write("FINAL offset="..OFFSET.." verdict="..lastVerdict..
          " combos="..combos.." meaties="..meaties.." drops="..drops.." blocks="..blocks.."\n")
        __log:close(); __log=nil; emu.stop(0)
      end
    end
    hold = HOLD                    -- freeze on this result, then reload for the next attempt
  else
    t = t + 1
  end

  drawHUD()
end, emu.eventType.endFrame)

print("demo_link.lua loaded (LINK_OFFSET="..OFFSET.."). R reset, S stop.")
