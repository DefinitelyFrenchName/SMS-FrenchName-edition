-- probe_p93_glyphdma.lua — issue #93: the label glyph font must NOT re-upload every vblank.
--
-- Loads traces/uranus_vs_jupiter.mss on a patch-10b (labels) ROM and counts font
-- uploads by watching writes of 1 to GLYPH_FLAG ($0910) — the uploader's last act.
-- Phase 1 (idle, 300 frames): both labels idle; the unfixed build re-arms the flag
-- every frame so the 224-byte font DMAs every vblank (~300 uploads); fixed, zero.
-- Phase 2 (one TECH label forced via the producer-hook poke, as probe_p88 does):
-- the lazy path must still upload at least once so the label draws with a font.
--   PASS: idle uploads <= 2 AND at least one upload once the label fires.
-- Run: ROM=build/sms_combolabels.sfc tools/run.sh tools/probe_p93_glyphdma.lua 90
-- Out: traces/probe_p93_glyphdma.txt

local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local WRAM = emu.memType.snesWorkRam
local function w(a, v) emu.write(a, v, WRAM) end

local STATE = ENV.ROOT .. "traces/uranus_vs_jupiter.mss"
local OUT = ENV.ROOT .. "traces/probe_p93_glyphdma.txt"
local IDLE_FROM, IDLE_TO, LABEL_AT, VERDICT = 30, 330, 340, 420

local t, uploads = 0, 0
local idleUploads, labelUploads = nil, nil

local __loaded = false
emu.addMemoryCallback(function()
  if not __loaded then
    local f = io.open(STATE, "rb")
    if not f then print("probe_p93: missing savestate " .. STATE); emu.stop(1); return end
    emu.loadSavestate(f:read("*a")); f:close(); __loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr, value)
  if value == 1 then uploads = uploads + 1 end
end, emu.callbackType.write, 0x0910, 0x0910, emu.cpuType.snes, emu.memType.snesWorkRam)

-- force one TECH edge at the producer hook (engine can't undo it before detect runs)
emu.addMemoryCallback(function()
  if __loaded and t == LABEL_AT then
    w(0x1001, 0x23); w(0x0900, 0x00)
  end
end, emu.callbackType.exec, 0x80D5E8, 0x80D5E8, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if not __loaded then return end
  t = t + 1
  if t == IDLE_FROM then uploads = 0 end
  if t == IDLE_TO then idleUploads = uploads end
  if t == VERDICT then
    labelUploads = uploads - idleUploads
    local ok = idleUploads <= 2 and labelUploads >= 1
    local log = io.open(OUT, "w")
    log:write(string.format(
      "idle uploads (300f)=%d  uploads after label=%d -> %s\n",
      idleUploads, labelUploads,
      ok and "PASS (lazy upload)"
         or (idleUploads > 2 and "FAIL (font re-uploads while idle)"
                              or "FAIL (label never triggered an upload)")))
    log:close()
    emu.stop(ok and 0 or 1)
  end
end, emu.eventType.endFrame)

print("probe_p93_glyphdma loaded")
