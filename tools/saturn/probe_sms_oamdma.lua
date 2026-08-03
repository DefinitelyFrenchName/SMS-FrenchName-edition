-- probe_sms_oamdma.lua — where does the OAM shadow reach OAM, and what sprite
-- PRIORITY do the fighters use?
--
-- Why: the ported stage needs THREE depths (sky < palace < ground) and SNES
-- mode 1 gives two per-plane priority levels — but a priority-1 BG tile draws in
-- front of OBJ priority 2, which is what SMS's fighters use, so Super S's own
-- layering (sky BG1.0 / palace BG2.1 / ground BG1.1) would bury them. Super S
-- must draw its fighters at OBJ3. If we can raise SMS's sprites to 3 while this
-- stage is loaded, the port can keep Super S's priority bits verbatim.
--
-- Logs: every DMA whose B-bus target is $2104 (OAM), with source and the PC that
-- kicked it, plus the OAM priority histogram in-match.
-- usage: ROM=<rom> tools/run.sh tools/saturn/probe_sms_oamdma.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/oamdma.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram = PL.ram
local MEM = emu.memType.snesMemory
local frames, seen = 0, {}

emu.addMemoryCallback(function(_addr, value)
  if frames < 60 or frames > 900 then return end
  for ch = 0, 7 do
    if ((value or 0) >> ch) & 1 == 1 then
      local b = emu.read(0x804301 + ch * 16, MEM) or 0
      if b == 0x04 then                                   -- $2104 = OAM
        local ok, st = pcall(emu.getState)
        local key = string.format("ch%d", ch)
        if not seen[key] then
          seen[key] = true
          log(string.format("f=%d OAM DMA ch%d src=%02X:%02X%02X len=%02X%02X kicked @%02X:%04X",
            frames, ch,
            emu.read(0x804304 + ch * 16, MEM) or 0,
            emu.read(0x804303 + ch * 16, MEM) or 0,
            emu.read(0x804302 + ch * 16, MEM) or 0,
            emu.read(0x804306 + ch * 16, MEM) or 0,
            emu.read(0x804305 + ch * 16, MEM) or 0,
            ok and (st["cpu.k"] or 0) or 0, ok and (st["cpu.pc"] or 0) or 0))
        end
      end
    end
  end
end, emu.callbackType.write, 0x80420B, 0x80420B, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  frames = frames + 1
  if frames == 800 then
    local hist = {}
    for i = 0, 127 do
      local y = emu.read(0x7E0200 + i * 4 + 1, MEM) or 0
      local at = emu.read(0x7E0200 + i * 4 + 3, MEM) or 0
      if y < 210 then
        local p = (at >> 4) & 3
        hist[p] = (hist[p] or 0) + 1
      end
    end
    local s = {}
    for p = 0, 3 do s[#s + 1] = string.format("pri%d=%d", p, hist[p] or 0) end
    log("shadow $7E:0200 priority histogram: " .. table.concat(s, " "))
  end
  if frames > 900 then log("done"); emu.stop(0) end
end, emu.eventType.endFrame)

print("probe_sms_oamdma loaded")
