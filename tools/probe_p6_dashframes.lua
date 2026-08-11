-- probe_p6_dashframes.lua — Uranus's forward dash, frame by frame.
--
--   ROM=<rom> tools/run.sh tools/probe_p6_dashframes.lua 60
--   -> traces/p6_dashframes.txt
--
-- Patch 6 gates its invulnerability window on +0x5D, described in the builder as
-- "the dash-frame counter (1..14)". That is worth measuring rather than trusting:
-- +0x5D is really the motion recognizer's timer for motion 1 (the 66), it
-- increments every frame and RESETS when it reaches $0F ($C1:1618), so its
-- relationship to the dash's own frames holds only as long as the dash is short
-- enough not to wrap. This logs act, +0x5D and the hurtbox index together so the
-- window can be expressed in the frames the maintainer actually means.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "p6_dashframes.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local P1, P2 = 0x1000, 0x1080
local STATE = os.getenv("SMS_STATE") or "uranus_vs_jupiter.mss"
local t, loaded, phase, ps = -1, false, "settle", 0
local rows = {}

local function p1(o) return PL.ram(P1 + o) end
local function px(b) return PL.ram(b + 0x21) + 256 * PL.ram(b + 0x22) end
-- forward = toward the opponent, which is what the recognizer itself compares
local function fwd() return px(P1) < px(P2) and "right" or "left" end

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_p6_dashframes: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss); loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  local b = {}
  if phase == "tap" then
    -- ONE double-tap, and its rhythm is a variable: GAP shifts the second tap so
    -- the same dash can be produced with a different recognizer-timer phase.
    local gap = tonumber(os.getenv("SMS_GAP") or "9")
    if (ps >= 0 and ps < 5) or (ps >= gap and ps < gap + 5) then b[fwd()] = true end
  end
  emu.setInput(PL.pad(b), 0, 0)
  emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  ps = ps + 1
  if phase == "settle" then
    if ps > 60 then phase, ps = "tap", 0 end
  else
    rows[#rows + 1] = { t = ps, act = p1(0x01), c = p1(0x5D), hurt = p1(0x41),
                        step = p1(0x02), tick = p1(0x06), frame = p1(0x07), x = px(P1),
                        vx = p1(0x30) | (p1(0x31) << 8), vy = p1(0x32) | (p1(0x33) << 8),
                        st = p1(0x16), y = p1(0x25) }
    if ps > 40 then
      local dash = {}
      for _, r in ipairs(rows) do if r.act == 0x60 then dash[#dash + 1] = r end end
      log("Uranus forward dash (act 0x60), frame by frame:")
      for i, r in ipairs(dash) do
        local function s16(v) return v >= 0x8000 and v - 0x10000 or v end
        log(string.format("  dash frame %2d: +5D=%02X +02=%02X +06=%02X vx=%6d vy=%6d st=%02X y=%3d hurt=%02X%s",
            i, r.c, r.step, r.tick, s16(r.vx), s16(r.vy), r.st, r.y, r.hurt,
            r.hurt == 0 and "  INVULN" or ""))
      end
      local inv = 0
      for _, r in ipairs(dash) do if r.hurt == 0 then inv = inv + 1 end end
      log(string.format("  -> %d frames of act 0x60; +0x5D runs %02X..%02X; %d invulnerable",
          #dash, #dash > 0 and dash[1].c or 0, #dash > 0 and dash[#dash].c or 0, inv))
      LOG:close(); emu.stop(0)
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_p6_dashframes loaded")
