-- probe_p11_kolatch.lua (patch 11): find the KO latch. Two identical sweep-KD scenarios
-- (mode 5): phase L = lethal (hp poked to 1), phase N = normal (hp 0x60). Logs P2 struct
-- $1080-$10FF at KD+2 / KD+30 / KD+58 for offline diff. Output: traces/p11_kolatch.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p11_kolatch.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local phase, pt, needLoad = 1, nil, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; pt = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local kdT = nil
local function dump(tag)
  local s = ""
  for a = 0x1080, 0x10FF do s = s .. string.format("%02X", ram(a)) end
  log(tag .. " " .. s)
end

emu.addEventCallback(function()
  if not pt then return end
  pt = pt + 1
  if pt == 5 then wr(0x8D, 5) end
  if pt == 10 then
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    wr(0x10A1, (p1x + 16) % 256); wr(0x10A2, math.floor((p1x + 16) / 256))
    if phase == 1 then wr(0x10C9, 0x01) end
  end
  if pt >= 24 and pt <= 25 then pulse[0] = { down = true, a = true } elseif pt == 26 then pulse[0] = nil end
  local a = ram(0x1081)
  if not kdT and (a == 0x19 or a == 0x1A) then kdT = pt end
  if kdT then
    if pt == kdT + 2 then dump((phase == 1 and "L" or "N") .. "+2 ") end
    if pt == kdT + 30 then dump((phase == 1 and "L" or "N") .. "+30") end
    if pt == kdT + 58 then dump((phase == 1 and "L" or "N") .. "+58") end
    if pt == kdT + 60 then
      if phase == 1 then
        phase = 2; pt = nil; needLoad = true; kdT = nil; pulse = {}
      else
        log("done"); emu.stop(0)
      end
    end
  end
  if pt and pt > 300 then log("TIMEOUT phase=" .. phase); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_p11_kolatch loaded")
