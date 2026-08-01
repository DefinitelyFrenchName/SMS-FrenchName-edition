
-- probe_vramwatch.lua — corruption hunt: mirror match, repeated hits, and a
-- watchdog on EVERY VRAM DMA. Flags transfers whose source bank or length is
-- outside the set observed in a clean vanilla match (the corrupting transfer
-- should stand out immediately).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = os.getenv("MODE") or "sat"
local LOG = assert(io.open(ENV.TRACE .. "saturn/vramwatch_" .. MODE .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local b1, b2 = {}, {}
local watching = false
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  emu.setInput(PL.pad(b1), 0, 0); emu.setInput(PL.pad(b2), 0, 1)
end, emu.eventType.inputPolled)
local vaddr = 0
for _, b in ipairs({0x002116, 0x802116}) do
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0xFF00) | (v or 0) end,
    emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0x00FF) | ((v or 0) << 8) end,
    emu.callbackType.write, b + 1, b + 1, emu.cpuType.snes, emu.memType.snesMemory)
end
local REG = emu.memType.snesMemory
local function reg(a) return emu.read(0x800000 + a, REG) end
local census, flagged = {}, 0
for _, b in ipairs({0x00420B, 0x80420B}) do
  emu.addMemoryCallback(function(addr, value)
    if not watching or (value or 0) == 0 then return end
    for ch = 0, 7 do
      if ((value >> ch) & 1) == 1 then
        local c = 0x4300 + ch * 0x10
        if reg(c + 1) == 0x18 or reg(c + 1) == 0x19 then
          local bank = reg(c + 4)
          local src = reg(c+2) + 256*reg(c+3)
          local len = reg(c+5) + 256*reg(c+6)
          local key = string.format("dst%04X", vaddr - (vaddr % 0x400))
          census[key] = (census[key] or 0) + 1
          -- expected: her cel banks $EB-$ED, SMS char/asset banks $C0-$DF, staging $7F/$7E
          -- vanilla destinations (measured): $6000-$65FF cels, $11xx name
          -- plates, plus the load-time windows. Flag anything else.
          local ok = (vaddr >= 0x6000 and vaddr < 0x6A00) or (vaddr >= 0x1100 and vaddr < 0x1200)
            or (vaddr >= 0x6A00 and vaddr < 0x7400) or vaddr == 0
          if (not ok) or len > 0x4000 then
            flagged = flagged + 1
            if flagged <= 12 then
              log(string.format("t=%03d SUSPECT DMA VRAM %04X <- %02X:%04X len %04X (p1act=%02X p2act=%02X)",
                t, vaddr, bank, src, len, ram(0x1001), ram(0x1081)))
            end
          end
        end
      end
    end
  end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    if MODE == "sat" then
      for _, base in ipairs({0x1000, 0x1080}) do
        wr(base, 0x1C)
        for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(base + o, 0) end
      end
    end
    watching = true
  end
  -- repeated close-range trades, both players attacking
  if t > 90 then
    if t % 40 == 0 then
      wr(0x1021, 0x90); wr(0x1022, 0x00); wr(0x10A1, 0xA6); wr(0x10A2, 0x00)
      wr(0x1049, 0x60); wr(0x10C9, 0x60)
    end
    local ph = t % 40
    b1 = (ph < 3) and {y=true} or (ph == 10 and {b=true} or (ph == 20 and {x=true} or (ph == 30 and {a=true} or {})))
    b2 = (ph == 5) and {y=true} or (ph == 15 and {b=true} or {})
  end
  if t > 2400 then
    local parts = {}
    for k, v in pairs(census) do parts[#parts+1] = k .. "=" .. v end
    table.sort(parts)
    log("DMA source-bank census: " .. table.concat(parts, " "))
    log("flagged: " .. flagged)
    emu.stop(flagged > 0 and 1 or 0)
  end
end, emu.eventType.endFrame)
print("vramwatch loaded " .. MODE)
