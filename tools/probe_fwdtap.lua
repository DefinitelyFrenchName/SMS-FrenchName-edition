-- probe_fwdtap.lua — why does a FORWARD double-tap arm for Uranus and not Venus?
--
--   SMS_STATE=uranus_vs_jupiter.mss ROM=<clean>       tools/run.sh tools/probe_fwdtap.lua 60
--   SMS_STATE=venus_vs_jupiter_clean.mss ROM=<front>  tools/run.sh tools/probe_fwdtap.lua 60
--   -> traces/fwdtap_<tag>.txt
--
-- The double-tap recognizer ($C1:15C4) is shared code, and the only
-- per-character input to it is the 7-byte record at $C1:16AF + (charID-1)*7,
-- loaded into DP $08-$0E. Venus's forward-double-tap id (DP $09) was 00 — a zero
-- is rejected at $C1:167B — and the front-dash build sets it to 0x0C. She still
-- does not arm: +0x5E never increments, while Uranus's does under an identical
-- tap pattern on the CLEAN ROM.
--
-- So the question is which BRANCH she takes, and register state is not reachable
-- from a callback here (emu.getState() throws inside one — HANDOFF trap 8). Exec
-- hooks on the branch targets answer it without needing registers: whichever
-- site stops being hit is where the two diverge.
--
--   $C1:1626  lda $6B          the routine reached this frame with input
--   $C1:162E  jsr $03DC        passed `and #$03 / beq`, i.e. $6B has a h-direction
--   $C1:164E  lda $5C,X        BACK pair branch  (bit1 set)
--   $C1:1658  lda $5E,X        FORWARD pair branch (bit1 clear)
--   $C1:165C  stz $5D,X        forward pair ARMING (the else branch)
--   $C1:1679  lda $09          forward completion — reads the id
--   $C1:167D  sta $07          id accepted (non-zero, past the beq)
--
-- Counting only. Nothing that can throw goes in a memory callback (trap 12), so
-- the report is written from endFrame at the end.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local STATE = os.getenv("SMS_STATE") or "venus_vs_jupiter_clean.mss"
local TAG = os.getenv("SMS_TAG") or "x"
local OUT = assert(io.open(ENV.TRACE .. "fwdtap_" .. TAG .. ".txt", "w"))

local P1, P2 = 0x1000, 0x1080
local SITES = {
  { 0xC11626, "1626 routine reached" },
  { 0xC1162E, "162E has h-direction ($6B & 3)" },
  { 0xC1164E, "164E BACK pair branch" },
  { 0xC11658, "1658 FORWARD pair branch" },
  { 0xC1165C, "165C forward pair ARMS" },
  { 0xC11679, "1679 forward completion (reads id)" },
  { 0xC1167D, "167D id accepted" },
}
local hits, seen6b = {}, {}
for _, s in ipairs(SITES) do hits[s[2]] = 0 end

local t, loaded = -1, false
local phase, ps = "settle", 0

for _, s in ipairs(SITES) do
  local label = s[2]
  emu.addMemoryCallback(function()
    if phase ~= "tap" then return end
    hits[label] = hits[label] + 1
    if label == SITES[1][2] then
      local v = PL.ram(0x006B)
      seen6b[v] = (seen6b[v] or 0) + 1
    end
  end, emu.callbackType.exec, s[1], s[1], emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addMemoryCallback(function()
  if not loaded then
    local f = io.open(ENV.TRACE .. STATE, "rb")
    if not f then print("probe_fwdtap: cannot open " .. STATE); emu.stop(1); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss); loaded = true; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

-- forward = toward the opponent by position (the recognizer's own criterion)
local function fwd()
  local a = PL.ram(P1 + 0x21) + 256 * PL.ram(P1 + 0x22)
  local b = PL.ram(P2 + 0x21) + 256 * PL.ram(P2 + 0x22)
  return a < b and "right" or "left"
end

emu.addEventCallback(function()
  if t < 0 then return end
  local b = {}
  if phase == "tap" then
    local c = ps % 20
    if (c >= 0 and c < 5) or (c >= 9 and c < 14) then b[fwd()] = true end
  end
  emu.setInput(PL.pad(b), 0, 0)
  emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  ps = ps + 1
  if phase == "settle" then
    if ps > 60 then phase, ps = "tap", 0 end
  elseif phase == "tap" then
    if ps > 200 then
      OUT:write("forward double-tap instrumentation — " .. TAG .. " (" .. STATE .. ")\n")
      OUT:write(string.format("  P1 charID %d, act %02X, forward-dbltap id (DP $09 source) = %02X\n",
                PL.ram(P1), PL.ram(P1 + 0x01), PL.ram(P1 + 0x01) and 0 or 0))
      for _, s in ipairs(SITES) do
        OUT:write(string.format("  %-38s %5d\n", s[2], hits[s[2]]))
      end
      local ks = {}
      for v in pairs(seen6b) do ks[#ks + 1] = v end
      table.sort(ks)
      local parts = {}
      for _, v in ipairs(ks) do parts[#parts + 1] = string.format("%02X x%d", v, seen6b[v]) end
      OUT:write("  $6B values at $C1:1626: " .. table.concat(parts, ", ") .. "\n")
      OUT:write(string.format("  +0x5B/+0x5C = %02X/%02X   +0x5D/+0x5E = %02X/%02X\n",
                PL.ram(P1 + 0x5B), PL.ram(P1 + 0x5C), PL.ram(P1 + 0x5D), PL.ram(P1 + 0x5E)))
      OUT:close(); emu.stop(0)
    end
  end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_fwdtap loaded: " .. TAG)
