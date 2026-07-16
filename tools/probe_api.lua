-- probe_api.lua — one-shot Mesen 2 Lua API probe for the training-mode build (P-1).
-- Answers: (1) does emu.getInput see our own setInput? (2) drawSurface enum + ScriptHud
-- sizes at scale 1/2/4, (3) inputPolled vs exec@$80:8353 ordering, (4) hitstop identity
-- (+0x43 vs +0x4D) during a 2LP hit, (5) isKeyPressed name tolerance, (6) emu.* API keys.
-- Headless: ROM=<clean> tools/run.sh tools/probe_api.lua 90 → traces/probe_api.txt
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local log = io.open(TRACE .. "probe_api.txt", "w")
local function L(s) log:write(s .. "\n"); log:flush() end
local WRAM = emu.memType.snesWorkRam
local function r(a) return emu.read(a, WRAM) end

-- (6) API surface
local keys = {}
for k, v in pairs(emu) do keys[#keys+1] = k .. "(" .. type(v) .. ")" end
table.sort(keys)
L("emu keys: " .. table.concat(keys, " "))
for _, tname in ipairs({"drawSurface", "eventType", "callbackType", "memType", "cpuType"}) do
  local t = emu[tname]
  if type(t) == "table" then
    local ks = {}
    for k, v in pairs(t) do ks[#ks+1] = k .. "=" .. tostring(v) end
    table.sort(ks)
    L(tname .. ": " .. table.concat(ks, " "))
  else
    L(tname .. ": " .. tostring(t))
  end
end

-- (2) draw surface sizes
local ok, sz = pcall(emu.getScreenSize)
L("getScreenSize: " .. (ok and (sz.width .. "x" .. sz.height) or ("ERR " .. tostring(sz))))
if emu.drawSurface then
  for _, sc in ipairs({1, 2, 4}) do
    local ok2, err = pcall(emu.selectDrawSurface, emu.drawSurface.scriptHud, sc)
    local ok3, s2 = pcall(emu.getDrawSurfaceSize)
    L(string.format("selectDrawSurface(scriptHud,%d): %s; size=%s", sc,
      ok2 and "ok" or tostring(err), ok3 and (s2.width .. "x" .. s2.height) or tostring(s2)))
  end
  pcall(emu.selectDrawSurface, emu.drawSurface.consoleScreen)
end

-- (5) key name tolerance
for _, k in ipairs({"A", "Q", "1", "Space", "Shift", "Up Arrow", "UpArrow", "Enter", "Return", "F1"}) do
  local okk, v = pcall(emu.isKeyPressed, k)
  L("isKeyPressed('" .. k .. "'): " .. (okk and tostring(v) or ("ERR " .. tostring(v))))
end

-- state machine: load savestate, drive P1 2LP at t=60 point-blank, probe per frame
local t, needLoad = -1, true
local order = {}   -- (3) event-order log for a few frames

emu.addMemoryCallback(function()
  if needLoad then
    local f = io.open(TRACE .. "venus_vs_jupiter_clean.mss", "rb")
    if not f then L("NO STATE"); return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    needLoad = false; t = 0
  end
  if t >= 0 and t <= 3 then order[#order+1] = "exec8353@t=" .. t end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }
emu.addEventCallback(function()
  if t >= 0 and t <= 3 then order[#order+1] = "inputPolled@t=" .. t end
  if t < 0 then return end
  local p1 = {}; for k, v in pairs(FALSE) do p1[k] = v end
  -- Venus 5LP at t=60 (point-blank poked below) — any hit works for hitstop probe
  if t >= 60 and t < 63 then p1.y = true end
  emu.setInput(FALSE, 0, 1)
  emu.setInput(p1, 0, 0)
  -- (1) do getInput calls observe our injected inputs?
  if t == 61 then
    local ok1, g0 = pcall(emu.getInput, 0)
    local ok2, g1 = pcall(emu.getInput, 1)
    local function fmt(g) if type(g) ~= "table" then return tostring(g) end
      local on = {}; for k, v in pairs(g) do if v then on[#on+1] = k end end
      return "{" .. table.concat(on, ",") .. "}" end
    L("getInput(0) inside inputPolled at t=61 (we set y=true): " .. (ok1 and fmt(g0) or tostring(g0)))
    L("getInput(1): " .. (ok2 and fmt(g1) or tostring(g1)))
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if t < 0 then return end
  if t == 4 then L("order t0-3: " .. table.concat(order, " ")) end
  if t == 5 then emu.write(0x1021, 0xE8, WRAM) end
  if t >= 58 and t <= 90 then
    -- (4) hitstop identity + raw input words
    L(string.format("t=%03d p1act=%02X step=%02X hb=%02X a43=%02X a4D=%02X tick=%02X%02X | p2act=%02X hp=%02X | raw5C=%02X%02X raw5E=%02X%02X p1_50=%02X",
      t, r(0x1001), r(0x1002), r(0x1040), r(0x1043), r(0x104D), r(0x1007), r(0x1006),
      r(0x1081), r(0x10C9), r(0x5D), r(0x5C), r(0x5F), r(0x5E), r(0x1050)))
  end
  if t == 91 then log:close(); emu.stop(0) end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_api loaded")
