-- probe_supers_dmacensus.lua — in-match DMA traffic census on the Saturn fixture:
-- for ~120 frames, log every $420B trigger's enabled channels (B-bus target, A-bus
-- source, size). Answers where sprite/anim data streams from at runtime.
-- ROM=<Super S> tools/run.sh tools/probe_supers_dmacensus.lua 60
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "supers_dmacensus.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local BUS = emu.memType.snesMemory
local t, needLoad = -1, true
local tally = {}   -- key "bbus|srcbank" -> {count, bytes, minsrc, maxsrc}

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "saturn_vs_uranus_supers.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808347, 0x808347, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local b = PL.pad()
  if (t >= 240 and t <= 241) or (t >= 300 and t <= 301) then b = PL.pad({ x = true }) end
  emu.setInput(b, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

_G.__dmacb = function(addr, value)
  if t < 0 or t > 360 then return end
  for ch = 0, 7 do
    if value & (1 << ch) ~= 0 then
      local base = 0x4300 + ch * 0x10
      local bbus = emu.read(base + 1, BUS)
      local alo = emu.read(base + 2, BUS) | (emu.read(base + 3, BUS) << 8)
      local abk = emu.read(base + 4, BUS)
      local sz = emu.read(base + 5, BUS) | (emu.read(base + 6, BUS) << 8)
      if sz == 0 then sz = 0x10000 end
      local key = string.format("2%02X|%02X|%s", bbus, abk, (t >= 238 and t <= 340) and "ATK" or ((t >= 190 and t <= 237) and "idle" or "pre"))
      local e = tally[key] or { n = 0, bytes = 0, lo = 0xFFFF, hi = 0 }
      e.n = e.n + 1; e.bytes = e.bytes + sz
      if alo < e.lo then e.lo = alo end
      if alo > e.hi then e.hi = alo end
      tally[key] = e
    end
  end
end
-- register on BOTH bus mirrors: bank $00 and the FastROM bank $80 view
emu.addMemoryCallback(_G.__dmacb, emu.callbackType.write, 0x00420B, 0x00420B, emu.cpuType.snes, BUS)
emu.addMemoryCallback(_G.__dmacb, emu.callbackType.write, 0x80420B, 0x80420B, emu.cpuType.snes, BUS)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 361 then
    log("DMA census (pre=intro, idle=190-237, ATK=238-340 with 5HP presses (Bbus|srcbank: count bytes src-range):")
    local keys = {}
    for k in pairs(tally) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local e = tally[k]
      log(string.format("  %s : n=%4d bytes=%7d src %04X..%04X", k, e.n, e.bytes, e.lo, e.hi))
    end
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("probe_supers_dmacensus loaded")
