-- probe_sms_despmatrix.lua — input-variation matrix for the desperation
-- (412364+HP). Variants: dir speed, post-motion delay before the button,
-- button held-through, ending direction. Reports new acts (>0x71 = candidate).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/despmatrix.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local DIRS5 = { {left=true},{left=true,down=true},{down=true},{down=true,right=true},{right=true} }
local DIRS6 = { {left=true},{left=true,down=true},{down=true},{down=true,right=true},{right=true},{left=true} }
local CASES = {
  { name="5dirs, back+HP imm",   dirs=5, per=3, delay=0 },
  { name="5dirs, back+HP d6",    dirs=5, per=3, delay=6 },
  { name="5dirs, back+HP d17",   dirs=5, per=3, delay=17 },
  { name="6dirs, d4",            dirs=6, per=3, delay=4 },
  { name="6dirs, d6",            dirs=6, per=3, delay=6 },
  { name="6dirs 4f, imm",        dirs=6, per=4, delay=0 },
}
local ci, t, needLoad = 1, -1, true
local acts = {}
local Q = 400
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  local c = CASES[ci]
  local p1 = PL.pad()
  if c and t >= Q then
    local dt = t - Q
    local D = (c.dirs == 5) and DIRS5 or DIRS6
    local total = c.per * #D
    if dt < total then
      p1 = PL.pad(D[math.floor(dt / c.per) + 1])
    elseif dt < total + c.delay then
      p1 = PL.pad(c.dirs == 5 and {} or { left = true })
    elseif dt <= total + c.delay + 2 then
      p1 = PL.pad({ left = true, x = true })
    end
  end
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
    wr(0x1049, 0x14)
  end
  if t > Q and t <= Q + 150 then acts[ram(0x1001)] = true end
  if t == Q + 150 then
    local l = {}
    for a in pairs(acts) do l[#l + 1] = string.format("%02X", a) end
    table.sort(l)
    log(string.format("%-20s acts[%s]", c.name, table.concat(l, " ")))
    acts = {}
    ci = ci + 1
    if not CASES[ci] then log("DONE"); emu.stop(0) end
    needLoad = true; t = -1
  end
end, emu.eventType.endFrame)
print("despmatrix loaded")
