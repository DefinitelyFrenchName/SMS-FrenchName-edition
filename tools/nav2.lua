-- nav2.lua: closed-loop menu navigation using RAM feedback.
-- Mesen 2.1.1 quirk: emu.setInput(buttons, 0, port) -- port is the 3rd arg!
-- Steps defined in nav2_steps.lua:
--   type="pulse": press btn (3on/4off, period 7) on port until cond() true, then settle
--   type="wait":  wait until cond() true (or frames elapsed)
--   type="shot":  screenshot + optional WRAM dump, immediately continue
--   type="state": save savestate to file
--   type="stop":  end run
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local frames = 0
local stepIdx = 1
local stepFrame = 0
local pulsing = {}    -- port -> btn
local log = io.open(TRACE .. "nav2.txt", "w")

local function ram(addr) return emu.read(addr, emu.memType.snesWorkRam) end
local function w16(a) return ram(a) + 256 * ram(a + 1) end

dofile("/Users/koneko/Developer/SailorMoonS/tools/nav2_steps.lua")

local function L(s)
  log:write(string.format("f=%06d step=%02d %s\n", frames, stepIdx, s))
  log:flush()
  print(string.format("f=%06d step=%02d %s", frames, stepIdx, s))
end

emu.addEventCallback(function()
  for port = 0, 1 do
    local btn = pulsing[port]
    if btn then
      local on = (frames % 7) < 3
      emu.setInput({ [btn] = on }, 0, port)
    else
      emu.setInput({ a=false,b=false,x=false,y=false,l=false,r=false,
                     up=false,down=false,left=false,right=false,
                     start=false,select=false }, 0, port)
    end
  end
end, emu.eventType.inputPolled)

-- savestate support: exec callback on joy_read ($00:8353, runs every frame)
local pendingSave = nil
emu.addMemoryCallback(function()
  if pendingSave then
    local ss = emu.createSavestate()
    local f = io.open(pendingSave, "wb")
    if f then f:write(ss); f:close() end
    L("SAVESTATE written " .. pendingSave .. " len=" .. #ss)
    pendingSave = nil
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local function shot(name, dumpFrom, dumpTo)
  local f = io.open(TRACE .. name .. ".png", "wb")
  if f then f:write(emu.takeScreenshot()); f:close() end
  if dumpFrom then
    local hex = {}
    for a = dumpFrom, dumpTo do hex[#hex+1] = string.format("%02X", ram(a)) end
    L("DUMP " .. name .. string.format(" %04X-%04X ", dumpFrom, dumpTo) .. table.concat(hex))
  end
end

emu.addEventCallback(function()
  frames = frames + 1
  stepFrame = stepFrame + 1
  local st = STEPS[stepIdx]
  if not st then emu.stop(0) return end

  local advance = false
  if st.type == "pulse" then
    pulsing[st.port or 0] = st.btn
    if st.cond and st.cond(ram, w16) then advance = true
    elseif st.max and stepFrame >= st.max then L("PULSE TIMEOUT " .. st.btn) advance = true end
  elseif st.type == "wait" then
    pulsing = {}
    if st.cond and st.cond(ram, w16) then advance = true
    elseif st.frames and stepFrame >= st.frames then advance = true end
  elseif st.type == "poke" then
    emu.write(st.addr, st.val, emu.memType.snesWorkRam)
    advance = true
  elseif st.type == "shot" then
    shot(st.name, st.dumpFrom, st.dumpTo)
    advance = true
  elseif st.type == "state" then
    pendingSave = TRACE .. st.name
    advance = true
  elseif st.type == "stop" then
    log:close()
    emu.stop(0)
    return
  end

  if advance then
    L(string.format("step %d (%s%s) done", stepIdx, st.type, st.btn and (":" .. st.btn) or ""))
    stepIdx = stepIdx + 1
    stepFrame = 0
    pulsing = {}
  end
end, emu.eventType.endFrame)

print("nav2 loaded")
