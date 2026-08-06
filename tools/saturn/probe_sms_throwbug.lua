-- probe_sms_throwbug.lua — reproduce the FIELD BUG where a thrown Saturn turns to
-- random tiles: P1 Jupiter walks into the L+R Saturn dummy and throws her
-- (forward+HP). Logs the CEL-DMA transfers around the throw, her pose bytes
-- (flagging any past her table's end $83), and a before/after VRAM fingerprint
-- of the stage-tile region; screenshots before/during. MODE (via lrmode_cfg):
-- "practice" (menu row 4) or "vscpu" (row 0); the dummy holds L+R to arm Saturn.
-- ROM=build/saturn/<rom> tools/run.sh tools/saturn/probe_sms_throwbug.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local MODE = "practice"
pcall(function() MODE = dofile(ENV.TOOLS .. "saturn/lrmode_cfg.lua") end)
local LOG = assert(io.open(ENV.TRACE .. "saturn/throwbug.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local hold = false

local function beat(on) return (frames % 7) < 3 and on or {} end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if p == 1 and hold then b.l = true; b.r = true end   -- arm the DUMMY
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local vram0 = {}
local MEMT = emu.memType.snesMemory
-- log the CEL streaming during the throw: which VRAM window each transfer
-- targets and how big it is. Her downed pose draws tiles that were never
-- uploaded (the field sees another character's hair in it), so the question is
-- whether the transfer for that pose happens at all.
local dmawin, dmalog = false, 0
emu.addMemoryCallback(function(_a, value)
  if not dmawin or dmalog > 26 then return end
  for ch = 0, 7 do
    if ((value or 0) >> ch) & 1 == 1 then
      local b = emu.read(0x804301 + ch * 16, MEMT) or 0
      if b == 0x18 or b == 0x19 then
        dmalog = dmalog + 1
        local sb = emu.read(0x804304 + ch * 16, MEMT) or 0
        local sa = ((emu.read(0x804303 + ch * 16, MEMT) or 0) << 8)
                 | (emu.read(0x804302 + ch * 16, MEMT) or 0)
        local ln = ((emu.read(0x804306 + ch * 16, MEMT) or 0) << 8)
                 | (emu.read(0x804305 + ch * 16, MEMT) or 0)
        log(string.format("    CEL-DMA src=$%02X:%04X len=%04X", sb, sa, ln))
      end
    end
  end
end, emu.callbackType.write, 0x80420B, 0x80420B, emu.cpuType.snes, MEMT)
local STEPS = {
  function() return frames >= 900 end,
  function()  -- menu row: vscpu = row 0 (default), practice = down to 1 then right to 4
    if MODE == "vscpu" then return sf > 30 end
    pulse[0] = beat({down = true}); return ram(0x1B10) == 1
  end,
  function()
    if MODE == "vscpu" then return true end
    pulse[0] = beat({right = true}); return ram(0x1B10) == 4
  end,
  function() pulse[0] = beat({start = true}); return sf > 40 end,
  function() pulse[0] = {}; return sf > 240 end,
  function() wr(0x1B40, 4); wr(0x1B80, 6); hold = true; return sf > 20 end,
  function() pulse[0] = beat({a = true}); return ram(0x1B42) == 1 or sf > 90 end,
  function() pulse[0] = {}; return sf > 30 end,
  function()  -- mash A/Start until actually IN MATCH ($0070==4)
    if MODE == "practice" then wr(0x1B80, 6) end
    pulse[0] = (frames % 14 < 3) and {a = true}
      or ((frames % 14 >= 7 and frames % 14 < 10) and {start = true} or {})
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 1500 then log("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() pulse[0] = {}; return ram(0x1FA) == 0x80 and sf > 120 end,
  -- THE FIELD BUG: when Saturn is THROWN her sprite becomes random tiles, and a
  -- command throw spreads the corruption into the STAGE tiles. P1 (Jupiter)
  -- walks into the Saturn dummy and throws her (forward + HP), with a VRAM
  -- fingerprint taken before and after.
  function()
    if sf == 1 then
      vram0 = {}
      for a = 0x4000, 0x5FFF, 64 do vram0[#vram0 + 1] = emu.read(a, emu.memType.snesVideoRam) or 0 end
      log(string.format("pre-throw: p1=%02X act=%02X  dummy=%02X act=%02X",
        ram(0x1000), ram(0x1001), ram(0x1080), ram(0x1081)))
      local f = io.open(ENV.TRACE .. "saturn/throwbug_before.png", "wb")
      if not f then print("probe_sms_throwbug.lua: cannot open " .. (ENV.TRACE .. "saturn/throwbug_before.png")) emu.stop(1) return end
      f:write(emu.takeScreenshot()); f:close()
    end
    pulse[0] = { right = true }
    return sf > 70
  end,
  function()                                    -- forward + HP = the throw
    pulse[0] = { right = true, x = true }
    dmawin = (sf >= 40 and sf <= 130)
    if sf <= 130 then
      local pose = ram(0x1098)
      if pose > 0x83 then
        log(string.format("  +%3df act=%02X POSE OUT OF RANGE: %02X (her table ends at 83)",
          sf, ram(0x1081), pose))
      elseif sf % 12 == 0 then
        log(string.format("  +%3df act=%02X pose=%02X", sf, ram(0x1081), pose))
      end
    end
    if sf == 60 or sf == 120 then
      local f = io.open(ENV.TRACE .. "saturn/throwbug_" .. sf .. ".png", "wb")
      if not f then print("probe_sms_throwbug.lua: cannot open " .. (ENV.TRACE .. "saturn/throwbug_" .. sf .. ".png")) emu.stop(1) return end
      f:write(emu.takeScreenshot()); f:close()
    end
    if sf > 130 then
      local n, diff = 0, 0
      for a = 0x4000, 0x5FFF, 64 do
        n = n + 1
        if (emu.read(a, emu.memType.snesVideoRam) or 0) ~= vram0[n] then diff = diff + 1 end
      end
      log(string.format("STAGE-TILE VRAM changed in %d of %d samples (%d%%)",
        diff, n, math.floor(100 * diff / n)))
      return true
    end
    return false
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if hold and frames % 25 == 0 then
    log(string.format("f=%d mode8D=%02X in70=%02X clock=%02X%02X e04=%02X flag=%02X p1=%02X act=%02X",
      frames, ram(0x8D), ram(0x70), ram(0x804), ram(0x803), ram(0x1E04),
      emu.read(0x7FF100, emu.memType.snesMemory), ram(0x1000), ram(0x1001)))
  end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then
    log(string.format("FINAL: p1=%02X %s", ram(0x1000),
      ram(0x1000) == 0x1C and "LR PASS" or "LR FAIL"))
    emu.stop(0)
  end
  if frames > 6000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("probe_sms_lrmodes loaded: " .. MODE)
