-- techsweep.lua — throw-tech window measurement (auto sweep, headless or GUI).
--
-- Reloads the same savestate before each attempt; the THROWER performs a proximity throw
-- (forward+HP point-blank) at a fixed frame, and the DEFENDER presses the tech buttons on
-- exactly one swept frame F. Each attempt is classified:
--   TECHED  = defender reached action 0x23 (throw tech) — logs the frame it happened
--   THROWN  = throw ran its course (defender tossed 0x1B/0x1D and/or lost HP), no tech
--   NOTHROW = the throw never connected (defender never entered Held 0x1C) — e.g. the
--             pre-connect press made the defender do a move and the grab whiffed
-- Output: one line per F plus a TECH window summary, written to traces/<OUT>.
--
-- Config via tools/techsweep_cfg.lua (dofile'd; all optional, defaults below):
--   STATE    savestate in traces/ (default "venus_vs_jupiter_clean.mss")
--   THROWER  0 = P1 throws (default), 1 = P2 throws (defender is the other port)
--   TFRAME   frame the throw button is pressed (default 60)
--   F_LO,F_HI  defender press-frame sweep range (default TFRAME-5 .. TFRAME+45)
--   TECH     defender button table (default {y=true,b=true} = LP+LK)
--   TECHMODE "press" 1-frame press (default) | "hold" press at F and hold to attempt end
--   MASH     if >1, repeat the 1-frame press MASH times every MASHGAP frames (default 1/4)
--   OUT      output file name (default "techsweep_out.txt")
--   WATCH    length of the per-attempt observation window after TFRAME (default 110)
--   VARY     "F" (default) sweeps the press frame F_LO..F_HI with MASH presses each,
--            "MASH" fixes the press frame at FFIX (default TFRAME+1) and sweeps the
--            press count M_LO..M_HI (defaults 1..25) to find the mash threshold
--
-- USE (headless): edit techsweep_cfg.lua, then  ROM=<rom> tools/run.sh tools/techsweep.lua 600
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
pcall(dofile, ENV.TOOLS .. "techsweep_cfg.lua")

STATE    = STATE or "venus_vs_jupiter_clean.mss"
THROWER  = THROWER or 0
TFRAME   = TFRAME or 60
F_LO     = F_LO or (TFRAME - 5)
F_HI     = F_HI or (TFRAME + 45)
TECH     = TECH or { y=true, b=true }
TECHMODE = TECHMODE or "press"
MASH     = MASH or 1
MASHGAP  = MASHGAP or 4
OUT      = OUT or "techsweep_out.txt"
WATCH    = WATCH or 110
VARY     = VARY or "F"
FFIX     = FFIX or (TFRAME + 1)
M_LO     = M_LO or 1
M_HI     = M_HI or 25

local PL = ENV.dofile("probelib.lua")   -- shared emulator-access helpers (#34)
local WRAM = PL.WRAM
local r = PL.ram
local FALSE = PL.FALSE_PAD

local DEF = (THROWER == 0) and 1 or 0            -- defender port
local thrBase = (THROWER == 0) and 0x1000 or 0x1080
local defBase = (THROWER == 0) and 0x1080 or 0x1000
-- side is derived from live positions at each attempt start (issue #47) — a fixed
-- "P1 left / P2 right" assumption gives false NOTHROW on crossed-up savestates
local function posx(b) return r(b + 0x21) + 256 * r(b + 0x22) end
local fwd = "right"
local function deriveSide() fwd = (posx(thrBase) <= posx(defBase)) and "right" or "left" end

local function throwerBtn(t)
  local b = {}; for k,v in pairs(FALSE) do b[k]=v end
  if t >= TFRAME and t < TFRAME+3 then b[fwd]=true; b.x=true end
  return b
end

local curMash = MASH

local function defenderBtn(t, F)
  local b = {}; for k,v in pairs(FALSE) do b[k]=v end
  local on = false
  if TECHMODE == "hold" then
    on = (t >= F)
  else
    for i = 0, curMash-1 do
      local p = F + i*MASHGAP
      if t == p then on = true end
    end
  end
  if on then for k,v in pairs(TECH) do b[k]=v end end
  return b
end

-- sweep state: candidates are press frames (VARY="F") or press counts (VARY="MASH")
local cands = {}
if VARY == "MASH" then for m=M_LO,M_HI do cands[#cands+1]=m end
else for f=F_LO,F_HI do cands[#cands+1]=f end end
local idx = 1
local results, connectAt, techAt = {}, {}, {}
local t, needLoad = -1, true
local F = (VARY == "MASH") and FFIX or cands[1]
if VARY == "MASH" then curMash = cands[1] end
local sawHeld, sawTech, sawToss, hpRef, hpEnd, techFrame, connectFrame = false,false,false,nil,nil,nil,nil
local log = assert(io.open(TRACE .. OUT, "w"), "techsweep.lua: cannot open " .. (TRACE .. OUT))

local function resetAttempt()
  sawHeld, sawTech, sawToss, hpRef, hpEnd, techFrame, connectFrame = false,false,false,nil,nil,nil,nil
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. STATE, "rb"), "techsweep: missing savestate " .. TRACE .. STATE)
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    needLoad = false; t = 0; resetAttempt()
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then emu.setInput(FALSE,0,0); emu.setInput(FALSE,0,1); return end
  local ti = throwerBtn(t)
  local di = defenderBtn(t, F)
  if THROWER == 0 then emu.setInput(ti,0,0); emu.setInput(di,0,1)
  else                 emu.setInput(di,0,0); emu.setInput(ti,0,1) end
end, emu.eventType.inputPolled)

local function classify()
  if sawTech then return "TECHED" end
  if not sawHeld then return "NOTHROW" end
  if sawToss or (hpRef and hpEnd and hpEnd < hpRef) then return "THROWN" end
  return "HELD?"                                    -- connected but neither tossed nor teched (odd)
end

emu.addEventCallback(function()
  if t < 0 then return end
  if t == 5 then emu.write(0x1021, 0xE8, WRAM) end  -- point-blank spacing
  if t == TFRAME - 1 then hpRef = r(defBase + 0x49); deriveSide() end
  if t >= TFRAME - 1 then
    local da = r(defBase + 0x01)
    if da == 0x1C then sawHeld = true; if not connectFrame then connectFrame = t end end
    if da == 0x23 and not sawTech then sawTech = true; techFrame = t end
    if da == 0x1B or da == 0x1D then sawToss = true end
    hpEnd = r(defBase + 0x49)
  end
  if t == TFRAME + WATCH then
    local v = classify()
    local key = (VARY == "MASH") and curMash or F
    results[key] = v; connectAt[key] = connectFrame; techAt[key] = techFrame
    log:write(string.format("%s=%03d %-7s connect=%s tech_at=%s hp=%02X->%02X\n",
      (VARY=="MASH") and "M" or "F", key, v, tostring(connectFrame), tostring(techFrame),
      hpRef or 0, hpEnd or 0))
    log:flush()
    idx = idx + 1
    if idx > #cands then
      local w = {}
      for _,f in ipairs(cands) do if results[f]=="TECHED" then w[#w+1]=f end end
      if #w > 0 then
        if VARY == "MASH" then
          log:write(string.format("TECH at %d..%d presses (from frame %d, gap %d)\n",
            w[1], w[#w], FFIX, MASHGAP))
        else
          log:write(string.format("TECH window: [%d..%d] = %d frame(s); connect=%s; window rel connect: [%+d..%+d]\n",
            w[1], w[#w], #w, tostring(connectAt[w[1]]),
            w[1]-(connectAt[w[1]] or w[1]), w[#w]-(connectAt[w[#w]] or w[#w])))
        end
        -- contiguity check
        local gaps = {}
        for i=2,#w do if w[i] ~= w[i-1]+1 then gaps[#gaps+1] = w[i-1].."/"..w[i] end end
        log:write("contiguous: " .. (#gaps==0 and "yes" or ("NO gaps at "..table.concat(gaps,","))) .. "\n")
      else
        log:write("TECH: none\n")
      end
      log:close()
      emu.stop(0)
    else
      if VARY == "MASH" then curMash = cands[idx] else F = cands[idx] end
      needLoad = true; t = -1
      return
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("techsweep loaded: " .. STATE .. " thrower=P" .. (THROWER+1) .. " F=" .. F_LO .. ".." .. F_HI)
