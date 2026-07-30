-- probe_sms_fireball.lua — verify Saturn's PORTED PROJECTILE in SMS: qcf+LP spawns
-- object 0x20, its ported proc/script animate and move it, it travels and despawns
-- (and at close range HITS). Uploads the effect tiles (traces/saturn/
-- supers_effecttiles.bin -> VRAM $6A00) so the fireball is VISIBLE; screenshots it.
-- ROM=build/saturn/SailorMoonS_saturn_smoke.sfc tools/run.sh tools/saturn/probe_sms_fireball.lua 300
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/fireball.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr

local CASES = {
  { name = "travel+despawn", dist = 200 },
  { name = "hits Jupiter", dist = 70, expectHit = true },
}
local ci, t, needLoad = 1, -1, true
local seen, sawHit, maxX, shot = {}, false, 0, false
local PRESS = 140

local function uploadTiles()
  local f = io.open(ENV.TRACE .. "saturn/supers_effecttiles.bin", "rb")
  if not f then log("WARN: no effect tiles dump; fireball will use Uranus tiles") return end
  local d = f:read("*a"); f:close()
  local V = emu.memType.snesVideoRam
  for i = 1, #d do emu.write(0x6A00 * 2 + i - 1, d:byte(i), V) end
  log("effect tiles uploaded to VRAM $6A00 (" .. #d .. " B)")
end

emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  local p1 = PL.pad()
  local q = PRESS
  if t == q or t == q + 1 then p1 = PL.pad({ down = true })
  elseif t == q + 2 or t == q + 3 then p1 = PL.pad({ down = true, right = true })
  elseif t == q + 4 or t == q + 5 then p1 = PL.pad({ right = true })
  elseif t == q + 6 or t == q + 7 then p1 = PL.pad({ right = true, y = true }) end
  emu.setInput(p1, 0, 0); emu.setInput(PL.pad(), 0, 1)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  local c = CASES[ci]
  if not c then return end
  if t == 60 then
    wr(0x1000, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1000 + o, 0) end
    uploadTiles()
  end
  if t == PRESS - 12 then
    local px = ram(0x1021) + 256 * ram(0x1022)
    local x = px + c.dist
    wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
  end
  if t > PRESS and t <= PRESS + 120 then
    local id = ram(0x1100)
    if id ~= 0 then
      local act, pose = ram(0x1101), ram(0x1105)
      local x = ram(0x1121) + 256 * ram(0x1122)
      seen[string.format("id%02X/act%02X/pose%02X", id, act, pose)] = true
      if x > maxX then maxX = x end
      if not shot and x > (ram(0x1021) + 256 * ram(0x1022)) + 95 then
        shot = true
        local png = emu.takeScreenshot()
        local f = assert(io.open(ENV.TRACE .. "saturn/saturn_fireball.png", "wb"))
        f:write(png); f:close()
        for si = 0, 60 do
          local o = 0x0200 + 4 * si
          local tile = ram(o + 2)
          if ram(o + 1) < 0xE0 and (tile >= 0xA0) then
            log(string.format("  ball oam%02d: x=%02X y=%02X tile=%02X attr=%02X",
              si, ram(o), ram(o + 1), tile, ram(o + 3)))
          end
        end
      end
    end
    local a2 = ram(0x1081)
    if a2 >= 0x0E and a2 <= 0x16 then sawHit = true end
  end
  if t == PRESS + 120 then
    local ls = {}
    for k in pairs(seen) do ls[#ls + 1] = k end
    table.sort(ls)
    local alive = ram(0x1100) ~= 0
    local p1x = ram(0x1021) + 256 * ram(0x1022)
    local verdict
    if c.expectHit then verdict = sawHit and "FIREBALL-HITS" or "NO-HIT"
    else verdict = (#ls > 0 and not alive and maxX > p1x + 80) and "TRAVELED+DESPAWNED"
                   or (#ls == 0 and "NO-SPAWN" or (alive and "STUCK-ALIVE" or "SHORT-TRAVEL"))
    end
    log(string.format("%-16s states[%s] maxX=%d p1x=%d hit=%s -> %s",
      c.name, table.concat(ls, " "), maxX, p1x, tostring(sawHit), verdict))
    seen, sawHit, maxX, shot = {}, false, 0, false
    ci = ci + 1
    if not CASES[ci] then log("DONE"); emu.stop(0) end
    needLoad = true; t = -1
  end
end, emu.eventType.endFrame)
print("probe_sms_fireball loaded")
