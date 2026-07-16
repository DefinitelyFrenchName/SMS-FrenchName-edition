local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local log = io.open(TRACE .. "probe_upl.txt", "w")
local t, needLoad = -1, true
local callers = {}
local dumpedKeys = false
local function ret()
  local ok, st = pcall(emu.getState); if not ok then return "?" end
  if not dumpedKeys then
    local ks={}; for k in pairs(st) do if tostring(k):find("scan") or tostring(k):find("cycle") or tostring(k):find("ppu") then ks[#ks+1]=tostring(k) end end
    table.sort(ks); log:write("ppu/scan keys: "..table.concat(ks,",").."\n"); dumpedKeys=true
  end
  local sp = st["cpu.sp"] or 0
  local lo = emu.read(sp+1, emu.memType.snesWorkRam)
  local hi = emu.read(sp+2, emu.memType.snesWorkRam)
  local bk = emu.read(sp+3, emu.memType.snesWorkRam)
  local sl = st["ppu.scanline"] or st["ppu.cycle"] or -1
  return string.format("%02X:%04X sl=%s", bk, (hi*256+lo), tostring(sl))
end
emu.addMemoryCallback(function()
  if needLoad then local f=io.open(TRACE.."venus_vs_jupiter_clean.mss","rb"); if not f then return end
    emu.loadSavestate(f:read("*a")); f:close(); needLoad=false; t=0 end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
for _, addr in ipairs({0xC0D56F, 0x80D56F}) do
  emu.addMemoryCallback(function()
    if t>=0 and t<10 then local k=ret(); callers[string.format("UPL@%06X ",addr)..k]=(callers[string.format("UPL@%06X ",addr)..k] or 0)+1 end
  end, emu.callbackType.exec, addr, addr, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if t<0 then return end
  if t==12 then
    local keys={}; for k in pairs(callers) do keys[#keys+1]=k end; table.sort(keys)
    if #keys==0 then log:write("(no uploader execs caught)\n") end
    for _,k in ipairs(keys) do log:write(k.." x"..callers[k].."\n") end
    log:close(); emu.stop(0)
  end
  t=t+1
end, emu.eventType.endFrame)
print("probe_upl loaded")
