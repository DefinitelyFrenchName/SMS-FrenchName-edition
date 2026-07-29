-- probe_p13_round.lua (patch 13, R1): VS round-transition signal hunt. Loads a VS state,
-- kills P2 (hp poke + hit), logs every change of p1/p2 act, hp, $0070, $01FA, $008D from
-- the KO through the next round's fight-ready state; snapshots $0000-$00FF + $0800-$08FF
-- at round-1 fight and round-2 fight for a diff (round-counter hunt).
-- Output: traces/p13_round.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p13_round.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
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

local prev = {}
local function trackByte(name, addr)
  local v = ram(addr)
  if prev[name] ~= v then
    log(string.format("chg t=%d %s %s->%02X", t, name, prev[name] and string.format("%02X", prev[name]) or "--", v))
    prev[name] = v
  end
end
local snap1, snap2 = nil, nil
local function snap()
  local s = {}
  for a = 0x0000, 0x00FF do s[#s + 1] = ram(a) end
  for a = 0x0800, 0x08FF do s[#s + 1] = ram(a) end
  return s
end

emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  trackByte("p1act", 0x1001); trackByte("p2act", 0x1081)
  trackByte("p1hp", 0x1049); trackByte("p2hp", 0x10C9)
  trackByte("f0070", 0x70); trackByte("f01FA", 0x1FA); trackByte("mode", 0x8D)
  if t == 5 then snap1 = snap() end
  if t == 10 then
    wr(0x10C9, 0x01)
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    wr(0x10A1, (p1x + 16) % 256); wr(0x10A2, math.floor((p1x + 16) / 256))
  end
  if t >= 14 and t <= 15 then pulse[0] = { down = true, y = true } elseif t == 16 then pulse[0] = nil end
  -- wait through KO + round transition; when both back at full HP and neutral, snapshot 2
  if t > 120 and not snap2 and ram(0x1049) == 0x60 and ram(0x10C9) == 0x60
     and ram(0x1001) == 0 and ram(0x1081) == 0 then
    snap2 = snap()
    local diffs = 0
    for i = 1, #snap1 do
      if snap1[i] ~= snap2[i] then
        local a = (i <= 256) and (i - 1) or (0x0800 + i - 257)
        log(string.format("rounddiff $%04X: %02X -> %02X", a, snap1[i], snap2[i]))
        diffs = diffs + 1
        if diffs > 40 then log("  ...") break end
      end
    end
    log(string.format("round2 ready at t=%d, diffs=%d", t, diffs))
  end
  if t == 1500 or (snap2 and t > 1200) then log("done snap2=" .. tostring(snap2 ~= nil)); emu.stop(0) end
end, emu.eventType.endFrame)
print("probe_p13_round loaded")
