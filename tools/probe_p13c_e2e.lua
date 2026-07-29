-- probe_p13c_e2e.lua: v0.13 nerf E2E reproduction. Config probe_p13c_e2e_cfg.lua:
--   SCEN = "vsproj"  : neptune VS state, P2 real-taunts x3 (L), P1 fireballs P2
--   SCEN = "prmelee" : training_p11 Practice, DAMAGE on via p11 flags, P2 taunts x3,
--                      P1 does 236236P (Uranus special-class melee) into P2
-- Logs LV2 timeline, P2 hp deltas per hit, and the attacker +0x44 at impact.
-- Output: appends traces/p13c_e2e.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
dofile(ENV.TOOLS .. "probe_p13c_e2e_cfg.lua")
TAUNTS = TAUNTS or 3
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p13c_e2e.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function wr(a, v) emu.write(a, v, WRAM) end

local t, needLoad = -1, true
local STATE = (SCEN == "uranus") and "uranus_vs_jupiter.mss" or ((SCEN == "vsproj") and "neptune_vs_jupiter.mss" or "training_p11.mss")
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function(addr, value)
  if t and t >= 0 then
    local st = emu.getState()
    local pc = st["cpu.k"] * 65536 + st["cpu.pc"]
    log(string.format("  hpwrite t=%d ->%02X pc=%06X LV2=%d p1a44=%02X j1a44=%02X",
      t, value, pc, ram(0x1F802), ram(0x1044), ram(0x1144)))
  end
end, emu.callbackType.write, 0x10C9, 0x10C9, emu.cpuType.snes, emu.memType.snesWorkRam)

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local prevLv = -1
emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  local lv = ram(0x1F802)
  if lv ~= prevLv then log(string.format("  LV2 %d->%d t=%d p2act=%02X", prevLv, lv, t, ram(0x1081))); prevLv = lv end
  if t == 2 then log(string.format("=== %s mode=%02X", SCEN, ram(0x8D))) end
  if SCEN == "prmelee" and t == 5 then wr(0x8D, 5); wr(0x1F004, 0xA5) end   -- p11 DAMAGE on
  -- P2 taunts x3 (L on port 1)
  local tlist = { 30, 220, 410 }
  for i = 1, TAUNTS do
    local tt = tlist[i]
    if t >= tt and t <= tt + 2 then pulse[1] = { l = true } elseif t == tt + 3 then pulse[1] = nil end
  end
  if SCEN == "uranus" then
    -- P1 Uranus: qcf+Y then qcb+Y then hcf+Y volleys from t=650 (find World Shaking)
    local seqs = {
      { 650, { {down=true},{down=true,right=true},{right=true},{right=true,y=true} } },
      { 780, { {down=true},{down=true,left=true},{left=true},{left=true,y=true} } },
      { 910, { {left=true},{down=true,left=true},{down=true},{down=true,right=true},{right=true},{right=true,y=true} } },
      { 1040, { {right=true},{down=true,right=true},{down=true},{down=true,left=true},{left=true},{left=true,y=true} } },
    }
    if t == 645 then log(string.format("pre-special LV2=%d p2hp=%02X p1act=%02X", ram(0x1F802), ram(0x10C9), ram(0x1001))) end
    for _, sq in ipairs(seqs) do
      for i, d in ipairs(sq[2]) do
        if t == sq[1] + i * 3 then pulse[0] = d end
      end
      if t == sq[1] + (#sq[2] + 1) * 3 then pulse[0] = nil end
    end
    if t >= 650 and ram(0x1001) >= 0x2B and not _seenacts then _seenacts = {} end
    if _seenacts and ram(0x1001) >= 0x2B and not _seenacts[ram(0x1001)] then
      _seenacts[ram(0x1001)] = true
      log(string.format("  p1 special act %02X a44=%02X j1=%02X", ram(0x1001), ram(0x1044), ram(0x1144)))
    end
    if t == 1200 then
      log(string.format("VERDICT uranus: p2hp=%02X totaldealt=%d LV2=%d", ram(0x10C9), 0x60 - ram(0x10C9), ram(0x1F802)))
      emu.stop(0)
    end
  elseif SCEN == "vsproj" then
    -- P1 Neptune 214LP at t=650
    if t == 650 then log(string.format("pre-special LV2=%d p2hp=%02X", ram(0x1F802), ram(0x10C9))) end
    if t == 654 then pulse[0] = { down = true } end
    if t == 657 then pulse[0] = { down = true, left = true } end
    if t == 660 then pulse[0] = { left = true, y = true } end
    if t == 663 then pulse[0] = nil end
    if t == 800 then
      log(string.format("VERDICT vsproj: p2hp=%02X dealt=%d LV2=%d", ram(0x10C9), 0x60 - ram(0x10C9), ram(0x1F802)))
      emu.stop(0)
    end
  else
    -- P1 Uranus 236236P at t=650 (park P2 at range 40 first)
    if t == 645 then
      local p1x = ram(0x1021) + 256 * ram(0x1022)
      wr(0x10A1, (p1x + 40) % 256); wr(0x10A2, math.floor((p1x + 40) / 256))
      log(string.format("pre-special LV2=%d p2hp=%02X", ram(0x1F802), ram(0x10C9)))
    end
    for i, d in ipairs({ { down = true }, { down = true, right = true }, { right = true },
                         { down = true }, { down = true, right = true }, { right = true, y = true } }) do
      if t == 648 + i * 3 then pulse[0] = d end
    end
    if t == 667 then pulse[0] = nil end
    if t == 800 then
      log(string.format("VERDICT prmelee: p2hp=%02X dealt=%d LV2=%d p1act=%02X", ram(0x10C9), 0x60 - ram(0x10C9), ram(0x1F802), ram(0x1001)))
      emu.stop(0)
    end
  end
end, emu.eventType.endFrame)
print("probe_p13c_e2e loaded")
