-- probe_fontdma.lua — find the code that uploads the menu FONT to VRAM.
--
-- Patch 16 extends the kanji font block from 182 to 256 tiles, but the extra
-- tiles never arrive: VRAM still ends at tile $5B5. The asset record's length
-- field is not the cause (changing it does nothing, and neither value matches
-- the 182 tiles that do arrive), and probe_menu_survey's DMA hook does not see
-- the transfer at all — it logs 54 tilemap-sized moves and nothing else.
--
-- So stop looking at the table and watch the hardware. Everything that reaches
-- VRAM passes through the PPU's address port ($2116/$2117) whatever route it
-- took, so setting that port to the font's window is the one event that cannot
-- be missed. Log the PC that does it, and the DMA parameters live at that moment.
--
-- The font lands at VRAM tile $500 = word address $5000, so a write of $50xx to
-- $2117 (the high byte) is the signature.
--
-- STATUS: the font upload is STILL NOT FOUND. What this probe has established:
--   * the hook works — 42 writes to $2117 are captured on a clean run;
--   * ALL of them target VRAM $0000-$1FFF, i.e. tilemaps. None touches $5000,
--     where the font demonstrably sits in a VRAM capture of the same screen;
--   * so the upload sets VMADD through a register mirror in some bank other than
--     $00/$80, or does not go through $2116/$2117 in this flow at all.
--
-- NEXT: registers are mirrored in banks $00-$3F and $80-$BF, so widen the hook
-- across those mirrors rather than guessing one bank at a time. Failing that,
-- work forward from the decompressor at $80:916B (probe_menu_survey already
-- exec-hooks it) — the font is expanded to a staging buffer first, and whatever
-- moves it onward is reachable from there.
--
-- The diagnostic counter is deliberately unconditional: the first two runs of
-- this probe reported a confident zero while the hook was simply not firing on
-- the right bank, which is indistinguishable from "the game does not do this"
-- unless the total is printed too.
--
--   ROM=<rom> tools/run.sh tools/probe_fontdma.lua 400
-- envs: WLO/WHI (VRAM word window, default 0x4F00/0x6000), TAG
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram = PL.ram

local function num(n, d) return tonumber(os.getenv(n) or "") or d end
local WLO, WHI = num("WLO", 0x4F00), num("WHI", 0x6000)
local TAG = os.getenv("TAG") or "fontdma"
local LOG = assert(io.open(ENV.TRACE .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local MEM = emu.memType.snesMemory
local frames, step, sf = 0, 1, 0
local pulse = {}
local vlo, vhi = 0, 0
local seen, hits = {}, 0
local allwrites, addrhist = 0, {}   -- unconditional: does the hook fire AT ALL?

local function pc()
  local ok, st = pcall(emu.getState)
  if not (ok and st) then return -1 end
  return ((st["cpu.k"] or 0) << 16) | (st["cpu.pc"] or 0)
end

-- $2116 = VMADDL, $2117 = VMADDH. The address is only meaningful once the high
-- byte lands, so report on the $2117 write.
-- Mesen's snesMemory is the full 24-bit CPU bus, so a register hook must name
-- the BANK the game actually writes through. Registering $2116/$2117 (bank 0)
-- catches nothing; the game writes $80:2116. probe_menu_survey does it right and
-- this probe copied the address wrong on the first attempt, reporting a clean
-- zero — the classic broken-probe-looks-like-a-finding failure.
for _, a in ipairs({ 0x002116, 0x802116 }) do
  emu.addMemoryCallback(function(_, v) vlo = v or 0 end,
    emu.callbackType.write, a, a, emu.cpuType.snes, MEM)
end
for _, a in ipairs({ 0x002117, 0x802117 }) do
emu.addMemoryCallback(function(_, v)
  vhi = v or 0
  local addr = vlo | (vhi << 8)
  allwrites = allwrites + 1
  local bucket = (addr >> 12)
  addrhist[bucket] = (addrhist[bucket] or 0) + 1
  if addr < WLO or addr >= WHI then return end
  local p = pc()
  local key = string.format("%06X/%04X", p, addr)
  if seen[key] then return end
  seen[key] = true; hits = hits + 1
  if hits <= 40 then
    log(string.format("f=%-5d VRAM addr <= $%04X (tile $%03X) by PC $%06X",
      frames, addr, addr // 32 * 2, p))
  end
end, emu.callbackType.write, a, a, emu.cpuType.snes, MEM)
end

-- and the DMA trigger, so a transfer can be attributed to a channel + params
emu.addMemoryCallback(function(_, v)
  local mask = v or 0
  if mask == 0 then return end
  for ch = 0, 7 do
    if (mask >> ch) & 1 == 1 then
      local b = 0x4300 + ch * 0x10
      local dst = emu.read(b + 1, MEM) or 0
      if dst == 0x18 or dst == 0x19 then          -- $2118/$2119 = VRAM data
        local src = (emu.read(b + 2, MEM) or 0) | ((emu.read(b + 3, MEM) or 0) << 8)
        local bank = emu.read(b + 4, MEM) or 0
        local len = (emu.read(b + 5, MEM) or 0) | ((emu.read(b + 6, MEM) or 0) << 8)
        local addr = vlo | (vhi << 8)
        if addr >= WLO and addr < WHI then
          log(string.format("f=%-5d DMA ch%d src=$%02X:%04X len=$%04X -> VRAM $%04X"
            .. " (tile $%03X) by PC $%06X", frames, ch, bank, src, len, addr,
            addr // 32 * 2, pc()))
        end
      end
    end
  end
end, emu.callbackType.write, 0x80420B, 0x80420B, emu.cpuType.snes, MEM)

local function beat(on) return (frames % 7) < 3 and on or {} end

emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ right = true }); return ram(0x1B10) == 4 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 400 end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log("")
    log(string.format("TOTAL $2117 writes seen: %d", allwrites))
    local ks = {}
    for k in pairs(addrhist) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do
      log(string.format("   VRAM $%X000-$%XFFF : %d writes", k, k, addrhist[k]))
    end
    log(string.format("distinct (PC, address) pairs touching VRAM $%04X-$%04X: %d",
      WLO, WHI, hits))
    if hits == 0 then
      log("NONE — either the window is wrong or the font is uploaded before this")
      log("flow reaches it. Widen WLO/WHI, or start logging from frame 0.")
    end
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_fontdma loaded: watching VRAM window $" ..
  string.format("%04X-%04X", WLO, WHI))
