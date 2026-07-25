-- probe_p10_vs.lua — patch-10 combo-counter pipeline diagnosis in 2P VS mode.
--
-- Loads traces/uranus_vs_jupiter.mss on a patch-10 ROM (headless: ROM=<p10 build>
-- tools/run.sh tools/probe_p10_vs.lua 120), plays [2LP > 2HP]x reps frame-perfect
-- (demo_infinite timing) vs a crouching dummy, and logs the whole display pipeline
-- per frame: $008D mode, P2 hp/act, combo block $08B0 (hits/free/ttl/shown/shadow),
-- LEFT staging $08D0 (dirty + 4 tile words), and the LEFT VRAM cells $10C2/3 $10E2/3.
-- Ends with a WHERE-IT-STALLS verdict. Out: traces/probe_p10_vs.txt

local WRAM = emu.memType.snesWorkRam
local VRAM = emu.memType.snesVideoRam
local function r(a) return emu.read(a, WRAM) end
local function w(a, v) emu.write(a, v, WRAM) end
local function rw(a) return r(a) + 256 * r(a + 1) end
local function vword(wa) return emu.read(wa * 2, VRAM) + 256 * emu.read(wa * 2 + 1, VRAM) end

local ROOT = "/Users/koneko/Developer/SailorMoonS/"
local STATE = ROOT .. "traces/uranus_vs_jupiter.mss"
local OUT = ROOT .. "traces/probe_p10_vs.txt"

local REP, WARMUP, MAXT = 55, 20, 220
-- optional: poke $008D=2 (1P-vs-COM) during [from,to] to A/B the counter's mode gate
-- (env P10_MODE2_FROM/TO; the real mode byte is restored every endFrame)
local M2F = tonumber(os.getenv("P10_MODE2_FROM") or "0")
local M2T = tonumber(os.getenv("P10_MODE2_TO") or "0")
local savedMode = nil
local SEQ = {   -- rep-local frame -> P1 buttons (demo_infinite.lua timing)
  [0]={down=true,y=true}, [2]={down=true},            -- 2LP
  [17]={down=true,x=true},[20]={down=true},           -- 2HP
  [35]={}, [37]={right=true},[38]={},[39]={right=true},[41]={},  -- 66
}
local OFFS = {}; for k in pairs(SEQ) do OFFS[#OFFS+1]=k end; table.sort(OFFS)
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

local t, playStart = 0, WARMUP + 1
local log = io.open(OUT, "w")
local first = {}   -- first frame each pipeline stage fires

local __loaded = false
emu.addMemoryCallback(function()
  if not __loaded then
    local f = io.open(STATE, "rb"); local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss); __loaded = true
    t = 0; playStart = WARMUP + 1
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local function reposition()
  for _,b in ipairs({0x1000, 0x1080}) do w(b+1,0); w(b+2,0); w(b+6,0); w(b+7,0) end
  w(0x1021, 0xE8); w(0x1022, 0)      -- P1 x (verified point-blank gap)
  w(0x10A1, 0x00); w(0x10A2, 0x01)   -- P2 x = 0x100
end

local function p1Input(lt)
  local last = {}
  for _,off in ipairs(OFFS) do if off <= lt then last = SEQ[off] else break end end
  local b = {}; for k,v in pairs(FALSE) do b[k]=v end
  for k,v in pairs(last) do b[k]=v end
  return b
end

emu.addEventCallback(function()
  if M2F > 0 and t + 1 >= M2F and t + 1 <= M2T then
    savedMode = r(0x8D); w(0x8D, 2)   -- producer (scanline 101) sees mode 2
  end
  if t >= playStart then
    emu.setInput(p1Input((t - playStart) % REP), 0, 0)
    local p2 = {}; for k,v in pairs(FALSE) do p2[k]=v end
    p2.down = true
    emu.setInput(p2, 0, 1)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not __loaded then return end   -- clock starts at savestate load
  if savedMode then w(0x8D, savedMode); savedMode = nil end
  t = t + 1
  if t == 5 then reposition() end
  if t >= playStart or t == 1 then
    local hits, free, ttl, shown, shadow =
      r(0x8B0), r(0x8B1), r(0x8B2), r(0x8B3), r(0x8B4)
    local dirty = r(0x8D0)
    local tt, ot, tb, ob = rw(0x8D1), rw(0x8D3), rw(0x8D5), rw(0x8D7)
    local v1, v2, v3, v4 = vword(0x10C2), vword(0x10C3), vword(0x10E2), vword(0x10E3)
    log:write(string.format(
      "t=%3d mode=%d init=%02X p2hp=%3d p2act=%02X | hits=%d free=%3d ttl=%2d shown=%d shad=%3d"
      .. " | dirty=%d stg=%04X,%04X,%04X,%04X | vram=%04X,%04X,%04X,%04X\n",
      t, r(0x8D), r(0x8C0), r(0x10C9), r(0x1081), hits, free, ttl, shown, shadow,
      dirty, tt, ot, tb, ob, v1, v2, v3, v4))
    if hits >= 2 and not first.hits2 then first.hits2 = t end
    if shown >= 2 and not first.shown then first.shown = t end
    if dirty == 1 and not first.dirty then first.dirty = t end
    if (v3 ~= 0x2000 or v4 ~= 0x2000) and not first.vram then first.vram = t end
  end
  if t >= MAXT then
    log:write(string.format("\nSUMMARY: mode=%d first hits>=2 @%s, shown>=2 @%s, dirty @%s, vram!=blank @%s\n",
      r(0x8D), tostring(first.hits2), tostring(first.shown), tostring(first.dirty), tostring(first.vram)))
    local verdict
    if not first.hits2 then verdict = "STALL: defender logic never reaches 2 hits (chain rule / hit detect)"
    elseif not first.shown then verdict = "STALL: render logic never stages (min-hits / shown compare)"
    elseif not first.vram then verdict = "STALL: staged but never flushed to VRAM (uploader hook)"
    else verdict = "PIPELINE OK: counter reached VRAM" end
    log:write("VERDICT: " .. verdict .. "\n")
    log:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)

print("probe_p10_vs.lua loaded")
