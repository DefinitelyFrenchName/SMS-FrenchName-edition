-- probe_sms_stageload.lua — census of the MATCH-LOAD transfers in SMS, to find
-- the per-stage asset table (task #36, stage PoC).
--   STAGE=<n>  poke the stage id (once found) before the match loads
--   TAG=<name> trace/screenshot suffix
-- Logs every DMA whose B-bus is a VRAM/CGRAM port from char-select confirm
-- until the match has been running a moment, with source bank:addr, length,
-- destination and the PC that kicked it. Also dumps VRAM + a screenshot so the
-- stage art can be identified by eye.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local TAG = os.getenv("TAG") or "x"
local CHAR = tonumber(os.getenv("CHAR") or "6")
local CHAR2 = tonumber(os.getenv("CHAR2") or "8")
local LOG = assert(io.open(ENV.TRACE .. "saturn/stageload_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local function beat(on) return (frames % 10) < 2 and on or {} end
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)

local watching = false
local STAGE = os.getenv("STAGE") and tonumber(os.getenv("STAGE")) or nil
local vaddr, cgadd = 0, 0
for _, b in ipairs({0x002116, 0x802116}) do
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0xFF00) | (v or 0) end,
    emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0x00FF) | ((v or 0) << 8) end,
    emu.callbackType.write, b + 1, b + 1, emu.cpuType.snes, emu.memType.snesMemory)
