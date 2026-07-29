-- demo_link.lua — AUTO-CALIBRATING 1-frame-link proof (ROM-agnostic).
--
-- Sweeps the follow-up 2LP press frame across a range, reloading the same savestate before
-- each attempt so only the press frame varies, and classifies each by the opponent's action
-- ON the frame the hit connects. It then reports the exact connect window for whatever gate
-- the loaded ROM has — no hand-tuned "valid frame". Works on the N=6 (v0.7, 1-frame meaty)
-- and N=5 (v0.6, true combo) builds alike.
--
--   DROP  = 2LP never comes out (pressed too early; edge lost in dash recovery)
--   COMBO = hit while opponent in HITSTUN  -> true combo (inescapable)
--   MEATY = hit while opponent has RECOVERED (block/neutral) -> connects via the engine's
--           hit-beats-same-frame-block rule; unblockable by holding back, but an invincible
--           reversal / jump-out escapes it
--   BLOCK = opponent fully guarding -> no damage
--
-- USE (Mesen GUI): open the ROM, Debug -> Script Window -> open this file -> Run. It loads a
--   matching savestate itself. Default is the v0.7 canonical ROM; for another build pass
--   LINK_STATE = "<path to a state tagged to THAT rom>". Set LINK_OFFSET = n to instead loop
--   a single attempt at (valid frame + n) with a big on-screen verdict (wrappers do this).
-- USE (headless): ROM=<rom> tools/run.sh tools/demo_link.lua
-- Keys: R re-run, S stop.

local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local STATE  = LINK_STATE or ENV.TRACE .. "uranus_vs_jupiter_v07.mss"
local OFFSET = LINK_OFFSET          -- nil => full-sweep report; number => single-offset demo
local F_LO, F_HI = 108, 122         -- press-frame sweep range

local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

-- P1 sequence with the follow-up 2LP at press-frame FV (verified relative timing).
local function p1btn(t, FV)
  local kf = { {10,{down=true}}, {60,{down=true,y=true}},{62,{down=true}},
               {77,{down=true,x=true}},{80,{down=true}},
               {95,{}},{97,{right=true}},{98,{}},{99,{right=true}},{101,{}},
               {FV,{down=true,y=true}},{FV+2,{down=true}} }
  local best={}
  for _,e in ipairs(kf) do if e[1] <= t then best=e[2] end end
  local b={}; for k,v in pairs(FALSE) do b[k]=v end
  for k,v in pairs(best) do b[k]=v end
  return b
end
local function p2btn(t)   -- take the setup clean, then hold down-back from frame 100
  local b={}; for k,v in pairs(FALSE) do b[k]=v end
  b.down=true
  if t>=100 then b.right=true end
  return b
end

-- classify one completed attempt
local function classify(seen53, hitP2, sawBlock)
  if not seen53 then return "DROP" end
  if hitP2 and hitP2>=0x10 and hitP2<=0x16 then return "COMBO" end
  if hitP2 then return "MEATY" end        -- hp dropped but P2 not in hitstun => recovered
  if sawBlock then return "BLOCK" end
  return "WHIFF"
end

-- sweep state
local cands = {}; for f=F_LO,F_HI do cands[#cands+1]=f end
local results = {}            -- FV -> outcome
local idx = 1
local phase = "sweep"
local base = nil              -- earliest connecting frame (the "valid" frame)
local demoFV = nil

-- per-attempt tracking
local t = -1
local needLoad = true
local FV = cands[1]
local seen53, sawBlock, hpRef, hitP2 = false, false, nil, nil
local driving = true
local hold = 0
local __log = (DEMO_LOG ~= nil) and io.open(DEMO_LOG, "w") or nil

local keyPrev = {}
local function pressed(name)
  local ok, now = pcall(emu.isKeyPressed, name); if not ok then return false end
  local was = keyPrev[name]; keyPrev[name] = now; return now and not was
end

local function resetAttempt() seen53, sawBlock, hpRef, hitP2 = false, false, nil, nil end
local function restartSweep()
  results = {}; idx = 1; phase = "sweep"; base = nil; demoFV = nil
  FV = cands[1]; needLoad = true; t = -1
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = io.open(STATE, "rb")
    if not f then return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    needLoad = false; t = 0; resetAttempt()
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if not driving or t < 0 or hold > 0 or phase=="report" then
    emu.setInput(FALSE,0,0); emu.setInput(FALSE,0,1); return
  end
  emu.setInput(p1btn(t, FV), 0, 0)
  emu.setInput(p2btn(t), 0, 1)
end, emu.eventType.inputPolled)

