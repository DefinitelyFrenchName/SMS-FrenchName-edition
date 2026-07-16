-- probe_p11_dbg.lua (patch 11): two debug scenarios on the patched ROM.
-- A) refill-KO: lethal hit with refill on; log hp, $0800/$0801, act, and any write
--    to $0800-$0805 with writer PC around the death.
-- B) menu-uneat: open menu, close it, press Y later; log $5C/$5D, p1 act, EATLINGER
--    per frame to see who eats the press.
-- Output: traces/p11_dbg.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local LOG = assert(io.open(TRACE .. "p11_dbg.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end
local function st(off) return ram(0x1F000 + off) end
local function stw(off, v) wr(0x1F000 + off, v) end

local phase, pt, needLoad = 1, nil, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; pt = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr, value)
  if pt and phase == 1 and pt > 20 and pt < 120 then
    log(string.format("  wr08xx t=%d addr=%04X val=%02X pc=%06X", pt, addr, value, emu.getState()["cpu.pc"]))
  end
end, emu.callbackType.write, 0x0800, 0x0805, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not pt then return end
  pt = pt + 1
  if phase == 1 then
    if pt == 5 then stw(0x26, 1); wr(0x8D, 5); stw(0x04, 0xA5) end
    if pt == 10 then
      local p1x = ram(0x1021) + 256 * ram(0x1022)
      wr(0x10A1, (p1x + 16) % 256); wr(0x10A2, math.floor((p1x + 16) / 256))
      wr(0x10C9, 0x01)
    end
    if pt >= 24 and pt <= 25 then pulse[0] = { down = true, y = true } elseif pt == 26 then pulse[0] = nil end
    if pt >= 26 and pt <= 120 and pt % 4 == 0 then
      log(string.format("A t=%d p2act=%02X p2hp=%02X bar0=%02X bar1=%02X", pt, ram(0x1081), ram(0x10C9), ram(0x800), ram(0x801)))
    end
    if pt == 120 then
      phase = 2; pt = nil; needLoad = true; pulse = {}
      log("--- phase B")
    end
  else
    if pt >= 10 and pt <= 12 then pulse[0] = { l = true, r = true } elseif pt == 13 then pulse[0] = nil end
    if pt >= 40 and pt <= 42 then pulse[0] = { l = true, r = true } elseif pt == 43 then pulse[0] = nil end
    if pt >= 60 and pt <= 63 then pulse[0] = { y = true } elseif pt == 64 then pulse[0] = nil end
    if pt >= 14 and pt <= 90 then
      log(string.format("B t=%d 5C=%02X 5D=%02X p1act=%02X mo=%02X eat=%02X ui=%02X clr=%02X vis=%02X f1FA=%02X m=%02X f70=%02X",
        pt, ram(0x5C), ram(0x5D), ram(0x1001), st(0x05), st(0x07), st(0x0D), st(0x0F), st(0x02), ram(0x1FA), ram(0x8D), ram(0x70)))
    end
    if pt == 95 then log("done"); emu.stop(0) end
  end
end, emu.eventType.endFrame)

print("probe_p11_dbg loaded")
