-- probe_exp_bdsafety.lua — is the GROUND backdash still invulnerable, on every
-- entry path and on both player slots?
--
--   SMS_SLOT=0 ROM=<rom> tools/run.sh tools/probe_exp_bdsafety.lua 120
--   SMS_SLOT=1 ROM=<rom> tools/run.sh tools/probe_exp_bdsafety.lua 120
--   -> traces/bd_safety_<slot>.txt   (diff clean vs the experimental build)
--
-- WHY THIS EXISTS. A field report said the grounded backdash "feels less safe"
-- on the air-backdash build. The earlier probe compared ONE entry path (idle) on
-- ONE slot (P1) and found the trace frame-identical to clean — which is evidence
-- about one path, not about the move. Trap 1's shape: a per-state change tested
-- in one state. So this walks four entry paths on either slot.
--
-- Invulnerability in this engine is hurtbox index 0 (+0x41) and nothing else, so
-- the per-frame hurt index IS the safety measurement; the report per path is the
-- set of indices seen across the backdash.
--
-- Note the frame the act STARTS always shows the previous act's hurt index: the
-- box writer $C0:9CCD runs before the new act's animation is latched. That one
-- frame reads "not invulnerable" on the CLEAN ROM too, which is why the verdict
-- compares against clean rather than against the number 0.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local SLOT = tonumber(os.getenv("SMS_SLOT") or "0")          -- which slot Venus is in
local FIX = SLOT == 0 and "venus_vs_jupiter_clean.mss" or "jupiter_vs_venus_clean.mss"
local ME = SLOT == 0 and 0x1000 or 0x1080
local OUT = assert(io.open(ENV.TRACE .. "bd_safety_" .. SLOT .. ".txt", "w"))
local function log(s) OUT:write(s .. "\n"); OUT:flush() end

local ACT, HURT = 0x01, 0x41
local function me(o) return PL.ram(ME + o) end
local function back() return (me(0x09) ~= 0) and "right" or "left" end

-- entry paths: what is held before/while the double-tap goes in
local PATHS = {
  { name = "from idle",        pre = function() return {} end },
  { name = "from crouch",      pre = function() return { down = true } end },
  { name = "from walk fwd",    pre = function() return { [back() == "left" and "right" or "left"] = true } end },
  { name = "after a landing",  pre = function() return {} end, jumpFirst = true },
}

local t, loaded = -1, false
local pi, phase, ps = 1, "settle", 0
local rows, results = {}, {}

local function classify(rs)
  local hurts, dur, first = {}, 0, nil
  local ended = false
  for _, r in ipairs(rs) do
    if r.act == 0x26 and not ended then
      first = first or r; dur = dur + 1
      hurts[r.hurt] = (hurts[r.hurt] or 0) + 1
    elseif first and not ended and r.act ~= 0x26 then ended = true end
  end
  if dur == 0 then return "no backdash seen" end
  local ks = {}
  for h in pairs(hurts) do ks[#ks + 1] = h end
  table.sort(ks)
  local parts = {}
  for _, h in ipairs(ks) do parts[#parts + 1] = string.format("%02X x%d", h, hurts[h]) end
  local nonzero = 0
  for h, n in pairs(hurts) do if h ~= 0 then nonzero = nonzero + n end end
  return string.format("%2d frames, hurt %s  (%d non-zero frame%s)",
                       dur, table.concat(parts, ", "), nonzero, nonzero == 1 and "" or "s")
end

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. FIX, "rb")
    if not f then print("probe_exp_bdsafety: cannot open " .. FIX); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss); loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  local p, b = PATHS[pi], {}
  if p then
    if phase == "hold" then
      b = p.pre()
      if p.jumpFirst and ps < 6 then b = { up = true } end
    elseif phase == "tap" then
      b = p.pre()
      if (ps >= 0 and ps < 5) or (ps >= 9 and ps < 14) then b[back()] = true end
    end
  end
  emu.setInput(PL.pad(b), 0, SLOT)
  emu.setInput(PL.pad(), 0, 1 - SLOT)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  local p = PATHS[pi]
  ps = ps + 1
  if phase == "settle" then
    if ps > 40 then phase, ps = "hold", 0 end
  elseif phase == "hold" then
    if ps > (p.jumpFirst and 60 or 12) then phase, ps, rows = "tap", 0, {} end
  elseif phase == "tap" then
    rows[#rows + 1] = { act = me(ACT), hurt = me(HURT) }
    if ps > 45 then
      results[#results + 1] = string.format("  %-16s %s", p.name, classify(rows))
      pi = pi + 1; phase, ps = "settle", 0
      if not PATHS[pi] then
        log(string.format("ground backdash safety — Venus in slot P%d (%s)", SLOT + 1, FIX))
        for _, r in ipairs(results) do log(r) end
        OUT:close(); emu.stop(0)
      end
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_exp_bdsafety loaded: slot " .. SLOT)
