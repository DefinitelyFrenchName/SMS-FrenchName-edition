-- probe_hud.lua — ScriptHud runtime probe: surface sizes at runtime, drawRectangle/String
-- on scriptHud at scale 2, ruler grid, measureString metrics. Screenshot both surfaces to
-- traces/probe_hud.png for visual inspection. Headless-friendly.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local log = assert(io.open(TRACE .. "probe_hud.txt", "w"), "probe_hud.lua: cannot open " .. (TRACE .. "probe_hud.txt"))
local t, needLoad = -1, true

emu.addMemoryCallback(function()
  if needLoad then
    local f = io.open(TRACE .. "venus_vs_jupiter_clean.mss", "rb")
    if not f then print("probe_hud.lua: cannot open " .. (TRACE .. "venus_vs_jupiter_clean.mss")) emu.stop(1) return end
    local ss = f:read("*a"); f:close()
    emu.loadSavestate(ss)
    needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if t < 0 then return end
  if t == 30 then
    for _, sc in ipairs({1, 2, 4}) do
      local ok = pcall(emu.selectDrawSurface, emu.drawSurface.scriptHud, sc)
      local ok2, s = pcall(emu.getDrawSurfaceSize)
      log:write(string.format("runtime scriptHud scale=%d: sel=%s size=%s\n", sc,
        tostring(ok), ok2 and (tostring(s.width) .. "x" .. tostring(s.height)) or tostring(s)))
    end
    pcall(emu.selectDrawSurface, emu.drawSurface.consoleScreen)
    local ok3, cs = pcall(emu.getDrawSurfaceSize)
    log:write("runtime consoleScreen size=" ..
      (ok3 and (tostring(cs.width) .. "x" .. tostring(cs.height)) or tostring(cs)) .. "\n")
    local ok4, m = pcall(emu.measureString, "S4 A5 R4")
    log:write("measureString('S4 A5 R4') = " ..
      (ok4 and (tostring(m.width) .. "x" .. tostring(m.height)) or tostring(m)) .. "\n")
    log:flush()
  end
  if t >= 30 and t <= 60 then
    -- draw a frame-meter mock on scriptHud @2 every frame
    pcall(emu.selectDrawSurface, emu.drawSurface.scriptHud, 2)
    emu.drawRectangle(14, 398, 484, 46, 0x101014, true)
    for i = 0, 79 do
      local col = (i % 13 < 4) and 0x28B04C or (i % 13 < 9) and 0xE03028 or 0x3058D8
      emu.drawRectangle(16 + i * 6, 404, 5, 10, col, true)
      emu.drawRectangle(16 + i * 6, 418, 5, 10, 0x3A3A42, true)
    end
    emu.drawString(16, 388, "P1 5LP  S4 A5 R4 T13   hit +6", 0xFFFFFF, 0x000000)
    emu.drawString(240, 414, "+6", 0x40FF40, 0x000000)
    -- console-surface reference text
    pcall(emu.selectDrawSurface, emu.drawSurface.consoleScreen)
    emu.drawString(8, 8, "consoleScreen ref", 0xFFFF00, 0x000000)
  end
  if t == 55 then
    local shot = emu.takeScreenshot()
    local f = io.open(TRACE .. "probe_hud.png", "wb")
    if not f then print("probe_hud.lua: cannot open " .. (TRACE .. "probe_hud.png")) emu.stop(1) return end
    f:write(shot); f:close()
    log:write("screenshot bytes=" .. tostring(#shot) .. "\n"); log:flush()
  end
  if t == 62 then log:close(); emu.stop(0) end
  t = t + 1
end, emu.eventType.endFrame)

print("probe_hud loaded")
