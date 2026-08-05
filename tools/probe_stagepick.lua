-- probe_stagepick.lua — which stages can the VS config screen actually reach?
--
-- Patch 17 asks for every stage selectable. The guess was a 0-8 range check, but
-- the vendor patcher (sms_patcher.py PATCH_NAKAYOSHI) unlocks the hidden stage
-- with ONE byte at $C3:BADE, turning `sta $1F59` into `stz $1F59` -- i.e. the
-- gate is a FLAG, not a range. This measures the reachable set either way: sit
-- on the config screen, cycle the stage row, and log every distinct value of
-- $7E:1838 (the selected stage).
--
--   ROM=<rom> TAG=clean tools/run.sh tools/probe_stagepick.lua 500
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local TAG = os.getenv("TAG") or "stagepick"
local LOG = assert(io.open(ENV.TRACE .. "stagepick_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush(); print(s) end
local frames, step, sf = 0, 1, 0
local pulse, seen = {}, {}
local function beat(on) return (frames % 7) < 3 and on or {} end
emu.addEventCallback(function()
  for p = 0, 1 do emu.setInput(pulse[p] and PL.pad(pulse[p]) or PL.pad(), 0, p) end
end, emu.eventType.inputPolled)
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,   -- 1P vs 2P
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 150 end,
  function() pulse[0] = {}; return sf > 20 end,
  function() pulse[1] = beat({ a = true }); return ram(0x1B82) == 1 or sf > 150 end,
  function() pulse[0] = {}; pulse[1] = {}; return sf > 90 end,
  function()   -- on the config screen: walk rows and cycle values
    local m = sf % 40
    if m < 4 then pulse[0] = { down = true }
    elseif m < 20 then pulse[0] = beat({ right = true })
    elseif m < 24 then pulse[0] = { up = true }
    else pulse[0] = beat({ left = true }) end
    -- $1838 is the stage at MATCH time; on this screen it stays 0, so the live
    -- selector is a different byte. Sweep the config screen's own state blocks
    -- ($1800-$18FF per annotations, plus $1B00-$1BFF) for a byte that cycles
    -- through a stage-sized set of values.
    if sf % 2 == 0 then
      for _, lo in ipairs({ 0x1800, 0x1B00 }) do
        for a = lo, lo + 0xFF do
          local v = ram(a)
          local t = seen[a]
          if not t then t = {}; seen[a] = t end
          t[v] = true
        end
      end
    end
    if sf == 1799 then
      -- Assert the precondition: a screenshot proves which screen this is. The
      -- first run reported "only stage 0 reachable" on BOTH ROMs, which is the
      -- signature of a harness that never got to the stage row.
      local f = io.open((os.getenv("SHOTDIR") or ENV.TRACE) .. "stagepick_" .. TAG .. ".png", "wb")
      if f then f:write(emu.takeScreenshot()); f:close() end
      log(string.format("context: $1838=%d $008E=%d $1B10=%d $0070=%d",
        ram(0x1838), ram(0x8E), ram(0x1B10), ram(0x70)))
    end
    return sf > 1800
  end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    local cands = {}
    for a, t in pairs(seen) do
      local vals = {}
      for v in pairs(t) do vals[#vals + 1] = v end
      table.sort(vals)
      -- a stage selector cycles a handful of small values
      if #vals >= 5 and #vals <= 12 and vals[1] <= 1 and vals[#vals] <= 12 then
        cands[#cands + 1] = string.format("$%04X: %d values %s", a, #vals,
          table.concat((function() local q={} for _,v in ipairs(vals) do q[#q+1]=tostring(v) end return q end)(), ","))
      end
    end
    table.sort(cands)
    log("STAGEPICK tag=" .. TAG .. " candidate selectors: " .. #cands)
    for _, l in ipairs(cands) do log("  " .. l) end
    LOG:close(); emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT step " .. step); LOG:close(); emu.stop(1) end
end, emu.eventType.endFrame)
