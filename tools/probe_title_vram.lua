-- probe_title_vram.lua — boot to the title screen, dump VRAM + CGRAM + screenshot.
-- ROM=<rom> OUT=<tag> tools/run.sh tools/probe_title_vram.lua 60
-- Output: traces/titlevram_<tag>.{bin,cgram,png} at frame 420 (title screen up).
local TRACE = "/Users/koneko/Developer/SailorMoonS/traces/"
local TAG = os.getenv("OUT") or "clean"
local t = 0
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

emu.addEventCallback(function()
  local b = {}
  for k, v in pairs(FALSE) do b[k] = v end
  if (t % 260) >= 160 and (t % 260) <= 161 then b.start = true end
  emu.setInput(b, 0, 0)
end, emu.eventType.inputPolled)

local DUMPS = { [700]=true, [1000]=true, [1300]=true }
emu.addEventCallback(function()
  t = t + 1
  if DUMPS[t] then
    local f = io.open(TRACE .. "titlevram_" .. TAG .. "_" .. t .. ".bin", "wb")
    local buf = {}
    for a = 0, 0xFFFF do buf[#buf+1] = string.char(emu.read(a, emu.memType.snesVideoRam)) end
    f:write(table.concat(buf)); f:close()
    f = io.open(TRACE .. "titlevram_" .. TAG .. "_" .. t .. ".cgram", "wb")
    buf = {}
    for a = 0, 0x1FF do buf[#buf+1] = string.char(emu.read(a, emu.memType.snesCgRam)) end
    f:write(table.concat(buf)); f:close()
    local png = emu.takeScreenshot()
    f = io.open(TRACE .. "titlevram_" .. TAG .. "_" .. t .. ".png", "wb"); f:write(png); f:close()
    if t >= 1300 then emu.stop(0) end
  end
end, emu.eventType.endFrame)
print("probe_title_vram loaded, tag=" .. TAG)
