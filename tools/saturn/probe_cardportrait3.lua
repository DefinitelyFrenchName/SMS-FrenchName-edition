
-- probe_cardportrait.lua — VS flow, P1 selects CHAR (poked at select), KO P2
-- twice, dump VRAM + screenshot at the report card. Run with two CHARs and
-- diff to locate the portrait tiles.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local CHAR = tonumber(os.getenv("CHAR") or "6")
local TAG = os.getenv("TAG") or "x"
local LOG = assert(io.open(ENV.TRACE .. "saturn/card_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local function beat(on) return (frames % 10) < 2 and on or {} end
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)
local watching = false
local vaddr = 0
for _, b in ipairs({0x002116, 0x802116}) do
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0xFF00) | (v or 0) end,
    emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0x00FF) | ((v or 0) << 8) end,
    emu.callbackType.write, b + 1, b + 1, emu.cpuType.snes, emu.memType.snesMemory)
end
local REG = emu.memType.snesMemory
local function reg(a) return emu.read(0x800000 + a, REG) end
for _, b in ipairs({0x00420B, 0x80420B}) do
  emu.addMemoryCallback(function(addr, value)
    if not watching or (value or 0) == 0 then return end
    for ch = 0, 7 do
      if ((value >> ch) & 1) == 1 then
        local c = 0x4300 + ch * 0x10
        if reg(c + 1) == 0x18 or reg(c + 1) == 0x19 then
          local ok, st = pcall(emu.getState)
          log(string.format("DMA VRAM %04X <- %02X:%04X len %04X @ %02X:%04X dp30=%02X%02X dp36=%02X",
            vaddr, reg(c+4), reg(c+2) + 256*reg(c+3), reg(c+5) + 256*reg(c+6),
            st and (st["cpu.k"] or st["snes.cpu.k"]) or -1,
            st and (st["cpu.pc"] or st["snes.cpu.pc"]) or -1,
            ram(0x31), ram(0x30), ram(0x36)))
        end
      end
    end
  end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end
local vw = {}
for _, b in ipairs({0x002118, 0x802118, 0x002119, 0x802119}) do
  emu.addMemoryCallback(function(addr, value)
    if not watching then return end
    local ok, st = pcall(emu.getState)
    local pc = (st and (st["cpu.k"] or 0) or 0) * 0x10000 + (st and (st["cpu.pc"] or 0) or 0)
    vw[pc] = (vw[pc] or 0) + 1
  end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end
local portrait_on, romreads, romlog = false, 0, {}
-- arm when VRAM writes land in the portrait window ($0000-$0900)
for _, b in ipairs({0x002118, 0x802118}) do
  emu.addMemoryCallback(function()
    if watching and not portrait_on and vaddr < 0x0480 then
      portrait_on = true
    end
  end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addMemoryCallback(function(addr)
  if portrait_on and romreads < 40 then
    romreads = romreads + 1
    romlog[#romlog+1] = string.format("%06X", addr)
  end
end, emu.callbackType.read, 0x9F0000, 0x9FFFFF, emu.cpuType.snes, emu.memType.snesMemory)
local dseen = 0
emu.addMemoryCallback(function(addr)
  if not watching or dseen > 24 then return end
  dseen = dseen + 1
  local ok, st = pcall(emu.getState)
  local function r(a) return ram(a) end
  -- capture the DP block the routine works from + the return address on stack
  local sp = st and (st["cpu.sp"] or st["snes.cpu.sp"]) or 0
  local ret = emu.read(sp + 1, emu.memType.snesMemory)
        + 256 * emu.read(sp + 2, emu.memType.snesMemory)
        + 65536 * emu.read(sp + 3, emu.memType.snesMemory)
  log(string.format("DEC enter #%d ret=%06X | dp: 00=%02X%02X 02=%02X%02X 04=%02X%02X"
    .. " 06=%02X%02X 30=%02X%02X 32=%02X%02X 34=%02X%02X 36=%02X",
    dseen, ret,
    r(0x01), r(0x00), r(0x03), r(0x02), r(0x05), r(0x04), r(0x07), r(0x06),
    r(0x31), r(0x30), r(0x33), r(0x32), r(0x35), r(0x34), r(0x36)))
end, emu.callbackType.exec, 0x9F84E8, 0x9F84E8, emu.cpuType.snes, emu.memType.snesMemory)
local function dumpvram(tag)
  local V = emu.memType.snesVideoRam
  local f = assert(io.open(ENV.TRACE .. "saturn/vramcard_" .. tag .. ".bin", "wb"))
  local b = {}
  for i = 0, 0xFFFF do b[#b+1] = string.char(emu.read(i, V)) end
  f:write(table.concat(b)); f:close()
  local png = emu.takeScreenshot()
  local g = assert(io.open(ENV.TRACE .. "saturn/card_" .. tag .. ".png", "wb"))
  g:write(png); g:close()
  local rows = {}
  for pc, n in pairs(vw) do rows[#rows+1] = {n, pc} end
  table.sort(rows, function(x, y) return x[1] > y[1] end)
  for i = 1, math.min(#rows, 8) do
    log(string.format("VRAM-write PC %06X: %d writes", rows[i][2], rows[i][1]))
  end
  log("ROM reads (bank $9F) after portrait writes began: " .. table.concat(romlog, " "))
  log("dumped " .. tag)
end
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() return sf>300 end,
  function() wr(0x1B40, CHAR); wr(0x1B80, 4); return sf>20 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>150 end,
  function() pulse[1]=beat({a=true}); return ram(0x1B82)==1 or sf>150 end,
  function()
    pulse[0] = (sf % 20 < 3) and {start=true} or {}
    if ram(0x70)==4 and ram(0x1000)~=0 and ram(0x1080)~=0 then return true end
    if sf > 900 then log("NO-MATCH"); emu.stop(1) end
    return false
  end,
  function() return sf > 150 end,
  -- two quick KOs
  function() wr(0x1021, 0x90); wr(0x1022, 0); wr(0x10A1, 0xA6); wr(0x10A2, 0)
             wr(0x10C9, 1); pulse[0] = (sf % 12 < 3) and {y=true} or {}
             return ram(0x10C9) == 0 or sf > 300 end,
  function() pulse[0]={}; return sf > 420 end,
  function() wr(0x1021, 0x90); wr(0x1022, 0); wr(0x10A1, 0xA6); wr(0x10A2, 0)
             wr(0x10C9, 1); pulse[0] = (sf % 12 < 3) and {y=true} or {}
             return ram(0x10C9) == 0 or sf > 400 end,
  function()   -- advance to the REPORT CARD, detected by state, then settle
    watching = true
    pulse[0] = (sf % 40 < 3) and {start=true} or {}
    if sf % 60 == 0 then log(string.format("sf=%d 70=%02X 8D=%02X 1E05=%02X", sf, ram(0x70), ram(0x8D), ram(0x1E05))) end
    if ram(0x1E05) == 0xFF and ram(0x70) == 0 then return true end
    if sf > 1200 then log("card not detected"); return true end
    return false
  end,
  function() pulse[0] = {}; return sf > 90 end,
  function() dumpvram(TAG); return true end,
  function() return sf > 30 end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 9000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("cardportrait loaded char=" .. CHAR)
