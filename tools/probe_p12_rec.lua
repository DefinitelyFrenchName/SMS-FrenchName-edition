-- probe_p12_rec.lua (patch 12): harvest special-move records (and their +6 misfire acts).
-- The special dispatcher $C1:0B49 runs for EVERY recognized special (roll or not) with
-- Y = the 8-byte record in bank $C1. Config probe_p12_rec_cfg.lua:
--   STATE = savestate; PLAYER = 1|2 (who performs; directions auto-mirrored by side)
-- Tries a fixed motion list (qcf/qcb/hcf x LP/LK/HP) and logs every distinct record hit.
-- Output: appends traces/p12_rec.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
dofile(ENV.TOOLS .. "probe_p12_rec_cfg.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p12_rec.txt", "a"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end

local t, needLoad = -1, true
local base = (PLAYER == 1) and 0x1000 or 0x1080
local port = PLAYER - 1
local recs = {}

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. STATE, "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addMemoryCallback(function()
  if t and t >= 0 then
    local st = emu.getState()
    -- only records for OUR player: $88 holds the struct ptr of the object being processed
    local x = st["cpu.x"]
    if x == base then
      local y = st["cpu.y"]
      if not recs[y] then
        local b = {}
        for i = 0, 7 do b[i] = emu.read(0x10000 + y + i, emu.memType.snesPrgRom) end
        recs[y] = b
        log(string.format("%s p%d(cid%d) rec@C1:%04X = %02X %02X %02X %02X %02X %02X %02X %02X  (misfire act=%02X)",
          STATE, PLAYER, ram(base), y, b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[6]))
      end
    end
  end
end, emu.callbackType.exec, 0xC10B49, 0xC10B49, emu.cpuType.snes, emu.memType.snesMemory)

-- side-aware motion player
local function onLeft()
  local mex = ram(base + 0x21) + 256 * ram(base + 0x22)
  local ob = (PLAYER == 1) and 0x1080 or 0x1000
  local oth = ram(ob + 0x21) + 256 * ram(ob + 0x22)
  return mex <= oth
end
local MOTIONS = {
  { name = "qcf", dirs = { { down = true }, { down = true, fwd = true }, { fwd = true } } },
  { name = "qcb", dirs = { { down = true }, { down = true, back = true }, { back = true } } },
  { name = "hcf", dirs = { { back = true }, { down = true, back = true }, { down = true },
                           { down = true, fwd = true }, { fwd = true } } },
  { name = "hcb", dirs = { { fwd = true }, { down = true, fwd = true }, { down = true },
                           { down = true, back = true }, { back = true } } },
  { name = "dp",  dirs = { { fwd = true }, { down = true }, { down = true, fwd = true } } },
  { name = "dd",  dirs = { { down = true }, {}, { down = true } } },
  { name = "chb", charge = true,
    dirs = { { back = true }, { back = true }, { back = true }, { back = true },
             { back = true }, { back = true }, { back = true }, { back = true },
             { back = true }, { back = true }, { back = true }, { back = true },
             { back = true }, { back = true }, { back = true }, { fwd = true } } },
  { name = "chd", charge = true,
    dirs = { { down = true }, { down = true }, { down = true }, { down = true },
             { down = true }, { down = true }, { down = true }, { down = true },
             { down = true }, { down = true }, { down = true }, { down = true },
             { down = true }, { down = true }, { down = true }, { up = true } } },
}
local BTNS = { "y", "b", "x" }
local pulse = {}
emu.addEventCallback(function()
  local neutral = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
  local pads = { {}, {} }
  for k, v in pairs(neutral) do pads[1][k] = v; pads[2][k] = v end
  for k, v in pairs(pulse) do pads[PLAYER][k] = v end
  emu.setInput(pads[1], 0, 0); emu.setInput(pads[2], 0, 1)
end, emu.eventType.inputPolled)

local mi, bi, step = 1, 1, 0
emu.addEventCallback(function()
  if not t or t < 0 then return end
  t = t + 1
  if t < 30 then return end
  local L = onLeft()
  local function pad(d)
    local p = {}
    if d.down then p.down = true end
    if d.up then p.up = true end
    if d.fwd then if L then p.right = true else p.left = true end end
    if d.back then if L then p.left = true else p.right = true end end
    return p
  end
  local m = MOTIONS[mi]
  if not m then
    local n = 0
    for _ in pairs(recs) do n = n + 1 end
    log(string.format("=== %s p%d done, %d records", STATE, PLAYER, n))
    emu.stop(0); return
  end
  step = step + 1
  local sd = math.floor((step - 1) / 3) + 1
  if sd <= #m.dirs then
    pulse = pad(m.dirs[sd])
  elseif sd == #m.dirs + 1 then
    pulse = pad(m.dirs[#m.dirs]); pulse[BTNS[bi]] = true
  elseif sd == #m.dirs + 2 then
    pulse = {}
  elseif step > (#m.dirs + 2) * 3 + 90 then   -- wait out the move, next combo
    step = 0
    bi = bi + 1
    if bi > #BTNS then bi = 1; mi = mi + 1 end
  end
end, emu.eventType.endFrame)
print("probe_p12_rec loaded")