-- once the sweep is done, compute the connect window and pick the demo frame
local function finishSweep()
  local combo, meaty = {}, {}
  for _,f in ipairs(cands) do
    if results[f]=="COMBO" then combo[#combo+1]=f end
    if results[f]=="MEATY" then meaty[#meaty+1]=f end
  end
  local connect = {}
  for _,f in ipairs(cands) do if results[f]=="COMBO" or results[f]=="MEATY" then connect[#connect+1]=f end end
  base = connect[1]
  if __log then
    local line = {}
    for _,f in ipairs(cands) do line[#line+1]=f..":"..(results[f] or "?") end
    __log:write(table.concat(line, " ").."\n")
    __log:write(string.format("CONNECT=%s COMBO=%s MEATY=%s base=%s\n",
      table.concat(connect,","), table.concat(combo,","), table.concat(meaty,","), tostring(base)))
    __log:close(); __log=nil; emu.stop(0); return
  end
  if OFFSET ~= nil and base then demoFV = base + OFFSET; phase="demo"; FV=demoFV; needLoad=true; t=-1
  else phase="report" end
end

emu.addEventCallback(function()
  if pressed("R") then restartSweep() end
  if pressed("S") then driving = not driving end

  if hold > 0 then
    hold = hold - 1
    if hold == 0 then needLoad = true; t = -1 end
  elseif t >= 0 and phase ~= "report" then
    local p1a, p2a, hp = r(0x1001), r(0x1081), r(0x10C9)
    if t == 5 then emu.write(0x1021, 0xE8, WRAM) end     -- point-blank
    if t == FV - 1 then hpRef = hp end
    if t >= FV and t <= FV + 14 then
      if p1a == 0x53 then seen53 = true end
      if p2a>=0x0C and p2a<=0x0F then sawBlock = true end
      if hpRef and hp < hpRef and hitP2 == nil then hitP2 = p2a end
    end
    if t == FV + 16 then
      local o = classify(seen53, hitP2, sawBlock)
      if phase == "sweep" then
        results[FV] = o
        idx = idx + 1
        if idx > #cands then finishSweep() else FV = cands[idx]; needLoad = true; t = -1 end
      else -- demo (single offset), loop with a hold to read it
        results[FV] = o; hold = 150
      end
    else
      t = t + 1
    end
  end

  -- ---------- HUD ----------
  local W = 0x00FF00
  if phase == "sweep" then
    emu.drawString(8, 8, "AUTO-CALIBRATING 1-frame-link window...", 0xFFFF00, 0x000000)
    emu.drawString(8, 17, string.format("testing press frame %d  (%d/%d)", FV, idx, #cands), 0xFFFFFF, 0x000000)
    emu.drawString(8, 26, "reloads the same state each attempt; opponent holds down-back", 0x808080, 0x000000)
  elseif phase == "demo" then
    local o = results[FV] or "?"
    local col = (o=="COMBO") and 0x00FF00 or (o=="DROP" or o=="MEATY") and 0xFFAA00 or 0xFF4040
    emu.drawString(8, 8, string.format("SINGLE-FRAME DEMO: press = valid %+d  (frame %d)", OFFSET, FV), 0xFFFF00, 0x000000)
    emu.drawString(8, 20, "result: "..o, col, 0x000000)
    emu.drawString(8, 200, hold>0 and "** paused on result **" or "", 0xFFFF00, 0x000000)
  else -- report
    emu.drawString(8, 8, "1-FRAME-LINK WINDOW (auto-measured)", 0xFFFF00, 0x000000)
    emu.drawString(8, 17, "DROP=no move  COMBO=hitstun  MEATY=recovered  BLOCK=guarded", 0x808080, 0x000000)
    local y, n = 28, 0
    local line = ""
    for _,f in ipairs(cands) do
      line = line .. string.format("%d:%-5s ", f, results[f] or "?"); n = n + 1
      if n % 4 == 0 then emu.drawString(8, y, line, 0xC0C0C0, 0x000000); y = y + 9; line = "" end
    end
    if line ~= "" then emu.drawString(8, y, line, 0xC0C0C0, 0x000000); y = y + 9 end
    local combo, meaty, connect = {}, {}, {}
    for _,f in ipairs(cands) do
      if results[f]=="COMBO" then combo[#combo+1]=f end
      if results[f]=="MEATY" then meaty[#meaty+1]=f end
      if results[f]=="COMBO" or results[f]=="MEATY" then connect[#connect+1]=f end
    end
    y = y + 4
    emu.drawString(8, y, "true-combo frames: "..(#combo>0 and table.concat(combo,",") or "none"), 0x00FF00, 0x000000); y=y+9
    emu.drawString(8, y, "meaty frames:      "..(#meaty>0 and table.concat(meaty,",") or "none"), 0xFFAA00, 0x000000); y=y+9
    if #connect>0 then
      local lo, hi = connect[1], connect[#connect]
      emu.drawString(8, y, string.format("CONNECT window: %d frame(s)  [%d-1=%s, %d+1=%s]",
        #connect, lo, results[lo-1] or "?", hi, results[hi+1] or "?"), W, 0x000000); y=y+9
      local kind = (#combo>0 and #meaty==0) and "true-combo"
                or (#combo==0 and #meaty>0) and "MEATY (unblockable by block; reversal/jump escapes)"
                or "true-combo + meaty"
      emu.drawString(8, y, "=> "..kind, W, 0x000000)
    end
  end
  emu.drawString(8, 210, driving and "R re-run   S stop" or "STOPPED - S resume", 0x808080, 0x000000)
end, emu.eventType.endFrame)

print("demo_link.lua loaded (auto-calibrate"..(OFFSET and (", offset "..OFFSET) or "")..").")
