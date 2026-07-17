-- probe_p12_acts.lua (patch 12, P1): pratfall act audit. Config probe_p12_acts_cfg.lua:
--   STATE = savestate; ACTS = { {player=1|2, act=0xNN}, ... }  (forced sequentially)
-- For each entry: force the act (proven write set) on a neutral fighter, log the act
-- timeline until it returns to neutral (or 300f timeout), report duration, whether a
-- hitbox ever appeared (+0x40), and screenshot mid-anim.
-- Output: appends traces/p12_acts.txt (+ p12_act_<state>_<p>_<act>.png)
dofile("/Users/koneko/Developer/SailorMoonS/tools/probe_p12_acts_cfg.lua")
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p12_acts.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
  emu.setInput(base, 0, 0); emu.setInput(base, 0, 1)
end, emu.eventType.inputPolled)

local idx, phase, startT, sawHB, actSeq = 1, "wait", 0, false, {}
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  local e = ACTS[idx]
  if not e then log("=== done " .. STATE); emu.stop(0); return end
  local b = (e.player == 1) and 0x1000 or 0x1080
  if phase == "wait" then
    if t >= 30 and ram(b + 1) == 0 then
      wr(b + 1, e.act); wr(b + 2, 1); wr(b + 4, e.act); wr(b + 6, 0); wr(b + 7, 0)
      phase = "run"; startT = t; sawHB = false; actSeq = { e.act }
    elseif t > 200 then
      log(string.format("%s p%d act%02X SKIP (fighter never neutral)", STATE, e.player, e.act))
      idx = idx + 1; phase = "wait"
    end
  else
    local a = ram(b + 1)
    if a ~= actSeq[#actSeq] then actSeq[#actSeq + 1] = a end
    if ram(b + 0x40) ~= 0 then sawHB = true end
    if t == startT + 15 then
      local f = io.open(TRACE .. string.format("p12_act_%s_p%d_%02X.png",
        STATE:gsub("%.mss", ""), e.player, e.act), "wb")
      f:write(emu.takeScreenshot()); f:close()
    end
    if a == 0 or a == 3 then
      local seq = ""
      for _, v in ipairs(actSeq) do seq = seq .. string.format(" %02X", v) end
      log(string.format("%s p%d(cid%d) act%02X: dur=%d hitbox=%s seq=%s",
        STATE, e.player, ram(b), e.act, t - startT, tostring(sawHB), seq))
      idx = idx + 1; phase = "wait"; t = 20   -- allow next entry after brief settle
    elseif t > startT + 300 then
      local seq = ""
      for _, v in ipairs(actSeq) do seq = seq .. string.format(" %02X", v) end
      log(string.format("%s p%d(cid%d) act%02X: TIMEOUT (stuck) seq=%s",
        STATE, e.player, ram(b), e.act, seq))
      idx = idx + 1; phase = "wait"; t = 20
    end
  end
end, emu.eventType.endFrame)
print("probe_p12_acts loaded")
