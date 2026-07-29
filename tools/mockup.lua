-- mockup.lua: at the title screen, overwrite the subtitle CHR tiles in VRAM with the
-- tiles from traces/subtitle_tiles.txt, then screenshot. NO ROM change.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local OUT = os.getenv("MOCKOUT") or "title_mockup"
local frames = 0
local wrote = false

-- load tiles: lines "<tileHex> <32byteHex>"
local tiles = {}
for line in io.lines(TRACE .. "subtitle_tiles.txt") do
  local id, hex = line:match("(%x+)%s+(%x+)")
  if id then tiles[#tiles+1] = { tonumber(id,16), hex } end
end

local function writeTile(tid, hex)
  local base = 0x4000 + tid*32  -- VRAM byte address of the tile
  for i = 0, 31 do
    local byte = tonumber(hex:sub(i*2+1, i*2+2), 16)
    emu.write(base + i, byte, emu.memType.snesVideoRam)
  end
end

emu.addEventCallback(function()
  frames = frames + 1
  if frames == 990 then  -- before shot
    local f = io.open(TRACE .. OUT .. "_before.png", "wb"); f:write(emu.takeScreenshot()); f:close()
  end
  if frames >= 1000 and frames <= 1008 then  -- write every frame to survive any refresh
    for _, t in ipairs(tiles) do writeTile(t[1], t[2]) end
    wrote = true
  end
  if frames == 1009 then
    local f = io.open(TRACE .. OUT .. ".png", "wb"); f:write(emu.takeScreenshot()); f:close()
    print("mockup screenshot: " .. OUT .. " (tiles=" .. #tiles .. ")")
    emu.stop(0)
  end
end, emu.eventType.endFrame)

print("mockup loaded")
