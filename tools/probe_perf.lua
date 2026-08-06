-- measure compute-stub + flush-stub cycle cost via masterClock deltas; also full-frame cycles.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
pcall(dofile,ENV.TOOLS .. "probe_perf_cfg.lua")
local TRACE=ENV.TRACE
local WRAM=emu.memType.snesWorkRam
local t, needLoad = -1, true
local function mclk() local ok,st=pcall(emu.getState); return ok and (st["cpu.cycleCount"] or st["masterClock"] or 0) or 0 end
local cStart, fStart = nil, nil
local computeCyc, flushCyc = {}, {}
local frameClk, lastFrame = {}, nil
emu.addMemoryCallback(function()
  if needLoad then local f = io.open(TRACE.."uranus_vs_jupiter_v07.mss","rb") if not f then print("probe_perf.lua: cannot open " .. (TRACE.."uranus_vs_jupiter_v07.mss")) emu.stop(1) return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec,0x808353,0x808353,emu.cpuType.snes,emu.memType.snesMemory)
-- compute stub entry ($EA:0000 for v07 build) and exit (PROD_CONT $80D5EC)
emu.addMemoryCallback(function() if t>=0 then cStart=mclk() end end,
  emu.callbackType.exec, STUB_C, STUB_C, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function() if t>=0 and cStart then computeCyc[#computeCyc+1]=mclk()-cStart; cStart=nil end end,
  emu.callbackType.exec, 0x80D5EC, 0x80D5EC, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function() if t>=0 then fStart=mclk() end end,
  emu.callbackType.exec, STUB_F, STUB_F, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function() if t>=0 and fStart then flushCyc[#flushCyc+1]=mclk()-fStart; fStart=nil end end,
  emu.callbackType.exec, 0x80D574, 0x80D574, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if t<0 then return end
  local c=mclk(); if lastFrame then frameClk[#frameClk+1]=c-lastFrame end; lastFrame=c
  if t==300 then
    local function stats(a) if #a==0 then return "n=0" end
      local s,mx=0,0; for _,v in ipairs(a) do s=s+v; if v>mx then mx=v end end
      return string.format("n=%d mean=%.0f max=%d", #a, s/#a, mx) end
    local log = io.open(TRACE.."probe_perf.txt","w")
    if not log then print("probe_perf.lua: cannot open " .. (TRACE.."probe_perf.txt")) emu.stop(1) return end
    log:write("compute stub cycles: "..stats(computeCyc).."\n")
    log:write("flush stub cycles:   "..stats(flushCyc).."\n")
    log:write("full frame cycles:   "..stats(frameClk).."\n")
    log:close(); emu.stop(0)
  end
  t=t+1
end, emu.eventType.endFrame)
print("perf loaded")
