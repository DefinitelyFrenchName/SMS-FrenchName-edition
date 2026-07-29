-- probe_p11_7fb.lua (patch 11, P10c): exact bank-$7F in-match footprint.
-- Loads traces/training_p11.mss, watches $7F reads/writes for 300 frames of fighting:
-- logs per-frame hit counts, the distinct address set (min/max + up to 60 samples),
-- and writer/reader PCs (up to 12 distinct). Output: traces/p11_7fb.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p11_7fb.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local t, needLoad = -1, true
local addrs, pcs, hits = {}, {}, 0
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

for _, cb in ipairs({ emu.callbackType.read, emu.callbackType.write }) do
  emu.addMemoryCallback(function(addr, value)
    if t >= 0 then
      hits = hits + 1
      addrs[addr] = true
      local pc = emu.getState()["cpu.pc"]
      pcs[pc] = (pcs[pc] or 0) + 1
    end
  end, cb, 0x7F0000, 0x7FFFFF, emu.cpuType.snes, emu.memType.snesMemory)
end

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local lastHits = 0
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t % 20 < 3 then pulse[0] = { down = true, y = true }
  elseif t % 20 < 6 then pulse[0] = { right = true, x = true }
  else pulse[0] = nil end
  if t % 50 == 0 then
    log(string.format("t=%d hits/50f=%d", t, hits - lastHits)); lastHits = hits
  end
  if t == 300 then
    local l = {}
    for a in pairs(addrs) do l[#l + 1] = a end
    table.sort(l)
    log(string.format("distinct addrs=%d min=%06X max=%06X", #l, l[1] or 0, l[#l] or 0))
    local s = ""
    for i = 1, math.min(#l, 60) do s = s .. string.format(" %06X", l[i]) end
    log("sample:" .. s)
    local pl = {}
    for pc, c in pairs(pcs) do pl[#pl + 1] = string.format("%06X x%d", pc, c) end
    table.sort(pl)
    for i = 1, math.min(#pl, 12) do log("pc " .. pl[i]) end
    log("done"); emu.stop(0)
  end
end, emu.eventType.endFrame)

print("probe_p11_7fb loaded")