end
for _, b in ipairs({0x002121, 0x802121}) do
  emu.addMemoryCallback(function(a, v) cgadd = v or 0 end,
    emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end
local REG = emu.memType.snesMemory
local function reg(a) return emu.read(0x800000 + a, REG) end
local n = 0
for _, b in ipairs({0x00420B, 0x80420B}) do
  emu.addMemoryCallback(function(addr, value)
    if not watching or (value or 0) == 0 or n > 900 then return end
    for ch = 0, 7 do
      if ((value >> ch) & 1) == 1 then
        local c = 0x4300 + ch * 0x10
        local bbus = reg(c + 1)
        local src = reg(c + 2) + 256 * reg(c + 3) + 65536 * reg(c + 4)
        local skip = (bbus == 0x22 and (src & 0xFFFF) == 0x0500)  -- per-frame CGRAM shadow
        if (bbus == 0x18 or bbus == 0x19 or bbus == 0x22) and not skip then
          n = n + 1
          local ok, st = pcall(emu.getState)
          local len = reg(c + 5) + 256 * reg(c + 6)
          log(string.format("f=%d %s %04X <- %02X:%02X%02X len %04X @%02X:%04X",
            frames, bbus == 0x22 and "CG" or "VRAM",
            bbus == 0x22 and cgadd or vaddr,
            reg(c + 4), reg(c + 3), reg(c + 2), len == 0 and 0x10000 or len,
            st and (st["cpu.k"] or 0) or 0, st and (st["cpu.pc"] or 0) or 0))
        end
      end
    end
  end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end

-- who sets the asset-group index $7E:1C18
local ix, ixlog = 0, {}
local ixaddrs = {0x7E1C18, 0x001C18}
for bk = 0x80, 0x8F do ixaddrs[#ixaddrs + 1] = bk * 0x10000 + 0x1C18 end
for bk = 0x00, 0x0F do ixaddrs[#ixaddrs + 1] = bk * 0x10000 + 0x1C18 end
for _, a in ipairs(ixaddrs) do
  emu.addMemoryCallback(function(addr, value)
    if not watching or ix > 40 then return end
    ix = ix + 1
    local ok, st = pcall(emu.getState)
    ixlog[#ixlog + 1] = string.format("f=%d %06X<=%02X @%02X:%04X", frames, addr, value or 0,
      st and (st["cpu.k"] or 0) or 0, st and (st["cpu.pc"] or 0) or 0)
  end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
end

-- reads of the asset-manifest table ($C3:BE00-$C3:C060): who consumes it
local tr, trlog, tseen = 0, {}, {}
for _, b in ipairs({{0xE002D0, 0xE00390}, {0xA002D0, 0xA00390}}) do
  emu.addMemoryCallback(function(addr, value)
    if not watching or tr > 60 then return end
    local ok, st = pcall(emu.getState)
    local pc = string.format("%02X:%04X", st and (st["cpu.k"] or 0) or 0,
                             st and (st["cpu.pc"] or 0) or 0)
    local key = string.format("%06X", addr)
    if tseen[key] then return end
    tseen[key] = true
    tr = tr + 1
    trlog[#trlog + 1] = string.format("%06X @%s X=%04X", addr, pc,
      st and (st["cpu.x"] or 0) or 0)
  end, emu.callbackType.read, b[1], b[2], emu.cpuType.snes, emu.memType.snesMemory)
end

-- every decompressor call: DP $00 = source long, DP $03 = destination
local dc, dclog = 0, {}
emu.addMemoryCallback(function()
  if not watching or dc > 30 then return end
  dc = dc + 1
  dclog[#dclog + 1] = string.format("f=%d src=%02X:%02X%02X dst=%02X%02X",
    frames, ram(0x02), ram(0x01), ram(0x00), ram(0x04), ram(0x03))
end, emu.callbackType.exec, 0x80927D, 0x80927D, emu.cpuType.snes, emu.memType.snesMemory)

-- the decompressor CORE: catches every entry point, with its caller
emu.addMemoryCallback(function()
  if not watching or dc > 30 then return end
  dc = dc + 1
  local ok, st = pcall(emu.getState)
  local sp = st and (st["cpu.sp"] or 0) or 0
  local ret = {}
  for i = 1, 6 do ret[i] = string.format("%02X", emu.read(sp + i, emu.memType.snesMemory)) end
  dclog[#dclog + 1] = string.format("f=%d CORE src=%02X:%02X%02X dst=%02X:%02X%02X stack=%s",
    frames, ram(0x02), ram(0x01), ram(0x00), ram(0x05), ram(0x04), ram(0x03),
    table.concat(ret, " "))
end, emu.callbackType.exec, 0x80919F, 0x80919F, emu.cpuType.snes, emu.memType.snesMemory)

-- who FILLS the $7F staging buffer (the decompressor) and from where
local fw, fwlog = 0, {}
for _, r in ipairs({{0x7F0000, 0x7F0007}}) do
  emu.addMemoryCallback(function(addr, value)
    if not watching or fw > 40 then return end
    fw = fw + 1
    local ok, st = pcall(emu.getState)
    fwlog[#fwlog + 1] = string.format("f=%d %06X<=%02X @%02X:%04X A=%04X X=%04X Y=%04X",
      frames, addr, value or 0,
      st and (st["cpu.k"] or 0) or 0, st and (st["cpu.pc"] or 0) or 0,
      st and (st["cpu.a"] or 0) or 0, st and (st["cpu.x"] or 0) or 0,
      st and (st["cpu.y"] or 0) or 0)
  end, emu.callbackType.write, r[1], r[2], emu.cpuType.snes, emu.memType.snesMemory)
end

-- force the scene id at $7E:008E just before the loader reads it ($C0:858C),
-- so any stage can be summoned for identification. Gated to the match load.
local forced = false
if STAGE then
  emu.addMemoryCallback(function()
    if not watching or frames < 1700 or forced then return end
    forced = true
    wr(0x8E, STAGE * 2)
    log(string.format("f=%d forced scene $8E = %02X (stage %d)", frames, STAGE * 2, STAGE))
  end, emu.callbackType.exec, 0x808586, 0x808586, emu.cpuType.snes, emu.memType.snesMemory)
end

local function dump()
  for _, l in ipairs(dclog) do log("DECOMP " .. l) end
  for _, l in ipairs(ixlog) do log("IDX " .. l) end
  for _, l in ipairs(trlog) do log("TBLREAD " .. l) end
  if os.getenv("DUMP") == "1" then
    local V = emu.memType.snesVideoRam
    local f = assert(io.open(ENV.TRACE .. "saturn/vram_stage_" .. TAG .. ".bin", "wb"))
    local b = {}
    for i = 0, 0xFFFF do b[#b + 1] = string.char(emu.read(i, V)) end
    f:write(table.concat(b)); f:close()
  end
  local png = emu.takeScreenshot()
  local g = assert(io.open(ENV.TRACE .. "saturn/stage_" .. TAG .. ".png", "wb"))
  g:write(png); g:close()

  log(string.format("dumped %s (transfers logged: %d)", TAG, n))
end



local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({down = true}); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({start = true}); return sf > 40 end,
  function() return sf > 300 end,
  function() wr(0x1B40, CHAR); wr(0x1B80, CHAR2); return sf > 20 end,
  function() pulse[0] = beat({a = true}); return ram(0x1B42) == 1 or sf > 150 end,
  function() pulse[1] = beat({a = true}); return ram(0x1B82) == 1 or sf > 150 end,
  function()   -- watch the post-confirm flow: shots every 40f, no input
    if sf % 40 == 0 and sf <= 320 then
      local png = emu.takeScreenshot()
      local g = assert(io.open(ENV.TRACE .. "saturn/flow_" .. TAG .. "_" .. sf .. ".png", "wb"))
      g:write(png); g:close()
    end
    if sf > 330 then
      local png = emu.takeScreenshot()
      local g = assert(io.open(ENV.TRACE .. "saturn/cfg_" .. TAG .. ".png", "wb"))
      g:write(png); g:close()
      return true
    end
    return false
  end,
  function()   -- config screen: Start into the match; watch from here
    watching = true
    pulse[0] = (sf % 20 < 3) and {start = true} or {}
    if ram(0x70) == 4 and ram(0x1000) ~= 0 and ram(0x1080) ~= 0 then return true end
    if sf > 900 then log("NO-MATCH"); dump(); emu.stop(1) end
    return false
  end,
  function() return sf > 120 end,
  function() dump(); return true end,
  function() return sf > 20 end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 6000 then log("TIMEOUT"); dump(); emu.stop(1) end
end, emu.eventType.endFrame)
print("stageload loaded")
