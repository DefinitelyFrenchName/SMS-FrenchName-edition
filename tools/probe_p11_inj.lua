-- probe_p11_inj.lua (patch 11, P3): input injection fidelity at the ROM hook point.
-- Emulates the future INPUT stub: exec callback at $80:8373 (after $5C-$5F held words are
-- stored, before press-edge calc) overwrites P2's held word $5E/$5F. Tests, in mode 4:
--   A) hold down-back  -> P2 crouches (act 3); P1 2LP -> P2 crouch-BLOCKS (act 0x0F)
--   B) alternating HK every other frame -> +0x50 press latch shows fresh HK bits
--   C) scanline positions of joy_read ($8353) and uploader ($D56F) within the frame/NMI
-- Output: traces/p11_inj.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p11_inj.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end
local function wr(a, v) emu.write(a, v, emu.memType.snesWorkRam) end

local t, needLoad = -1, true
local inj = nil          -- {lo, hi} to write into $5E/$5F at the hook point
local slLog = {}

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
  if #slLog < 8 then slLog[#slLog+1] = "joy@" .. emu.getState()["ppu.scanline"] end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function()
  if inj then wr(0x5E, inj[1]); wr(0x5F, inj[2]) end
end, emu.callbackType.exec, 0x808373, 0x808373, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function()
  if #slLog < 16 and #slLog >= 8 then slLog[#slLog+1] = "upl@" .. emu.getState()["ppu.scanline"] end
end, emu.callbackType.exec, 0x80D56F, 0x80D56F, emu.cpuType.snes, emu.memType.snesMemory)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k,v in pairs(b) do base[k]=v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

-- $5F bit layout: B=80 Y=40 Sel=20 St=10 Up=08 Dn=04 Lt=02 Rt=01 ; $5E: A=80 X=40 L=20 R=10
-- P2 is on the right, faces left -> back = Right (bit 01). down-back = $5F = 0x05.
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 20 then log("scanlines: " .. table.concat(slLog, " ")) end
  if t == 30 then inj = { 0x00, 0x05 }; log("inject down-back on") end
  if t >= 33 and t <= 36 then
    log(string.format("t=%d p2act=%02X p2held50=%02X", t, ram(0x1081), ram(0x10D0)))
  end
  if t == 50 then
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    local x = p1x + 16
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
    log(string.format("p2x->%04X (still down-back)", x))
  end
  if t >= 54 and t <= 55 then pulse[0] = { y = true, down = true } end
  if t == 56 then pulse[0] = nil end
  if t >= 58 and t <= 75 then
    log(string.format("t=%d p1act=%02X p2act=%02X p2hp=%02X", t, ram(0x1001), ram(0x1081), ram(0x10C9)))
  end
  if t == 90 then inj = nil; log("inject off") end
  -- B: HK mash latch test
  if t >= 100 and t <= 140 then
    if t % 2 == 0 then inj = { 0x80, 0x00 } else inj = { 0x00, 0x00 } end
    if t >= 100 and t <= 112 then
      log(string.format("t=%d p2held50=%02X p2_52=%02X p2_54=%02X", t, ram(0x10D0), ram(0x10D2), ram(0x10D4)))
    end
  end
  if t == 141 then inj = nil end
  if t == 150 then
    log(string.format("FINAL p2act=%02X p2hp=%02X", ram(0x1081), ram(0x10C9)))
    log("done"); emu.stop(0)
  end
end, emu.eventType.endFrame)

print("probe_p11_inj loaded")
