-- techfind.lua — instrumentation for locating the throw-tech (mash-escape) machinery.
--
-- Runs ONE scripted throw (P1 throws at t=60, P2 mashes HK gap-2 from t=61 → will tech)
-- and logs:
--   * every write to the DEFENDER's actionID (+0x01) with the writer's PC (catches the
--     Held 0x1C setter and the tech 0x23 commit)
--   * a per-frame dump of BOTH player structs (0x1000-0x10FF) from t=DUMP_LO..DUMP_HI
--     so the mash counter can be found by diffing frames around press edges
-- Output: traces/techfind.txt (+ struct dump traces/techfind_dump.txt)
--
-- Config via tools/techfind_cfg.lua (optional): STATE, TFRAME, MASH, MASHGAP, NOMASH
-- USE: ROM=<rom> tools/run.sh tools/techfind.lua 120
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
pcall(dofile, ENV.TOOLS .. "techfind_cfg.lua")

STATE   = STATE or "venus_vs_jupiter_clean.mss"
TFRAME  = TFRAME or 60
MASH    = MASH or 10
MASHGAP = MASHGAP or 2
NOMASH  = NOMASH or false
DUMP_LO = DUMP_LO or (TFRAME - 3)
DUMP_HI = DUMP_HI or (TFRAME + 45)

local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

local log  = io.open(TRACE .. "techfind.txt", "w")
local dump = io.open(TRACE .. "techfind_dump.txt", "w")
local t, needLoad = -1, true

local function pcstr()
  local ok, st = pcall(emu.getState)
  if not ok then return "?" end
  local pc = st["cpu.pc"] or st["snes.cpu.pc"]
  local k  = st["cpu.k"]  or st["snes.cpu.k"]
  if pc == nil then
    -- fall back: scan for any key containing "pc"
    local parts = {}
    for kk, vv in pairs(st) do
      if type(kk)=="string" and kk:lower():find("pc") then parts[#parts+1] = kk.."="..tostring(vv) end
    end
    return table.concat(parts, " ")
  end
  return string.format("%02X:%04X", k or 0, pc)
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = io.open(TRACE .. STATE, "rb")
    if not f then return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

-- watch every write to defender (P2) actionID
emu.addMemoryCallback(function(addr, value)
  if t >= 0 then
    log:write(string.format("t=%03d WRITE 1081 <= %02X @ %s\n", t, value or -1, pcstr()))
  end
end, emu.callbackType.write, 0x1081, 0x1081, emu.cpuType.snes, emu.memType.snesWorkRam)

-- watch the thrower's mash counter (+0x56) and the defender's decoded buttons (+0x50)
emu.addMemoryCallback(function(addr, value)
  if t >= 0 then
    log:write(string.format("t=%03d WRITE 1056 <= %02X @ %s [p2_50=%02X]\n",
      t, value or -1, pcstr(), r(0x10D0)))
  end
end, emu.callbackType.write, 0x1056, 0x1056, emu.cpuType.snes, emu.memType.snesWorkRam)

-- log every time the mash-sampling instruction runs (lda $0050,Y at $C1:07D3):
-- reached only when the drag routine is called with $05 != 0 → these are the exact
-- frames a tech press can count on.
emu.addMemoryCallback(function()
  if t >= 0 then
    log:write(string.format("t=%03d SAMPLE p2_50=%02X cnt=%02X thr07=%02X thr02=%02X\n",
      t, r(0x10D0), r(0x1056), r(0x1007), r(0x1002)))
  end
end, emu.callbackType.exec, 0xC107D3, 0xC107D3, emu.cpuType.snes, emu.memType.snesMemory)

-- optionally watch ROM reads of the throw script region (set SCRIPT_LO/HI in cfg)
if SCRIPT_LO then
  local seen = {}
  emu.addMemoryCallback(function(addr)
    if t >= 0 then
      local key = t .. ":" .. addr
      if not seen[key] then
        seen[key] = true
        log:write(string.format("t=%03d SCRIPTREAD %06X (base+%02X)\n", t, addr, addr - SCRIPT_LO))
      end
    end
  end, emu.callbackType.read, SCRIPT_LO, SCRIPT_HI, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  if t < 0 then emu.setInput(FALSE,0,0); emu.setInput(FALSE,0,1); return end
  local p1 = {}; for k,v in pairs(FALSE) do p1[k]=v end
  if t >= TFRAME and t < TFRAME+3 then p1.right=true; p1.x=true end
  local p2 = {}; for k,v in pairs(FALSE) do p2[k]=v end
  if not NOMASH then
    for i=0,MASH-1 do if t == TFRAME+1+i*MASHGAP then p2.a=true end end
  end
  emu.setInput(p2,0,1); emu.setInput(p1,0,0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  if t == 5 then emu.write(0x1021, 0xE8, WRAM) end
  if t >= DUMP_LO and t <= DUMP_HI then
    for base = 0x1000, 0x1080, 0x80 do
      local row = {}
      for a = base, base + 0x7F do row[#row+1] = string.format("%02X", r(a)) end
      dump:write(string.format("t=%03d %04X: %s\n", t, base, table.concat(row, " ")))
    end
  end
  if t == DUMP_HI + 40 then
    log:close(); dump:close(); emu.stop(0)
  end
  t = t + 1
end, emu.eventType.endFrame)

print("techfind loaded")
