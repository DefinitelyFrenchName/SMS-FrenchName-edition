-- probe_p11_res.lua (patch 11, P9+P10): resource probes in native training mode.
--  P10: read/write watch on WRAM $0816-$09FF and bank $7F ($10000-$1FFFF) across
--       play + movelist (Start) + exit (Select) -> which bytes does the game touch?
--  P9:  BG3 menu real estate: locate initial nonblank cells (row map), write digit
--       test words to rows 8-15, screenshot (visible?), readback at +160f (stable?),
--       and log PPU scroll state keys.
-- Output: traces/p11_res.txt (+ p11_res_rows.png)
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p11_res.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end
local function vread(b) return emu.read(b, emu.memType.snesVideoRam) end
local function vwrite(b, v) emu.write(b, v, emu.memType.snesVideoRam) end

local t, needLoad = -1, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local touched, touched7F = {}, {}
for _, cb in ipairs({ emu.callbackType.read, emu.callbackType.write }) do
  emu.addMemoryCallback(function(addr) if t >= 0 then touched[addr] = true end end,
    cb, 0x0816, 0x09FF, emu.cpuType.snes, emu.memType.snesWorkRam)
  emu.addMemoryCallback(function(addr) if t >= 0 then touched7F[math.floor(addr / 256)] = true end end,
    cb, 0x10000, 0x1FFFF, emu.cpuType.snes, emu.memType.snesWorkRam)
end

local pulse = {}
emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k,v in pairs(b) do base[k]=v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local testCells = {}
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1

  if t == 10 then
    -- initial nonblank map by row
    local rows = {}
    for w = 0x1000, 0x13FF do
      local word = vread(w * 2) + 256 * vread(w * 2 + 1)
      if word ~= 0x2000 and word ~= 0x0000 then
        local r = math.floor((w - 0x1000) / 32)
        rows[r] = (rows[r] or 0) + 1
      end
    end
    local s = "nonblank rows:"
    for r = 0, 31 do if rows[r] then s = s .. string.format(" r%d=%d", r, rows[r]) end end
    log(s)
    -- scroll-ish state keys
    local st = emu.getState()
    for k, v in pairs(st) do
      if type(k) == "string" and (k:find("croll") or k:find("layer")) then
        log(string.format("state %s = %s", k, tostring(v)))
      end
    end
  end
  if t == 30 then
    for r = 8, 15 do
      for i = 0, 9 do
        local w = 0x1000 + r * 32 + 4 + i
        vwrite(w * 2, 0x50 + i); vwrite(w * 2 + 1, 0x2C)
        testCells[#testCells + 1] = w
      end
    end
    log("wrote digit rows 8-15 cols 4-13")
  end
  if t == 45 then
    local f = io.open(TRACE .. "p11_res_rows.png", "wb")
    if not f then print("probe_p11_res.lua: cannot open " .. (TRACE .. "p11_res_rows.png")) emu.stop(1) return end
    f:write(emu.takeScreenshot()); f:close()
  end
  -- some fighting action for realistic WRAM traffic
  if t >= 60 and t <= 140 then
    if t % 20 < 3 then pulse[0] = { down = true, y = true }
    elseif t % 20 < 6 then pulse[0] = { right = true, x = true }
    else pulse[0] = nil end
  end
  if t == 190 then
    local intact, gone = 0, 0
    for _, w in ipairs(testCells) do
      local word = vread(w * 2) + 256 * vread(w * 2 + 1)
      if word >= 0x2C50 and word <= 0x2C59 then intact = intact + 1 else gone = gone + 1 end
    end
    log(string.format("t=%d testcells intact=%d gone=%d", t, intact, gone))
    for _, w in ipairs(testCells) do vwrite(w * 2, 0x00); vwrite(w * 2 + 1, 0x20) end
    log("testcells cleared")
  end
  -- movelist open/close
  if t >= 220 and t <= 222 then pulse[0] = { start = true } end
  if t == 223 then pulse[0] = nil end
  if t == 300 then log(string.format("movelist f01FA=%02X", ram(0x1FA))) end
  if t >= 320 and t <= 322 then pulse[0] = { start = true } end
  if t == 323 then pulse[0] = nil end
  -- exit via Select
  if t >= 400 and t <= 402 then pulse[0] = { select = true } end
  if t == 403 then pulse[0] = nil end
  if t == 560 then
    local list = {}
    for a in pairs(touched) do list[#list + 1] = a end
    table.sort(list)
    local s, n = "wram touched:", 0
    for _, a in ipairs(list) do s = s .. string.format(" %04X", a); n = n + 1 end
    log(string.format("wram $0816-$09FF touched=%d", n)); log(s)
    local p7 = {}
    for pg in pairs(touched7F) do p7[#p7 + 1] = pg end
    table.sort(p7)
    local s7 = ""
    for _, pg in ipairs(p7) do s7 = s7 .. string.format(" %02X", pg - 0x100) end
    log(string.format("bank7F touched pages=%d:%s", #p7, s7))
    log("done"); emu.stop(0)
  end
end, emu.eventType.endFrame)

print("probe_p11_res loaded")
